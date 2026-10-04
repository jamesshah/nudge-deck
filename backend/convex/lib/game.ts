import { ConvexError } from "convex/values";
import { internal } from "../_generated/api";
import type { Doc, Id } from "../_generated/dataModel";
import type { MutationCtx, QueryCtx } from "../_generated/server";
import { requireActiveCouple, requireCouple } from "./auth";
import { deliveryTime, MAX_PROOF_BYTES } from "./rules";

type ProofInput = {
  proofType: "text" | "photo" | "audio";
  proofText?: string | null;
  proofStorageId?: Id<"_storage"> | null;
};

/** Tab the iOS client should open when the user taps the push. */
export type NotifyScreen = "inbox" | "deck" | "recap" | "timeline";

/** Pending inbox items that deserve an app-icon badge. */
export async function attentionBadgeCount(
  ctx: QueryCtx | MutationCtx,
  userId: Id<"users">,
): Promise<number> {
  const user = await ctx.db.get("users", userId);
  const coupleId = user?.coupleId;
  if (!coupleId) return 0;
  const plays = await ctx.db
    .query("plays")
    .withIndex("by_couple", (q) => q.eq("coupleId", coupleId))
    .take(300);
  let count = 0;
  for (const play of plays) {
    if (play.toId === userId && play.delivered && play.state === "pending") count += 1;
    else if (play.fromId === userId && play.state === "proofSubmitted") count += 1;
  }
  return count;
}

export async function notify(
  ctx: MutationCtx,
  userId: Id<"users">,
  title: string,
  body: string,
  opts: { screen: NotifyScreen; playId?: Id<"plays"> } = { screen: "inbox" },
): Promise<void> {
  const badge = await attentionBadgeCount(ctx, userId);
  await ctx.scheduler.runAfter(0, internal.push.sendToUser, {
    userId,
    title,
    body,
    badge,
    screen: opts.screen,
    playId: opts.playId,
  });
}

function assertSeasonOpen(couple: Doc<"couples">, now: number): void {
  if (couple.endsAt !== undefined && now >= couple.endsAt) {
    throw new ConvexError("This season has ended. Check out your recap!");
  }
}

async function requireUnusedHand(
  ctx: QueryCtx,
  user: Doc<"users">,
  couple: Doc<"couples">,
  handId: Id<"hands">,
): Promise<{ hand: Doc<"hands">; card: Doc<"cards"> }> {
  const hand = await ctx.db.get("hands", handId);
  if (!hand || hand.coupleId !== couple._id || hand.ownerId !== user._id) {
    throw new ConvexError("That Nudge isn't in your Deck.");
  }
  if (hand.usedAt !== undefined) {
    throw new ConvexError("You've already used that Nudge. Every one is single use.");
  }
  const card = await ctx.db.get("cards", hand.cardId);
  if (!card) throw new ConvexError("That Nudge no longer exists.");
  return { hand, card };
}

async function requirePlayOnMe(
  ctx: QueryCtx,
  user: Doc<"users">,
  couple: Doc<"couples">,
  playId: Id<"plays">,
): Promise<Doc<"plays">> {
  const play = await ctx.db.get("plays", playId);
  if (!play || play.coupleId !== couple._id || play.toId !== user._id) {
    throw new ConvexError("That Nudge wasn't sent to you.");
  }
  if (!play.delivered) throw new ConvexError("That Nudge hasn't been delivered yet.");
  if (play.state !== "pending") {
    throw new ConvexError("That Nudge has already been answered.");
  }
  return play;
}

async function hasUnansweredPlay(
  ctx: QueryCtx,
  coupleId: Id<"couples">,
  fromId: Id<"users">,
): Promise<boolean> {
  const pending = await ctx.db
    .query("plays")
    .withIndex("by_couple_and_from_and_state", (q) =>
      q.eq("coupleId", coupleId).eq("fromId", fromId).eq("state", "pending"),
    )
    .first();
  return pending !== null;
}

export async function playCard(
  ctx: MutationCtx,
  user: Doc<"users">,
  args: { handId: Id<"hands">; stackedOnPlayId?: Id<"plays"> | null },
): Promise<Id<"plays">> {
  const { couple, partnerId } = await requireActiveCouple(ctx, user);
  const now = Date.now();
  assertSeasonOpen(couple, now);
  const { hand, card } = await requireUnusedHand(ctx, user, couple, args.handId);

  if (card.kind === "counter") {
    throw new ConvexError("Counters can only be used on a Nudge sent to you.");
  }

  let stackedOn: Doc<"plays"> | null = null;
  if (args.stackedOnPlayId) {
    stackedOn = await ctx.db.get("plays", args.stackedOnPlayId);
    if (!stackedOn || stackedOn.coupleId !== couple._id || stackedOn.toId !== user._id) {
      throw new ConvexError("You can only stack on a Nudge your person sent you.");
    }
    if (!stackedOn.delivered || (stackedOn.state !== "pending" && stackedOn.state !== "proofSubmitted")) {
      throw new ConvexError("You can only stack on a Nudge that's still in play.");
    }
  }

  if (await hasUnansweredPlay(ctx, couple._id, user._id)) {
    throw new ConvexError(
      "Your Nudge is waiting… 👀 Give them a chance to respond before sending another.",
    );
  }

  const partner = await ctx.db.get("users", partnerId);
  if (!partner) throw new ConvexError("Your person could not be found.");
  const deliverAt = deliveryTime(now, partner);
  const delivered = deliverAt <= now;

  await ctx.db.patch("hands", hand._id, { usedAt: now });
  const playId = await ctx.db.insert("plays", {
    coupleId: couple._id,
    cardId: card._id,
    handId: hand._id,
    fromId: user._id,
    toId: partnerId,
    kind: "action",
    state: "pending",
    stackedOnPlayId: stackedOn?._id,
    delivered,
    deliverAt,
    playedAt: now,
  });

  if (delivered) {
    await notifyPlayDelivered(ctx, user.name, partnerId, card.title, stackedOn !== null, playId);
  } else {
    const deliverJobId = await ctx.scheduler.runAt(deliverAt, internal.plays.deliver, { playId });
    await ctx.db.patch("plays", playId, { deliverJobId });
  }
  return playId;
}

async function notifyPlayDelivered(
  ctx: MutationCtx,
  _fromName: string,
  toId: Id<"users">,
  _cardTitle: string,
  stacked: boolean,
  playId: Id<"plays">,
): Promise<void> {
  await notify(
    ctx,
    toId,
    "👀 You've been nudged.",
    stacked
      ? "Someone stacked another Nudge on you."
      : "Your person sent you something.",
    { screen: "inbox", playId },
  );
}

export async function deliverPlay(ctx: MutationCtx, playId: Id<"plays">): Promise<void> {
  const play = await ctx.db.get("plays", playId);
  if (!play || play.delivered) return;
  const couple = await ctx.db.get("couples", play.coupleId);
  // Unpaired couples never deliver. After a season ends, only allow a delivery that
  // was already due by endsAt (same-tick with endSeason); later quiet-hours holds stay dark.
  if (
    !couple ||
    couple.deletedAt !== undefined ||
    (couple.status !== "active" &&
      (couple.endsAt === undefined || play.deliverAt > couple.endsAt))
  ) {
    if (play.deliverJobId) {
      await ctx.db.patch("plays", playId, { deliverJobId: undefined });
    }
    return;
  }
  await ctx.db.patch("plays", playId, { delivered: true, deliverJobId: undefined });
  const [from, card] = await Promise.all([
    ctx.db.get("users", play.fromId),
    ctx.db.get("cards", play.cardId),
  ]);
  await notifyPlayDelivered(
    ctx,
    from?.name ?? "Your partner",
    play.toId,
    card?.title ?? "A new card",
    play.stackedOnPlayId !== undefined,
    playId,
  );
}

export async function counterPlay(
  ctx: MutationCtx,
  user: Doc<"users">,
  args: { handId: Id<"hands">; targetPlayId: Id<"plays"> },
): Promise<Id<"plays">> {
  const { couple, partnerId } = await requireActiveCouple(ctx, user);
  const now = Date.now();
  assertSeasonOpen(couple, now);
  const { hand, card } = await requireUnusedHand(ctx, user, couple, args.handId);
  if (card.kind !== "counter") {
    throw new ConvexError("Only counter Nudges can block one that's on you.");
  }
  const target = await requirePlayOnMe(ctx, user, couple, args.targetPlayId);

  await ctx.db.patch("hands", hand._id, { usedAt: now });
  const counterId = await ctx.db.insert("plays", {
    coupleId: couple._id,
    cardId: card._id,
    handId: hand._id,
    fromId: user._id,
    toId: partnerId,
    kind: "counter",
    state: "completed",
    counteredPlayId: target._id,
    delivered: true,
    deliverAt: now,
    playedAt: now,
    respondedAt: now,
  });
  await ctx.db.patch("plays", target._id, {
    state: "countered",
    counteredByPlayId: counterId,
    respondedAt: now,
  });

  await notify(
    ctx,
    partnerId,
    `${user.name} blocked your Nudge`,
    "We'll pretend that didn't happen.",
    { screen: "timeline", playId: target._id },
  );
  return counterId;
}

export async function refusePlay(
  ctx: MutationCtx,
  user: Doc<"users">,
  args: { playId: Id<"plays"> },
  random: () => number = Math.random,
): Promise<void> {
  const { couple } = await requireCouple(ctx, user, { mustBeActive: false });
  const play = await requirePlayOnMe(ctx, user, couple, args.playId);
  const now = Date.now();

  const myHand = await ctx.db
    .query("hands")
    .withIndex("by_couple_and_owner", (q) =>
      q.eq("coupleId", couple._id).eq("ownerId", user._id),
    )
    .collect();
  const stealable = myHand.filter((h) => h.usedAt === undefined);
  const stolen =
    stealable.length > 0 ? stealable[Math.floor(random() * stealable.length)]! : null;

  if (stolen) {
    await ctx.db.patch("hands", stolen._id, {
      ownerId: play.fromId,
      stolenFromId: user._id,
      acquiredAt: now,
    });
  }
  await ctx.db.patch("plays", play._id, {
    state: "refused",
    respondedAt: now,
    stolenHandId: stolen?._id,
  });

  await notify(
    ctx,
    play.fromId,
    `${user.name} passed`,
    stolen
      ? "You stole a Nudge from their Deck. Nudge them back?"
      : "Their Deck was empty, so there was nothing to steal.",
    { screen: stolen ? "deck" : "timeline", playId: play._id },
  );
}

async function assertProofFileSize(
  ctx: MutationCtx,
  storageId: Id<"_storage">,
): Promise<void> {
  const meta = await ctx.db.system.get("_storage", storageId);
  if (!meta) {
    throw new ConvexError("That proof file is missing. Try uploading again.");
  }
  if (meta.size > MAX_PROOF_BYTES) {
    await ctx.storage.delete(storageId);
    throw new ConvexError("Keep photo and voice note proofs under 3 MB.");
  }
}

export async function completeWithProof(
  ctx: MutationCtx,
  user: Doc<"users">,
  args: { playId: Id<"plays"> } & ProofInput,
): Promise<void> {
  const { couple } = await requireCouple(ctx, user, { mustBeActive: false });
  const play = await requirePlayOnMe(ctx, user, couple, args.playId);

  const text = args.proofText?.trim() || undefined;
  if (args.proofType === "text" && !text) {
    throw new ConvexError("Write a short note as proof.");
  }
  if (args.proofType !== "text" && !args.proofStorageId) {
    throw new ConvexError(`Attach a ${args.proofType === "photo" ? "photo" : "voice note"} as proof.`);
  }
  if (text && text.length > 1000) throw new ConvexError("Keep your note under 1000 characters.");
  if (args.proofStorageId) {
    await assertProofFileSize(ctx, args.proofStorageId);
  }

  await ctx.db.patch("plays", play._id, {
    state: "proofSubmitted",
    proofType: args.proofType,
    proofText: text,
    proofStorageId: args.proofStorageId ?? undefined,
    proofRejectedNote: undefined,
    respondedAt: Date.now(),
  });
  await notify(
    ctx,
    play.fromId,
    `${user.name} sent proof`,
    "A Nudge is waiting for your review.",
    { screen: "inbox", playId: play._id },
  );
}

async function requireProofToReview(
  ctx: QueryCtx,
  user: Doc<"users">,
  playId: Id<"plays">,
): Promise<Doc<"plays">> {
  const { couple } = await requireCouple(ctx, user, { mustBeActive: false });
  const play = await ctx.db.get("plays", playId);
  if (!play || play.coupleId !== couple._id || play.fromId !== user._id) {
    throw new ConvexError("Only the person who sent this Nudge can review the proof.");
  }
  if (play.state !== "proofSubmitted") throw new ConvexError("There's no proof waiting on this Nudge.");
  return play;
}

export async function acceptProof(
  ctx: MutationCtx,
  user: Doc<"users">,
  args: { playId: Id<"plays"> },
): Promise<void> {
  const play = await requireProofToReview(ctx, user, args.playId);
  await ctx.db.patch("plays", play._id, { state: "completed" });
  await notify(ctx, play.toId, "Nudge complete 🫡", "Nice work.", {
    screen: "timeline",
    playId: play._id,
  });
}

export async function rejectProof(
  ctx: MutationCtx,
  user: Doc<"users">,
  args: { playId: Id<"plays">; note?: string | null },
): Promise<void> {
  const play = await requireProofToReview(ctx, user, args.playId);
  const note = args.note?.trim() || "Not quite. Try again!";
  if (play.proofStorageId) await ctx.storage.delete(play.proofStorageId);
  await ctx.db.patch("plays", play._id, {
    state: "pending",
    proofType: undefined,
    proofText: undefined,
    proofStorageId: undefined,
    proofRejectedNote: note.slice(0, 280),
  });
  await notify(ctx, play.toId, `${user.name} wants another try`, "Someone wants your attention.", {
    screen: "inbox",
    playId: play._id,
  });
}

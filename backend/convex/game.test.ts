/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import { deliveryTime, isInQuietHours } from "./lib/rules";
import schema from "./schema";
import { apnsConfigured, normalizeApnsPrivateKey } from "./lib/apnsConfig";
import { SEED_CARDS } from "./seedData";

const modules = import.meta.glob("./**/*.ts");

type T = ReturnType<typeof convexTest>;

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date("2026-01-10T12:00:00Z"));
  vi.stubEnv("ALLOW_DEV_SIGNIN", "true");
});

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
});

async function setupCouple(opts: { bobOffset?: number; bobTimeZone?: string } = {}) {
  const t = convexTest(schema, modules);
  await t.mutation(internal.seed.run, {});
  const alice = await t.mutation(api.auth.signInDev, {
    name: "Alice",
    timeZone: "Europe/London",
    utcOffsetMinutes: 0,
  });
  const bob = await t.mutation(api.auth.signInDev, {
    name: "Bob",
    timeZone: opts.bobTimeZone ?? "UTC",
    utcOffsetMinutes: opts.bobOffset ?? 0,
  });
  await t.mutation(api.couples.create, { sessionToken: alice, timeframeDays: 30 });
  const invite = await t.query(api.couples.current, { sessionToken: alice });
  await t.mutation(api.couples.join, {
    sessionToken: bob,
    inviteCode: ` ${invite!.inviteCode.toLowerCase()} `,
  });
  return { t, alice, bob };
}

async function hand(t: T, token: string) {
  return await t.query(api.cards.myHand, { sessionToken: token });
}

async function actionCard(t: T, token: string, index = 0) {
  const cards = (await hand(t, token)).cards.filter((c) => c.kind === "action");
  return cards[index]!.handId;
}

async function counterCard(t: T, token: string) {
  return (await hand(t, token)).cards.find((c) => c.kind === "counter")!.handId;
}

async function incoming(t: T, token: string) {
  return (await t.query(api.plays.inbox, { sessionToken: token })).incoming;
}

async function play(t: T, token: string, handId: Id<"hands">, stackedOnPlayId?: Id<"plays">) {
  await t.mutation(api.plays.playCard, { sessionToken: token, handId, stackedOnPlayId });
}

describe("deck and pairing", () => {
  test("seed has an original 60-card deck with counters and is idempotent", async () => {
    expect(SEED_CARDS).toHaveLength(60);
    expect(SEED_CARDS.filter((c) => c.kind === "counter")).toHaveLength(6);
    expect(new Set(SEED_CARDS.map((c) => c.slug)).size).toBe(60);

    const t = convexTest(schema, modules);
    expect(await t.mutation(internal.seed.run, {})).toEqual({ inserted: 60, updated: 0 });
    expect(await t.mutation(internal.seed.run, {})).toEqual({ inserted: 0, updated: 60 });
  });

  test("joining deals each player a unique half of the deck", async () => {
    const { t, alice, bob } = await setupCouple();
    const a = await hand(t, alice);
    const b = await hand(t, bob);
    expect(a.cards).toHaveLength(30);
    expect(b.cards).toHaveLength(30);
    expect(a.cards.filter((c) => c.kind === "counter")).toHaveLength(3);
    expect(b.cards.filter((c) => c.kind === "counter")).toHaveLength(3);
    const aIds = new Set(a.cards.map((c) => c.cardId));
    expect(b.cards.some((c) => aIds.has(c.cardId))).toBe(false);

    const couple = await t.query(api.couples.current, { sessionToken: bob });
    expect(couple?.status).toBe("active");
    expect(couple?.partner?.name).toBe("Alice");
    expect(couple?.endsAt).toBe(Date.now() + 30 * 24 * 60 * 60 * 1000);
  });

  test("invalid sessions are rejected and me() returns null", async () => {
    const t = convexTest(schema, modules);
    expect(await t.query(api.users.me, { sessionToken: "nope" })).toBeNull();
    await expect(t.query(api.cards.myHand, { sessionToken: "nope" })).rejects.toThrow(/session/);
  });
});

describe("dev sign-in", () => {
  const args = { name: "Casey", timeZone: "UTC", utcOffsetMinutes: 0 };

  test("works when ALLOW_DEV_SIGNIN=true", async () => {
    const t = convexTest(schema, modules);
    const token = await t.mutation(api.auth.signInDev, args);
    expect((await t.query(api.users.me, { sessionToken: token }))?.name).toBe("Casey");
  });

  test.each([undefined, "false", "1"])("is rejected when ALLOW_DEV_SIGNIN is %s", async (value) => {
    if (value === undefined) delete process.env.ALLOW_DEV_SIGNIN;
    else vi.stubEnv("ALLOW_DEV_SIGNIN", value);
    const t = convexTest(schema, modules);
    await expect(t.mutation(api.auth.signInDev, args)).rejects.toThrow(/turned off/);
  });
});

describe("apple sign-in names", () => {
  const device = { timeZone: "UTC", utcOffsetMinutes: 0 };

  test("stores the provided name on first sign-in", async () => {
    const t = convexTest(schema, modules);
    const token = await t.mutation(internal.auth.upsertAppleUser, {
      appleSub: "apple.jamie",
      name: "Jamie",
      ...device,
    });
    expect((await t.query(api.users.me, { sessionToken: token }))?.name).toBe("Jamie");
  });

  test("upgrades the Player placeholder without overwriting a chosen name", async () => {
    const t = convexTest(schema, modules);
    const placeholder = await t.mutation(internal.auth.upsertAppleUser, {
      appleSub: "apple.alex",
      ...device,
    });
    expect((await t.query(api.users.me, { sessionToken: placeholder }))?.name).toBe("Player");

    const upgraded = await t.mutation(internal.auth.upsertAppleUser, {
      appleSub: "apple.alex",
      name: "Alex",
      ...device,
    });
    expect((await t.query(api.users.me, { sessionToken: upgraded }))?.name).toBe("Alex");

    const again = await t.mutation(internal.auth.upsertAppleUser, {
      appleSub: "apple.alex",
      name: "ShouldNotOverwrite",
      ...device,
    });
    expect((await t.query(api.users.me, { sessionToken: again }))?.name).toBe("Alex");
  });
});

describe("rules", () => {
  test("every card is single use", async () => {
    const { t, alice, bob } = await setupCouple();
    const handId = await actionCard(t, alice);
    await play(t, alice, handId);
    expect((await hand(t, alice)).cards.some((c) => c.handId === handId)).toBe(false);

    const [p] = await incoming(t, bob);
    await t.mutation(api.plays.completeWithProof, {
      sessionToken: bob,
      playId: p!._id,
      proofType: "text",
      proofText: "Done!",
    });
    await t.mutation(api.plays.acceptProof, { sessionToken: alice, playId: p!._id });

    await expect(play(t, alice, handId)).rejects.toThrow(/single use/);
  });

  test("you can't play a second card before your partner responds", async () => {
    const { t, alice, bob } = await setupCouple();
    await play(t, alice, await actionCard(t, alice, 0));
    await expect(play(t, alice, await actionCard(t, alice, 0))).rejects.toThrow(
      /chance to respond/,
    );

    const [p] = await incoming(t, bob);
    await t.mutation(api.plays.completeWithProof, {
      sessionToken: bob,
      playId: p!._id,
      proofType: "text",
      proofText: "On it",
    });
    await play(t, alice, await actionCard(t, alice, 0));
    const states = (await incoming(t, bob)).map((x) => x.state).sort();
    expect(states).toEqual(["pending", "proofSubmitted"]);
  });

  test("cards stack on each other without cancelling", async () => {
    const { t, alice, bob } = await setupCouple();
    await play(t, alice, await actionCard(t, alice));
    const [base] = await incoming(t, bob);

    await expect(play(t, alice, await actionCard(t, alice), base!._id)).rejects.toThrow(
      /only stack on a Nudge your person sent you/,
    );

    await play(t, bob, await actionCard(t, bob), base!._id);

    const bobIncoming = await incoming(t, bob);
    expect(bobIncoming).toHaveLength(1);
    expect(bobIncoming[0]!.state).toBe("pending");

    const [stack] = await incoming(t, alice);
    expect(stack!.stackedOnPlayId).toBe(base!._id);
    expect(stack!.stackedOnTitle).toBe(base!.title);
  });

  test("stacking requires the base card to still be in play", async () => {
    const { t, alice, bob } = await setupCouple();
    await play(t, alice, await actionCard(t, alice));
    const [base] = await incoming(t, bob);
    await t.mutation(api.plays.refuse, { sessionToken: bob, playId: base!._id });
    await expect(play(t, bob, await actionCard(t, bob), base!._id)).rejects.toThrow(
      /still in play/,
    );
  });

  test("counter cards knock a played card out of the game", async () => {
    const { t, alice, bob } = await setupCouple();
    await expect(play(t, alice, await counterCard(t, alice))).rejects.toThrow(
      /Counters can only be used/,
    );

    await play(t, alice, await actionCard(t, alice));
    const [target] = await incoming(t, bob);

    await expect(
      t.mutation(api.plays.counter, {
        sessionToken: bob,
        handId: await actionCard(t, bob),
        targetPlayId: target!._id,
      }),
    ).rejects.toThrow(/Only counter Nudges/);

    const counterHandId = await counterCard(t, bob);
    await t.mutation(api.plays.counter, {
      sessionToken: bob,
      handId: counterHandId,
      targetPlayId: target!._id,
    });

    expect(await incoming(t, bob)).toHaveLength(0);
    const timeline = await t.query(api.plays.timeline, { sessionToken: alice });
    expect(timeline.find((p) => p._id === target!._id)?.state).toBe("countered");
    const counterPlay = timeline.find((p) => p.kind === "counter");
    expect(counterPlay?.counteredTitle).toBe(target!.title);
    expect((await hand(t, bob)).cards.some((c) => c.handId === counterHandId)).toBe(false);

    await expect(
      t.mutation(api.plays.counter, {
        sessionToken: bob,
        handId: await counterCard(t, bob),
        targetPlayId: target!._id,
      }),
    ).rejects.toThrow(/already been answered/);

    // The sender's card is resolved, so they can play again.
    await play(t, alice, await actionCard(t, alice));
  });

  test("refusing a card lets the sender steal one from your hand", async () => {
    const { t, alice, bob } = await setupCouple();
    await play(t, alice, await actionCard(t, alice));
    const [p] = await incoming(t, bob);

    await t.mutation(api.plays.refuse, { sessionToken: bob, playId: p!._id });

    const a = await hand(t, alice);
    const b = await hand(t, bob);
    expect(a.cards).toHaveLength(30);
    expect(b.cards).toHaveLength(29);
    const stolen = a.cards.find((c) => c.stolenFromName === "Bob");
    expect(stolen).toBeDefined();

    const timeline = await t.query(api.plays.timeline, { sessionToken: bob });
    expect(timeline[0]!.state).toBe("refused");
    expect(timeline[0]!.stolenCardTitle).toBe(stolen!.title);

    if (stolen!.kind === "action") {
      await play(t, alice, stolen!.handId);
      expect((await incoming(t, bob))[0]!.title).toBe(stolen!.title);
    }

    const recap = await t.query(api.couples.recap, { sessionToken: alice });
    const aliceStats = recap!.players.find((s) => s.name === "Alice")!;
    const bobStats = recap!.players.find((s) => s.name === "Bob")!;
    expect(aliceStats.cardsStolen).toBe(1);
    expect(aliceStats.refusedByPartner).toBe(1);
    expect(bobStats.refused).toBe(1);
  });

  test("recap puts the partner left and signed-in player right for both players", async () => {
    const { t, alice, bob } = await setupCouple();
    const asAlice = await t.query(api.couples.recap, { sessionToken: alice });
    const asBob = await t.query(api.couples.recap, { sessionToken: bob });
    expect(asAlice!.players.map((p) => p.name)).toEqual(["Bob", "Alice"]);
    expect(asBob!.players.map((p) => p.name)).toEqual(["Alice", "Bob"]);
  });

  test("proof must be attached and accepted by the sender", async () => {
    const { t, alice, bob } = await setupCouple();
    await play(t, alice, await actionCard(t, alice));
    const [p] = await incoming(t, bob);

    await expect(
      t.mutation(api.plays.completeWithProof, {
        sessionToken: bob,
        playId: p!._id,
        proofType: "text",
        proofText: "   ",
      }),
    ).rejects.toThrow(/short note/);
    await expect(
      t.mutation(api.plays.completeWithProof, {
        sessionToken: bob,
        playId: p!._id,
        proofType: "photo",
        proofText: null,
        proofStorageId: null,
      }),
    ).rejects.toThrow(/Attach a photo/);

    const oversized = await t.run(async (ctx) =>
      ctx.storage.store(new Blob([new Uint8Array(3 * 1024 * 1024 + 1)])),
    );
    await expect(
      t.mutation(api.plays.completeWithProof, {
        sessionToken: bob,
        playId: p!._id,
        proofType: "photo",
        proofStorageId: oversized,
      }),
    ).rejects.toThrow(/under 3 MB/);

    const storageId = await t.run(async (ctx) => ctx.storage.store(new Blob(["jpeg-bytes"])));
    await t.mutation(api.plays.completeWithProof, {
      sessionToken: bob,
      playId: p!._id,
      proofType: "photo",
      proofStorageId: storageId,
    });

    const review = (await t.query(api.plays.inbox, { sessionToken: alice })).toReview;
    expect(review).toHaveLength(1);
    expect(review[0]!.proofType).toBe("photo");
    expect(review[0]!.proofUrl).toBeTruthy();

    await expect(
      t.mutation(api.plays.acceptProof, { sessionToken: bob, playId: p!._id }),
    ).rejects.toThrow(/Only the person who sent/);

    await t.mutation(api.plays.rejectProof, {
      sessionToken: alice,
      playId: p!._id,
      note: "Show the whole view!",
    });
    const retry = (await incoming(t, bob))[0]!;
    expect(retry.state).toBe("pending");
    expect(retry.proofRejectedNote).toBe("Show the whole view!");

    await t.mutation(api.plays.completeWithProof, {
      sessionToken: bob,
      playId: p!._id,
      proofType: "text",
      proofText: "Here's the whole view",
    });
    await t.mutation(api.plays.acceptProof, { sessionToken: alice, playId: p!._id });
    const timeline = await t.query(api.plays.timeline, { sessionToken: bob });
    expect(timeline[0]!.state).toBe("completed");
    expect(timeline[0]!.proofRejectedNote).toBeUndefined();
  });

  test("cards played during quiet hours are delivered when they end", async () => {
    // Bob is UTC-5 with quiet hours 22:00-07:00 local.
    const { t, alice, bob } = await setupCouple({
      bobOffset: -300,
      bobTimeZone: "America/New_York",
    });
    await t.mutation(api.users.setQuietHours, {
      sessionToken: bob,
      startMinutes: 22 * 60,
      endMinutes: 7 * 60,
    });

    // 04:30 UTC = 23:30 for Bob.
    vi.setSystemTime(new Date("2026-01-11T04:30:00Z"));
    await play(t, alice, await actionCard(t, alice));

    expect(await incoming(t, bob)).toHaveLength(0);
    expect(await t.query(api.plays.timeline, { sessionToken: bob })).toHaveLength(0);
    const [scheduled] = await t.query(api.plays.timeline, { sessionToken: alice });
    expect(scheduled!.delivered).toBe(false);
    // 07:00 for Bob = 12:00 UTC.
    expect(scheduled!.deliverAt).toBe(Date.parse("2026-01-11T12:00:00Z"));

    vi.advanceTimersByTime(7.5 * 60 * 60 * 1000 - 1000);
    await t.finishInProgressScheduledFunctions();
    expect(await incoming(t, bob)).toHaveLength(0);

    vi.advanceTimersByTime(1000);
    await t.finishInProgressScheduledFunctions();
    const delivered = await incoming(t, bob);
    expect(delivered).toHaveLength(1);
    expect(delivered[0]!.delivered).toBe(true);
    expect(await t.query(api.plays.timeline, { sessionToken: bob })).toHaveLength(1);
  });

  test("the target can't respond to a card that hasn't been delivered", async () => {
    const { t, alice, bob } = await setupCouple();
    await t.mutation(api.users.setQuietHours, { sessionToken: bob, startMinutes: 0, endMinutes: 1439 });
    await play(t, alice, await actionCard(t, alice));
    const [scheduled] = await t.query(api.plays.timeline, { sessionToken: alice });
    await expect(
      t.mutation(api.plays.refuse, { sessionToken: bob, playId: scheduled!._id }),
    ).rejects.toThrow(/hasn't been delivered/);
  });

  test("unpair cancels endSeason and pending quiet-hours delivery jobs", async () => {
    const { t, alice, bob } = await setupCouple({
      bobOffset: -300,
      bobTimeZone: "America/New_York",
    });
    await t.mutation(api.users.setQuietHours, {
      sessionToken: bob,
      startMinutes: 22 * 60,
      endMinutes: 7 * 60,
    });
    vi.setSystemTime(new Date("2026-01-11T04:30:00Z"));
    await play(t, alice, await actionCard(t, alice));
    const [held] = await t.query(api.plays.timeline, { sessionToken: alice });
    const coupleId = (await t.query(api.couples.current, { sessionToken: alice }))!._id;
    const before = await t.run(async (ctx) => {
      const couple = await ctx.db.get("couples", coupleId);
      const playRow = await ctx.db.get("plays", held!._id);
      return {
        endSeasonJobId: couple!.endSeasonJobId!,
        deliverJobId: playRow!.deliverJobId!,
      };
    });
    expect(before.endSeasonJobId).toBeDefined();
    expect(before.deliverJobId).toBeDefined();

    await t.mutation(api.couples.unpair, { sessionToken: alice });

    const after = await t.run(async (ctx) => {
      const couple = await ctx.db.get("couples", coupleId);
      const playRow = await ctx.db.get("plays", held!._id);
      const endJob = await ctx.db.system.get("_scheduled_functions", before.endSeasonJobId);
      const deliverJob = await ctx.db.system.get("_scheduled_functions", before.deliverJobId);
      return {
        coupleEndJobId: couple?.endSeasonJobId,
        playDeliverJobId: playRow?.deliverJobId,
        playDelivered: playRow?.delivered,
        endJobState: endJob?.state.kind,
        deliverJobState: deliverJob?.state.kind,
      };
    });
    expect(after.coupleEndJobId).toBeUndefined();
    expect(after.playDeliverJobId).toBeUndefined();
    expect(after.playDelivered).toBe(false);
    expect(after.endJobState).toBe("canceled");
    expect(after.deliverJobState).toBe("canceled");

    vi.advanceTimersByTime(8 * 60 * 60 * 1000);
    await t.finishInProgressScheduledFunctions();
    const playRow = await t.run(async (ctx) => ctx.db.get("plays", held!._id));
    expect(playRow?.delivered).toBe(false);
  });

  test("startNewSeason cancels the previous endSeason timer", async () => {
    const { t, alice, bob } = await setupCouple();
    const oldId = (await t.query(api.couples.current, { sessionToken: alice }))!._id;
    const oldJobId = await t.run(async (ctx) => (await ctx.db.get("couples", oldId))!.endSeasonJobId!);
    expect(oldJobId).toBeDefined();

    await t.mutation(api.couples.startNewSeason, { sessionToken: alice, timeframeDays: 180 });
    const newId = (await t.query(api.couples.current, { sessionToken: bob }))!._id;
    expect(newId).not.toBe(oldId);

    const after = await t.run(async (ctx) => {
      const old = await ctx.db.get("couples", oldId);
      const neu = await ctx.db.get("couples", newId);
      const oldJob = await ctx.db.system.get("_scheduled_functions", oldJobId);
      return {
        oldStatus: old?.status,
        oldJobId: old?.endSeasonJobId,
        oldJobState: oldJob?.state.kind,
        newJobId: neu?.endSeasonJobId,
        newStatus: neu?.status,
      };
    });
    expect(after.oldStatus).toBe("ended");
    expect(after.oldJobId).toBeUndefined();
    expect(after.oldJobState).toBe("canceled");
    expect(after.newJobId).toBeDefined();
    expect(after.newStatus).toBe("active");
    expect(after.newJobId).not.toBe(oldJobId);
  });

  test("plays held for quiet hours stay undelivered after the season ends", async () => {
    const { t, alice, bob } = await setupCouple({
      bobOffset: -300,
      bobTimeZone: "America/New_York",
    });
    await t.mutation(api.users.setQuietHours, {
      sessionToken: bob,
      startMinutes: 22 * 60,
      endMinutes: 7 * 60,
    });
    // Hold a Nudge, then end early via startNewSeason so deliver would be after the old season.
    vi.setSystemTime(new Date("2026-01-11T04:30:00Z"));
    await play(t, alice, await actionCard(t, alice));
    const [held] = await t.query(api.plays.timeline, { sessionToken: alice });
    const oldId = (await t.query(api.couples.current, { sessionToken: alice }))!._id;

    await t.mutation(api.couples.startNewSeason, { sessionToken: alice, timeframeDays: 7 });
    expect((await t.query(api.couples.current, { sessionToken: alice }))?._id).not.toBe(oldId);

    vi.advanceTimersByTime(8 * 60 * 60 * 1000);
    await t.finishInProgressScheduledFunctions();
    const playRow = await t.run(async (ctx) => ctx.db.get("plays", held!._id));
    expect(playRow?.delivered).toBe(false);
    expect(playRow?.coupleId).toBe(oldId);
  });

  test("no cards can be played after the season ends", async () => {
    const { t, alice } = await setupCouple();
    const handId = await actionCard(t, alice);
    vi.advanceTimersByTime(30 * 24 * 60 * 60 * 1000);
    await t.finishInProgressScheduledFunctions();
    expect((await t.query(api.couples.current, { sessionToken: alice }))?.status).toBe("ended");
    await expect(play(t, alice, handId)).rejects.toThrow(/season has ended/);
  });

  test("either player can unpair during an active season", async () => {
    const { t, alice, bob } = await setupCouple();
    const before = (await t.query(api.couples.current, { sessionToken: alice }))!._id;
    await t.mutation(api.couples.unpair, { sessionToken: alice });
    expect(await t.query(api.couples.current, { sessionToken: alice })).toBeNull();
    expect(await t.query(api.couples.current, { sessionToken: bob })).toBeNull();
    expect((await t.query(api.users.me, { sessionToken: alice }))?.coupleId).toBeUndefined();
    expect((await t.query(api.users.me, { sessionToken: bob }))?.coupleId).toBeUndefined();
    const archived = await t.run(async (ctx) => ctx.db.get("couples", before));
    expect(archived?.status).toBe("ended");
    expect(archived?.deletedAt).toBeDefined();
  });

  test("players can unpair after a season has already ended", async () => {
    const { t, alice, bob } = await setupCouple();
    const coupleId = (await t.query(api.couples.current, { sessionToken: alice }))!._id;
    vi.advanceTimersByTime(30 * 24 * 60 * 60 * 1000);
    await t.finishInProgressScheduledFunctions();
    expect((await t.query(api.couples.current, { sessionToken: alice }))?.status).toBe("ended");
    await t.mutation(api.couples.unpair, { sessionToken: bob });
    expect(await t.query(api.couples.current, { sessionToken: alice })).toBeNull();
    expect(await t.query(api.couples.current, { sessionToken: bob })).toBeNull();
    const archived = await t.run(async (ctx) => ctx.db.get("couples", coupleId));
    expect(archived?.status).toBe("ended");
    expect(archived?.deletedAt).toBeDefined();
  });

  test("unpair is rejected while waiting for a partner", async () => {
    const t = convexTest(schema, modules);
    await t.mutation(internal.seed.run, {});
    const alice = await t.mutation(api.auth.signInDev, {
      name: "Alice",
      timeZone: "UTC",
      utcOffsetMinutes: 0,
    });
    await t.mutation(api.couples.create, { sessionToken: alice, timeframeDays: 7 });
    await expect(t.mutation(api.couples.unpair, { sessionToken: alice })).rejects.toThrow(/Cancel the invite/);
  });

  test("startNewSeason from an active season deals a fresh deck", async () => {
    const { t, alice, bob } = await setupCouple();
    const oldId = (await t.query(api.couples.current, { sessionToken: alice }))!._id;
    const oldHand = (await hand(t, alice)).cards.map((c) => c.handId);
    await t.mutation(api.couples.startNewSeason, { sessionToken: alice, timeframeDays: 7 });
    const current = await t.query(api.couples.current, { sessionToken: alice });
    expect(current?.status).toBe("active");
    expect(current?.timeframeDays).toBe(7);
    expect(current?._id).not.toBe(oldId);
    expect((await t.query(api.couples.current, { sessionToken: bob }))!._id).toBe(current!._id);
    const newHand = (await hand(t, alice)).cards.map((c) => c.handId);
    expect(newHand).not.toEqual(oldHand);
    await play(t, alice, await actionCard(t, alice));
    const old = await t.run(async (ctx) => ctx.db.get("couples", oldId));
    expect(old?.status).toBe("ended");
    expect(old?.deletedAt).toBeUndefined();
  });

  test("startNewSeason after natural end starts a new active season", async () => {
    const { t, alice, bob } = await setupCouple();
    vi.advanceTimersByTime(30 * 24 * 60 * 60 * 1000);
    await t.finishInProgressScheduledFunctions();
    expect((await t.query(api.couples.current, { sessionToken: alice }))?.status).toBe("ended");
    await t.mutation(api.couples.startNewSeason, { sessionToken: bob, timeframeDays: 90 });
    expect((await t.query(api.couples.current, { sessionToken: alice }))?.status).toBe("active");
    expect((await t.query(api.couples.current, { sessionToken: alice }))?.timeframeDays).toBe(90);
    await play(t, bob, await actionCard(t, bob));
  });

  test("join rejects a soft-deleted invite", async () => {
    const { t, alice, bob } = await setupCouple();
    const inviteCode = (await t.query(api.couples.current, { sessionToken: alice }))!.inviteCode;
    await t.mutation(api.couples.unpair, { sessionToken: alice });
    const carol = await t.mutation(api.auth.signInDev, {
      name: "Carol",
      timeZone: "UTC",
      utcOffsetMinutes: 0,
    });
    await expect(
      t.mutation(api.couples.join, { sessionToken: carol, inviteCode }),
    ).rejects.toThrow(/doesn't match an open invite/);
    expect(await t.query(api.couples.current, { sessionToken: bob })).toBeNull();
  });

  test("a new custom card is first without reshuffling the existing hand", async () => {
    const { t, alice } = await setupCouple();
    const before = (await hand(t, alice)).cards.map((card) => card.handId);
    await t.mutation(api.cards.createCustom, {
      sessionToken: alice,
      title: "Our newest card",
      body: "This should be first.",
    });
    const after = (await hand(t, alice)).cards;
    expect(after[0]!.title).toBe("Our newest card");
    expect(after[0]!.isCustom).toBe(true);
    expect(after.slice(1).map((card) => card.handId)).toEqual(before);
  });

  test("players can write up to five custom cards", async () => {
    const { t, alice } = await setupCouple();
    for (let i = 1; i <= 5; i++) {
      await t.mutation(api.cards.createCustom, {
        sessionToken: alice,
        title: `Custom card ${i}`,
        body: "Something only we would get.",
      });
    }
    await expect(
      t.mutation(api.cards.createCustom, { sessionToken: alice, title: "One more", body: "" }),
    ).rejects.toThrow(/up to 5/);
    const h = await hand(t, alice);
    expect(h.cards.filter((c) => c.isCustom)).toHaveLength(5);
    expect(h.customCardsLeftToWrite).toBe(0);
  });
});

describe("quiet hours math", () => {
  const q = { utcOffsetMinutes: 330, quietStartMinutes: 23 * 60, quietEndMinutes: 8 * 60 };

  test("wraps around midnight in the player's local time", () => {
    // 18:00 UTC = 23:30 IST.
    expect(isInQuietHours(Date.parse("2026-03-01T18:00:00Z"), q)).toBe(true);
    // 03:00 UTC = 08:30 IST.
    expect(isInQuietHours(Date.parse("2026-03-01T03:00:00Z"), q)).toBe(false);
    expect(deliveryTime(Date.parse("2026-03-01T18:00:00Z"), q)).toBe(
      Date.parse("2026-03-02T02:30:00Z"),
    );
  });

  test("delivers immediately outside quiet hours or when unset", () => {
    const now = Date.parse("2026-03-01T06:00:00Z");
    expect(deliveryTime(now, q)).toBe(now);
    expect(deliveryTime(now, { utcOffsetMinutes: 0 })).toBe(now);
  });

  test("uses the IANA timezone instead of a stale device offset", () => {
    const losAngeles = {
      timeZone: "America/Los_Angeles",
      utcOffsetMinutes: 0, // deliberately stale/wrong
      quietStartMinutes: 22 * 60,
      quietEndMinutes: 7 * 60,
    };
    // July 1 06:30 UTC = June 30 23:30 PDT.
    const now = Date.parse("2026-07-01T06:30:00Z");
    expect(isInQuietHours(now, losAngeles)).toBe(true);
    expect(deliveryTime(now, losAngeles)).toBe(Date.parse("2026-07-01T14:00:00Z"));
  });

  test("the end minute is released, not held for another day", () => {
    const overnight = { utcOffsetMinutes: -300, quietStartMinutes: 22 * 60, quietEndMinutes: 7 * 60 };
    const oneMinuteBefore = Date.parse("2026-01-11T11:59:00Z");
    const exactlyAtEnd = Date.parse("2026-01-11T12:00:00Z");
    expect(isInQuietHours(oneMinuteBefore, overnight)).toBe(true);
    expect(deliveryTime(oneMinuteBefore, overnight)).toBe(exactlyAtEnd);
    expect(isInQuietHours(exactlyAtEnd, overnight)).toBe(false);
    expect(deliveryTime(exactlyAtEnd, overnight)).toBe(exactlyAtEnd);
  });
});

describe("APNs configuration", () => {
  test("requires all four provider values", () => {
    vi.stubEnv("APNS_KEY_ID", "KEY123");
    vi.stubEnv("APNS_TEAM_ID", "TEAM123");
    vi.stubEnv("APNS_PRIVATE_KEY", "PRIVATE KEY");
    expect(apnsConfigured()).toBe(false);
    vi.stubEnv("APNS_TOPIC", "com.jamesshah.nudgedeck");
    expect(apnsConfigured()).toBe(true);
  });

  test("rebuilds a PEM when env newlines were mangled", () => {
    const body =
      "MIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQgAAAAAAAAAAAAAAAAAAAA" +
      "AAAAAAAAAAAAAAAAAAAAoFcGCSqGSIb3DQEJDzFBBBBB";
    const oneLine = `"-----BEGIN PRIVATE KEY-----${body}-----END PRIVATE KEY-----"`;
    const escaped = `-----BEGIN PRIVATE KEY-----\\n${body}\\n-----END PRIVATE KEY-----\\n`;
    for (const raw of [oneLine, escaped]) {
      const pem = normalizeApnsPrivateKey(raw);
      expect(pem.startsWith("-----BEGIN PRIVATE KEY-----\n")).toBe(true);
      expect(pem.includes("\n-----END PRIVATE KEY-----\n")).toBe(true);
      expect(pem.replace(/-----[^-]+-----|\s/g, "")).toBe(body);
    }
  });
});

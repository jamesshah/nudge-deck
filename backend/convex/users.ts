import { ConvexError, v } from "convex/values";
import { query } from "./_generated/server";
import { userFromSession, userMutation } from "./lib/auth";
import { notify } from "./lib/game";
import { MINUTES_PER_DAY } from "./lib/rules";
import { cancelCoupleSeasonJobs } from "./lib/seasonJobs";
import { nullable } from "./lib/validators";

/** Returns null for an unknown or expired session so the app can drop a stale token. */
export const me = query({
  args: { sessionToken: v.string() },
  returns: v.union(
    v.null(),
    v.object({
      _id: v.id("users"),
      name: v.string(),
      timeZone: v.string(),
      utcOffsetMinutes: v.number(),
      quietStartMinutes: v.optional(v.number()),
      quietEndMinutes: v.optional(v.number()),
      coupleId: v.optional(v.id("couples")),
      isDevAccount: v.boolean(),
    }),
  ),
  handler: async (ctx, { sessionToken }) => {
    const user = await userFromSession(ctx, sessionToken);
    if (!user) return null;
    return {
      _id: user._id,
      name: user.name,
      timeZone: user.timeZone,
      utcOffsetMinutes: user.utcOffsetMinutes,
      quietStartMinutes: user.quietStartMinutes,
      quietEndMinutes: user.quietEndMinutes,
      coupleId: user.coupleId,
      isDevAccount: user.isDevAccount ?? false,
    };
  },
});

export const updateProfile = userMutation({
  args: { name: nullable(v.string()), timeZone: v.string(), utcOffsetMinutes: v.number() },
  returns: v.null(),
  handler: async (ctx, args) => {
    const name = args.name?.trim();
    if (name !== undefined && (name.length === 0 || name.length > 40)) {
      throw new ConvexError("Names need to be between 1 and 40 characters.");
    }
    await ctx.db.patch("users", ctx.user._id, {
      timeZone: args.timeZone,
      utcOffsetMinutes: args.utcOffsetMinutes,
      ...(name ? { name } : {}),
    });
    return null;
  },
});

/** Pass null for both to turn quiet hours off. */
export const setQuietHours = userMutation({
  args: { startMinutes: v.union(v.number(), v.null()), endMinutes: v.union(v.number(), v.null()) },
  returns: v.null(),
  handler: async (ctx, { startMinutes, endMinutes }) => {
    if (startMinutes === null || endMinutes === null) {
      await ctx.db.patch("users", ctx.user._id, {
        quietStartMinutes: undefined,
        quietEndMinutes: undefined,
      });
      return null;
    }
    const valid = (m: number) => Number.isInteger(m) && m >= 0 && m < MINUTES_PER_DAY;
    if (!valid(startMinutes) || !valid(endMinutes)) {
      throw new ConvexError("Quiet hours must be times within the day.");
    }
    await ctx.db.patch("users", ctx.user._id, {
      quietStartMinutes: startMinutes,
      quietEndMinutes: endMinutes,
    });
    return null;
  },
});

/**
 * Permanently deletes the signed-in user, their sessions, and devices.
 * Waiting invites are canceled; active/ended couples are unpaired (soft-deleted)
 * so the partner can invite someone new.
 */
export const deleteAccount = userMutation({
  args: {},
  returns: v.null(),
  handler: async (ctx) => {
    const userId = ctx.user._id;
    const coupleId = ctx.user.coupleId;

    if (coupleId) {
      const couple = await ctx.db.get("couples", coupleId);
      if (couple && couple.deletedAt === undefined) {
        if (couple.status === "waiting") {
          const customCards = await ctx.db
            .query("cards")
            .withIndex("by_couple_and_creator", (q) => q.eq("coupleId", coupleId))
            .collect();
          for (const card of customCards) await ctx.db.delete("cards", card._id);
          const hands = await ctx.db
            .query("hands")
            .withIndex("by_couple_and_owner", (q) => q.eq("coupleId", coupleId))
            .collect();
          for (const hand of hands) await ctx.db.delete("hands", hand._id);
          await ctx.db.delete("couples", couple._id);
        } else {
          const now = Date.now();
          const wasActive = couple.status === "active";
          await cancelCoupleSeasonJobs(ctx, couple);
          await ctx.db.patch("couples", coupleId, {
            ...(wasActive ? { status: "ended" as const, endsAt: now } : {}),
            deletedAt: now,
          });
          const partnerId = couple.playerA === userId ? couple.playerB : couple.playerA;
          for (const memberId of [couple.playerA, couple.playerB]) {
            if (!memberId || memberId === userId) continue;
            await ctx.db.patch("users", memberId, { coupleId: undefined });
          }
          if (partnerId) {
            await notify(
              ctx,
              partnerId,
              "Account deleted",
              `${ctx.user.name} deleted their account. You can invite someone new anytime.`,
              { screen: "deck" },
            );
          }
        }
      }
    }

    const sessions = await ctx.db
      .query("sessions")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .collect();
    for (const session of sessions) await ctx.db.delete("sessions", session._id);

    const devices = await ctx.db
      .query("devices")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .collect();
    for (const device of devices) await ctx.db.delete("devices", device._id);

    await ctx.db.delete("users", userId);
    return null;
  },
});

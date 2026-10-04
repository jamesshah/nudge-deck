import { v } from "convex/values";
import { internal } from "./_generated/api";
import { internalAction } from "./_generated/server";
import { apnsConfigured } from "./lib/apnsConfig";

const notifyScreen = v.union(
  v.literal("inbox"),
  v.literal("deck"),
  v.literal("recap"),
  v.literal("timeline"),
);

/**
 * Sends a push to every registered device for a user. Without APNs
 * credentials this is a no-op: the app still gets realtime updates and
 * shows local notifications.
 */
export const sendToUser = internalAction({
  args: {
    userId: v.id("users"),
    title: v.string(),
    body: v.string(),
    badge: v.number(),
    screen: v.optional(notifyScreen),
    playId: v.optional(v.id("plays")),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    if (!apnsConfigured()) {
      console.log(`APNs not configured; skipping push "${args.title}"`);
      return null;
    }
    const devices = await ctx.runQuery(internal.devices.forUser, { userId: args.userId });
    if (devices.length === 0) return null;
    // APNs needs HTTP/2, which only the Node runtime provides.
    const invalid = await ctx.runAction(internal.apns.send, {
      devices,
      title: args.title,
      body: args.body,
      badge: args.badge,
      screen: args.screen,
      playId: args.playId,
    });
    if (invalid.length > 0) {
      await ctx.runMutation(internal.devices.removeTokens, { apnsTokens: invalid });
    }
    return null;
  },
});

import { ConvexError, v } from "convex/values";
import { createRemoteJWKSet, jwtVerify } from "jose";
import { internal } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import { action, internalMutation, mutation, type MutationCtx } from "./_generated/server";
import { makeSessionToken } from "./lib/rules";
import { nullable } from "./lib/validators";

const APPLE_ISSUER = "https://appleid.apple.com";
const appleKeys = createRemoteJWKSet(new URL(`${APPLE_ISSUER}/auth/keys`));

const deviceTime = {
  timeZone: v.string(),
  utcOffsetMinutes: v.number(),
};

function cleanName(name: string | null | undefined): string | undefined {
  const trimmed = name?.trim();
  if (!trimmed) return undefined;
  return trimmed.slice(0, 40);
}

async function startSession(ctx: MutationCtx, userId: Id<"users">): Promise<string> {
  const token = makeSessionToken();
  await ctx.db.insert("sessions", { userId, token });
  return token;
}

/**
 * Name-only sign-in so two Simulator accounts can pair without an Apple
 * Developer account. Off unless the deployment sets `ALLOW_DEV_SIGNIN=true`.
 */
export const signInDev = mutation({
  args: { name: v.string(), ...deviceTime },
  returns: v.string(),
  handler: async (ctx, args) => {
    if (process.env.ALLOW_DEV_SIGNIN !== "true") {
      throw new ConvexError("Dev sign-in is turned off for this deployment.");
    }
    const name = cleanName(args.name);
    if (!name) throw new ConvexError("Enter a name to sign in.");
    const userId = await ctx.db.insert("users", {
      name,
      isDevAccount: true,
      timeZone: args.timeZone,
      utcOffsetMinutes: args.utcOffsetMinutes,
    });
    return await startSession(ctx, userId);
  },
});

export const signInWithApple = action({
  args: { identityToken: v.string(), name: nullable(v.string()), ...deviceTime },
  returns: v.string(),
  handler: async (ctx, args): Promise<string> => {
    const audience = process.env.APPLE_BUNDLE_ID ?? "com.jamesshah.nudgedeck";
    let sub: string;
    try {
      const { payload } = await jwtVerify(args.identityToken, appleKeys, {
        issuer: APPLE_ISSUER,
        audience,
      });
      if (!payload.sub) throw new Error("missing sub");
      sub = payload.sub;
    } catch (error) {
      console.error("Apple identity token rejected", error);
      throw new ConvexError("Sign in with Apple failed. Please try again.");
    }
    return await ctx.runMutation(internal.auth.upsertAppleUser, {
      appleSub: sub,
      name: cleanName(args.name),
      timeZone: args.timeZone,
      utcOffsetMinutes: args.utcOffsetMinutes,
    });
  },
});

export const upsertAppleUser = internalMutation({
  args: { appleSub: v.string(), name: v.optional(v.string()), ...deviceTime },
  returns: v.string(),
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("users")
      .withIndex("by_appleSub", (q) => q.eq("appleSub", args.appleSub))
      .unique();
    let userId: Id<"users">;
    if (existing) {
      userId = existing._id;
      // Upgrade the placeholder if Apple/client finally sends a real name; don't
      // overwrite a name the user chose in Settings.
      const shouldSetName = !!args.name && existing.name === "Player";
      await ctx.db.patch("users", userId, {
        timeZone: args.timeZone,
        utcOffsetMinutes: args.utcOffsetMinutes,
        ...(shouldSetName ? { name: args.name } : {}),
      });
    } else {
      // Apple only shares the name on the very first sign-in; the client caches it
      // and prompts when missing so we rarely hit the Player fallback.
      userId = await ctx.db.insert("users", {
        name: args.name ?? "Player",
        appleSub: args.appleSub,
        timeZone: args.timeZone,
        utcOffsetMinutes: args.utcOffsetMinutes,
      });
    }
    return await startSession(ctx, userId);
  },
});

export const signOut = mutation({
  args: { sessionToken: v.string() },
  returns: v.null(),
  handler: async (ctx, { sessionToken }) => {
    const session = await ctx.db
      .query("sessions")
      .withIndex("by_token", (q) => q.eq("token", sessionToken))
      .unique();
    if (session) await ctx.db.delete("sessions", session._id);
    return null;
  },
});

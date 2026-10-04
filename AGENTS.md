# Nudge Deck — Agent Guide

NudgeDeck — Little things. More together. SwiftUI iOS client + Convex backend. **All game rules run in Convex mutations** so clients cannot cheat.

Vocabulary: **Nudges** (cards), **Deck** (hand), **Pass** (refuse), **Nudge back** (reciprocal play).

## Layout

| Path | Role |
| --- | --- |
| `backend/convex/` | Schema, auth, plays, couples, cards, push |
| `backend/convex/lib/game.ts` | Play / stack / counter / refuse / proof rules |
| `backend/convex/lib/rules.ts` | Pure helpers (quiet hours, dealing, invite codes) |
| `backend/convex/game.test.ts` | Rule tests (`convex-test` + vitest) |
| `ios/NudgeDeck/` | SwiftUI app (XcodeGen); Convex via ConvexMobile |

## Hard rules

- Put game logic in Convex (`lib/game.ts` / mutations), not in the iOS client.
- Use `npx convex dev` for development. `npx convex deploy` is production only.
- Never set `ALLOW_DEV_SIGNIN=true` on production.
- Do not commit secrets (`.env.local`, APNs `.p8`, deploy keys, `Local.xcconfig`).
- Prefer editing existing modules over adding parallel abstractions.
- Keep agent docs short; prefer README for long setup walkthroughs.

## Backend commands

```bash
cd backend
npm install
npm test
npm run lint
npx convex dev
npx convex run seed:run
```

## iOS commands

```bash
cd ios/NudgeDeck
xcodegen generate   # after editing project.yml; commit .xcodeproj + Support/Info.plist
open NudgeDeck.xcodeproj
# tests:
xcodebuild test -project NudgeDeck.xcodeproj -scheme NudgeDeck \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

`NudgeDeck.xcodeproj` and `Support/Info.plist` are **tracked** (Xcode Cloud needs them). After changing `project.yml`, regenerate and commit both. Preview-only stores (`GameStore(previewCouple:)`, `SessionStore(previewState:)`) must not create a Convex client. Sample data lives in `Preview Content/PreviewFixtures.swift` behind `#if DEBUG`.

## Auth & config notes

- Dev sign-in needs **both** app `ENABLE_DEV_SIGNIN` and backend `ALLOW_DEV_SIGNIN=true`.
- Override Convex URL locally via gitignored `ios/NudgeDeck/Config/Local.xcconfig` (see README for the `$()` xcconfig `//` trick).
- `Config/App.xcconfig` is the **staging / TestFlight** Convex URL; keep `ALLOW_DEV_SIGNIN` off on that deployment. App Store production URL goes in `Config/Production.xcconfig` later (see README).

## When changing rules

1. Update `lib/game.ts` / `lib/rules.ts`.
2. Extend `game.test.ts`.
3. Only then adjust iOS UI / models to match the API.

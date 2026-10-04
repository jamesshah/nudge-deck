# Nudge Deck

NudgeDeck — Little things. More together.

A playful couples game where you send each other little challenges, dares, questions, and things to do together. Pick a Deck → get a Nudge → send it → they respond → Nudge back.

- **iOS app**: native SwiftUI (iOS 17+), using [ConvexMobile](https://github.com/get-convex/convex-swift) for realtime queries and mutations.
- **Backend**: [Convex](https://convex.dev). All game rules run in Convex mutations, so neither client can cheat.

## Rules

- Joining a couple deals the 60-Nudge deck: each player gets a unique 30 Nudges, including 3 counters.
- Every Nudge is single use.
- You can't send another until your person responds to your last one (completes, sends proof, counters, or passes).
- Nudges stack: you can send one on top of one they sent you. Both stay in play.
- **Counter** Nudges block one that was sent to you.
- **Passing** a Nudge lets the sender steal a random one from your Deck and Nudge you back with it.
- **Proof**: the target attaches a photo, voice note, or note. The sender accepts it or sends it back for another try.
- **Quiet hours**: a Nudge sent during quiet hours is held and delivered when they end. Both players' local times are shown in the app.
- **Custom Nudges**: each player can write up to 5 of their own per season.

## Repo layout

```
backend/            Convex backend
  convex/
    schema.ts       users, sessions, couples, cards, hands, plays, devices
    lib/game.ts     game rules (play, stack, counter, refuse, proof)
    lib/rules.ts    pure helpers (quiet hours, dealing, invite codes)
    plays.ts        public play mutations + inbox/timeline queries
    couples.ts      create/join/cancel, season end, recap
    cards.ts        hand query, custom cards
    auth.ts         dev sign-in and Sign in with Apple
    push.ts         push dispatch (no-op until APNs is configured)
    apns.ts         APNs HTTP/2 sender ("use node")
    seedData.ts     the original 60-card Nudge Deck
    game.test.ts    rule tests (convex-test + vitest)
ios/NudgeDeck/       SwiftUI app
  project.yml       XcodeGen project spec
  Config/App.xcconfig   CONVEX_URL build setting
  NudgeDeck/         app sources
  NudgeDeckTests/    unit tests
```

## Backend

Requires Node 20+.

```bash
cd backend
npm install
npm test            # rule tests
npm run lint
npx convex dev      # local/dev deployment; watches and pushes functions
npx convex run seed:run   # load the deck (safe to re-run)
npx convex env set ALLOW_DEV_SIGNIN true   # allow the name-only test sign-in on this dev deployment
```

Use `npx convex dev` for development. `npx convex deploy` is for production only.

### Deploying to the shared deployment

The app points at `https://loyal-lapwing-231.convex.cloud` by default. With a deploy key for that deployment (Convex dashboard, then Settings, then Deploy keys):

```bash
cd backend
export CONVEX_DEPLOY_KEY=...        # production deploy key for loyal-lapwing-231
npx convex deploy
npx convex run seed:run
```

### Environment variables

Set these in the Convex dashboard (Settings, then Environment Variables) or with `npx convex env set NAME value`.

| Variable | Purpose |
| --- | --- |
| `APPLE_BUNDLE_ID` | Audience for Sign in with Apple tokens. Defaults to `com.jamesshah.nudgedeck`. |
| `ALLOW_DEV_SIGNIN` | Set to `true` to allow the name-only test sign-in (`auth:signInDev`). Any other value, or leaving it unset, rejects it. Never set it on production. |
| `APNS_KEY_ID` | Key ID of your APNs auth key (.p8). |
| `APNS_TEAM_ID` | Your Apple Developer team ID. |
| `APNS_PRIVATE_KEY` | Contents of the .p8 file. Literal `\n` sequences are accepted. |
| `APNS_TOPIC` | The app's bundle ID, e.g. `com.jamesshah.nudgedeck`. |

Without all four `APNS_*` variables, provider pushes are skipped. The app keeps its
local-notification fallback enabled, but that fallback is driven by the live Convex
subscription and therefore works only while the app process is running.

## iOS app (Mac setup)

Requires Xcode 15 or later with an iOS 17+ Simulator runtime, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
cd ios/NudgeDeck
xcodegen generate
open NudgeDeck.xcodeproj
```

Run the tests from the command line:

```bash
cd ios/NudgeDeck
xcodegen generate
xcodebuild test -project NudgeDeck.xcodeproj -scheme NudgeDeck \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Swift Package Manager fetches ConvexMobile on first build.

### Canvas previews

Every screen and its main subviews have `#Preview` blocks that run offline. `GameStore(previewCouple:...)` and `SessionStore(previewState:)` are preview-only initializers that never create a Convex client. The sample data lives in `NudgeDeck/Preview Content/PreviewFixtures.swift` (`PreviewData`), all behind `#if DEBUG`: a couple in San Francisco and London, a hand covering every card category, and plays in every state. `PreviewRenderingTests` renders the same scenarios in the Simulator during `xcodebuild test` and fails on any that come out blank. Each render is attached to the test result.

### Pointing at a different backend

`CONVEX_URL` lives in `ios/NudgeDeck/Config/App.xcconfig`. To override it without touching the repo, create `ios/NudgeDeck/Config/Local.xcconfig` (gitignored):

```
CONVEX_URL = http:/$()/127.0.0.1:3210
```

The `$()` keeps xcconfig from treating `//` as a comment. The Simulator can reach a local `npx convex dev` backend at `127.0.0.1`.

### Dev (name-only) sign-in

The **Quick sign-in for testing** panel needs both switches on:

- **App:** the `ENABLE_DEV_SIGNIN` build setting in `Config/App.xcconfig` reaches the app through Info.plist. It defaults to `YES` for Debug and `NO` otherwise. Set `ENABLE_DEV_SIGNIN = NO` in `Local.xcconfig` to hide the panel in Debug, which is what users of a signed build see. A `-EnableDevSignIn YES` or `-EnableDevSignIn NO` launch argument overrides the setting at runtime; the smoke UI test passes `YES`. Release builds compile the panel out under `#if DEBUG`, whatever the setting says.
- **Backend:** set `ALLOW_DEV_SIGNIN=true` on the deployment (`npx convex env set ALLOW_DEV_SIGNIN true`). To turn it off, run `npx convex env remove ALLOW_DEV_SIGNIN`.

With the panel hidden, Sign in with Apple is the only way in.

### Trying it with two players

1. Boot two Simulators (e.g. iPhone 16 and iPhone 16 Pro) and run the app on both.
2. On each, use **Quick sign-in for testing** with a different name.
3. On the first, pick a timeframe and tap **Create invite code**. On the second, enter the code and tap **Join**. Both hands are dealt.
4. Play a card from the Hand tab, then answer it from the other Simulator's Inbox.

### Two-player smoke test

The `NudgeDeckSmoke` scheme runs a UI test that drives one player in the Simulator and the partner through the Convex HTTP API. It covers pairing, playing, sending proof back for another try, accepting, completing with a note, refusing (with the steal), and countering. It needs a local backend (`npx convex dev`, seeded) and the `Local.xcconfig` override above:

```bash
cd ios/NudgeDeck
xcodegen generate
xcodebuild test -project NudgeDeck.xcodeproj -scheme NudgeDeckSmoke \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
```

Screenshots of each step are attached to the test result.

### Sign in with Apple and push notifications

Both need a paid Apple Developer account and a signed build.

1. In the Apple Developer portal, enable **Sign in with Apple** and **Push Notifications** for the App ID `com.jamesshah.nudgedeck` (or your own bundle ID; update `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`, `APPLE_BUNDLE_ID`, and `APNS_TOPIC` in Convex to match).
2. Create `ios/NudgeDeck/Config/Local.xcconfig`:
   ```
   DEVELOPMENT_TEAM = ABCDE12345
   ```
   `CODE_SIGN_ENTITLEMENTS` is already configured in `project.yml`; Debug builds use
   the development APNs environment and Release builds use production.
3. In the Apple Developer portal, create an APNs auth key (Keys, then +, then
   **Apple Push Notifications service (APNs)**) and download its `.p8` file. Apple
   only lets you download this file once.
4. Set the provider credentials on the same Convex deployment the app uses:
   ```bash
   cd backend
   npx convex env set APNS_TEAM_ID ABCDE12345
   npx convex env set APNS_KEY_ID 1A2BC3D4E5
   # Use --from-file. Do not pass the PEM as a CLI argument: lines starting
   # with ----- are parsed as flags ("unknown option" / looks like a denial).
   # Dashboard pastes also often collapse newlines and break OpenSSL.
   npx convex env set APNS_PRIVATE_KEY --from-file /absolute/path/to/AuthKey_1A2BC3D4E5.p8
   npx convex env set APNS_TOPIC com.jamesshah.nudgedeck
   ```
   James must provide: the paid Apple Developer **Team ID**, the downloaded APNs
   **`.p8` private key**, its **Key ID**, and the app's exact **bundle ID/topic**.
   The `.p8` must include the `-----BEGIN PRIVATE KEY-----` /
   `-----END PRIVATE KEY-----` lines.
5. Run `xcodegen generate` and build to a real device. Grant notification permission
   when prompted. The app registers with APNs, stores the device token in Convex, and
   the backend sends through the sandbox or production APNs host as appropriate.

### Test a background notification in Simulator

Simulator push injection does not need an Apple account or APNs provider key. Build
and launch the app once, grant notification permission, then put it in the background
or terminate it. From `ios/NudgeDeck`, run:

```bash
xcrun simctl push booted com.jamesshah.nudgedeck Support/sample-background.apns
```

The checked-in sample includes an alert, sound, badge, bundle target, and example
`playId`. This proves the iOS entitlement, authorization, and background presentation
path. It does not prove the Convex-to-APNs provider connection; that requires the four
credentials above.

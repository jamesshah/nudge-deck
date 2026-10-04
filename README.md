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
  project.yml       XcodeGen project spec (edit this, then regenerate)
  NudgeDeck.xcodeproj/  generated project (committed for Xcode Cloud)
  Support/Info.plist    generated (committed)
  Config/App.xcconfig   staging / TestFlight CONVEX_URL + team
  Config/Production.xcconfig  future App Store Convex URL (not wired yet)
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

### Deploying to the shared (staging / TestFlight) deployment

`Config/App.xcconfig` points at `https://loyal-lapwing-231.convex.cloud`. That URL is the **staging** backend used by Debug defaults and by **TestFlight** (Release) builds. Do not set `ALLOW_DEV_SIGNIN=true` on it. With a deploy key for that deployment (Convex dashboard, then Settings, then Deploy keys):

```bash
cd backend
export CONVEX_DEPLOY_KEY=...        # deploy key for loyal-lapwing-231
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

Requires Xcode 15 or later with an iOS 17+ Simulator runtime. The generated `NudgeDeck.xcodeproj` and `Support/Info.plist` are committed so Xcode Cloud can archive without running XcodeGen. After editing `project.yml`, regenerate and **commit** both:

```bash
brew install xcodegen   # once
cd ios/NudgeDeck
xcodegen generate
git add NudgeDeck.xcodeproj Support/Info.plist
open NudgeDeck.xcodeproj
```

A fresh clone can open the committed project without XcodeGen. Run tests:

```bash
cd ios/NudgeDeck
xcodebuild test -project NudgeDeck.xcodeproj -scheme NudgeDeck \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Swift Package Manager fetches ConvexMobile on first build.

### Staging vs production Convex

| Build | Xcode configuration | xcconfig | Backend |
| --- | --- | --- | --- |
| Local Debug | Debug | `App.xcconfig` (+ optional `Local.xcconfig`) | staging or local |
| TestFlight | **Release** | **`App.xcconfig`** | staging (`loyal-lapwing-231`) |
| App Store (later) | **AppStore** (add when ready) | **`Production.xcconfig`** | production deployment |

TestFlight and App Store both archive as Release-style builds today, so Debug vs Release alone cannot split backends. Keep TestFlight on Release + `App.xcconfig`. When you have a production Convex URL, fill in `Config/Production.xcconfig`, add an `AppStore` configuration in `project.yml`, regenerate/commit the project, and use a **separate** Xcode Cloud workflow that archives `AppStore` (manual / `appstore-*` tags) so you do not burn free hours by accident.

### Canvas previews

Every screen and its main subviews have `#Preview` blocks that run offline. `GameStore(previewCouple:...)` and `SessionStore(previewState:)` are preview-only initializers that never create a Convex client. The sample data lives in `NudgeDeck/Preview Content/PreviewFixtures.swift` (`PreviewData`), all behind `#if DEBUG`: a couple in San Francisco and London, a hand covering every card category, and plays in every state. `PreviewRenderingTests` renders the same scenarios in the Simulator during `xcodebuild test` and fails on any that come out blank. Each render is attached to the test result.

### Pointing at a different backend

Staging `CONVEX_URL` and `DEVELOPMENT_TEAM` live in `ios/NudgeDeck/Config/App.xcconfig`. To override the URL without touching the repo, create `ios/NudgeDeck/Config/Local.xcconfig` (gitignored):

```
CONVEX_URL = http:/$()/127.0.0.1:3210
```

The `$()` keeps xcconfig from treating `//` as a comment. The Simulator can reach a local `npx convex dev` backend at `127.0.0.1`. On a physical device, point `CONVEX_URL` at your Mac's LAN hostname (e.g. `http:/$()/mini.local:3210`); the app rewrites storage upload/download URLs so they use that host instead of the backend's `127.0.0.1`.

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
2. `DEVELOPMENT_TEAM` is set in `Config/App.xcconfig`. `CODE_SIGN_ENTITLEMENTS` is in `project.yml`; Debug uses the development APNs environment and Release/TestFlight use production. One APNs Auth Key (`.p8`) covers sandbox and production; the app reports which host to use.
3. In the Apple Developer portal, create an APNs auth key (Keys, then +, then
   **Apple Push Notifications service (APNs)**) and download its `.p8` file. Apple
   only lets you download this file once.
4. Set the provider credentials on the same Convex deployment the app uses:
   ```bash
   cd backend
   npx convex env set APNS_TEAM_ID YOUR_TEAM_ID
   npx convex env set APNS_KEY_ID 1A2BC3D4E5
   # Use --from-file. Do not pass the PEM as a CLI argument: lines starting
   # with ----- are parsed as flags ("unknown option" / looks like a denial).
   # Dashboard pastes also often collapse newlines and break OpenSSL.
   npx convex env set APNS_PRIVATE_KEY --from-file /absolute/path/to/AuthKey_1A2BC3D4E5.p8
   npx convex env set APNS_TOPIC com.jamesshah.nudgedeck
   ```
   The `.p8` must include the `-----BEGIN PRIVATE KEY-----` /
   `-----END PRIVATE KEY-----` lines.
5. Open the committed `NudgeDeck.xcodeproj` (or regenerate after `project.yml` changes) and build to a real device. Grant notification permission
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
`screen` / `playId` deep-link fields. Tapping it should open the Inbox tab. This proves
the iOS entitlement, authorization, background presentation, and tap-routing path. It
does not prove the Convex-to-APNs provider connection; that requires the four
credentials above.

## Xcode Cloud → TestFlight (25 free hours)

One workflow archives **Release** (`App.xcconfig` staging Convex) once and posts to **both** TestFlight Internal and External. That does not double compute hours. Stay under 25 hours/month by avoiding PR/branch build matrices and skipping cloud tests (`NudgeDeckSmoke` needs local Convex).

### Hour policy

- **Actions:** Archive only (no Test action)
- **Start conditions:** Manual + Git tags matching `tf-*` (branch changes off)
- **Distribution:** Internal + External post-actions on the same archive
- Roughly 2–4 tagged builds per week stays well under 25 hours

### Cut a build

```bash
git tag tf-0.1.0.1
git push origin tf-0.1.0.1
```

Or start the workflow manually from Xcode / App Store Connect.

### 1. App Store Connect TestFlight groups

In [App Store Connect](https://appstoreconnect.apple.com) → **Nudge Deck** → **TestFlight**:

1. **Internal Testing** — create a group (e.g. “Team”). Add App Store Connect users on the team. Internal builds are available after processing (no Beta App Review).
2. **External Testing** — create a group (e.g. “Beta”). Add email testers or a public link later. Fill **What to Test**, contact info, and export compliance / encryption answers (HTTPS-only apps typically use the standard exemption answers).
3. The **first** build sent to External goes through **Beta App Review**. Later builds to the same group often skip a full review unless metadata changes significantly.

External testers hit the **staging** Convex backend while this workflow uses `App.xcconfig`.

### 2. Create the Xcode Cloud workflow

Prerequisites: git remote is `jamesshah/nudge-deck`, `NudgeDeck.xcodeproj` is on the branch you build, paid Apple Developer account.

1. Open `ios/NudgeDeck/NudgeDeck.xcodeproj` in Xcode.
2. Confirm Signing & Capabilities: team selected, Automatic signing, Sign in with Apple + Push present.
3. **Product → Xcode Cloud → Create Workflow** (or App Store Connect → app → Xcode Cloud).
4. Grant Xcode Cloud access to **`jamesshah/nudge-deck`** if prompted.
5. Workflow settings:
   - **Name:** `TestFlight`
   - **Project / scheme:** `NudgeDeck.xcodeproj` / **`NudgeDeck`**
   - **Environment:** latest stable Xcode / macOS; pin versions once a build succeeds
   - **Start conditions:** Manual **on**; Branch changes **off**; Tag changes **on** with `tf-*`
   - **Actions:** Archive → iOS → **Release**; Deployment Preparation = **TestFlight External Testing** (not Internal-only)
   - **Post-Actions:**
     - TestFlight Internal Testing → your Internal group
     - TestFlight External Testing → your External group
6. Start a manual run. Confirm archive upload, then Internal install after processing; External after Beta App Review (first time).
7. Verify Sign in with Apple and push against staging Convex (Release uses production APNs host; one Auth Key covers both hosts).

Do **not** put APNs `.p8` keys in Xcode Cloud env — push credentials stay on Convex.

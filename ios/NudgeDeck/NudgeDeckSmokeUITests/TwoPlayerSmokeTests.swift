import XCTest

/// Drives player A through the app while player B acts through the Convex HTTP API.
/// Needs a local `npx convex dev` backend with the deck seeded, and the app built
/// against it (`CONVEX_URL = http:/$()/127.0.0.1:3210` in Local.xcconfig).
final class TwoPlayerSmokeTests: XCTestCase {
    private let app = XCUIApplication()
    private let partner = PartnerClient(baseURL: URL(string: "http://127.0.0.1:3210")!)
    private let suffix = String(Int(Date().timeIntervalSince1970) % 100_000)
    private var partnerName: String { "Blair\(suffix)" }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments += [
            "-EnableDevSignIn", "YES",
            // Simulator often can't resolve LAN .local hosts from Local.xcconfig.
            "-ConvexURL", "http://127.0.0.1:3210",
            "-handDisplayMode", "cards",
            "-handCategoryFilter", "All",
        ]
        app.launch()
    }

    func testTwoPlayerFlow() throws {
        let nameField = app.textFields["Your name"]
        signOutIfNeeded(nameField)
        XCTAssertTrue(nameField.waitForExistence(timeout: 20), "Sign-in screen didn't appear")
        nameField.tap()
        nameField.typeText("Alex\(suffix)")
        app.buttons["Start"].tap()

        let create = app.buttons["Create invite"]
        XCTAssertTrue(create.waitForExistence(timeout: 15), "Pairing screen didn't appear")
        create.tap()

        let codeLabel = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^[A-Z0-9]{6}$")).firstMatch
        XCTAssertTrue(codeLabel.waitForExistence(timeout: 15), "Invite code didn't appear")
        let code = codeLabel.label
        snapshot("00-invite-code")

        try partner.signIn(name: partnerName)
        try partner.mutation("couples:join", ["inviteCode": code])

        let playButton = app.buttons["Nudge \(partnerName)"]
        XCTAssertTrue(playButton.waitForExistence(timeout: 20), "Deck wasn't dealt after partner joined")
        dismissNotificationPrompt()
        snapshot("01-hand")

        // A sends a Nudge; B completes it with a text note; A sends it back once, then accepts.
        playButton.tap()
        tapWhenReady(app.navigationBars.buttons["Send"])
        let aPlay = try partner.waitForIncoming()
        try partner.mutation("plays:completeWithProof", [
            "playId": aPlay, "proofType": "text", "proofText": "Called you from the train!", "proofStorageId": NSNull(),
        ])

        app.tabBars.buttons["Inbox"].tap()
        let tryAgain = app.buttons["Try again"]
        XCTAssertTrue(tryAgain.waitForExistence(timeout: 15), "Proof to review didn't show up")
        tryAgain.tap()
        let noteField = app.alerts.textFields.firstMatch
        XCTAssertTrue(noteField.waitForExistence(timeout: 5), "Try-again alert has no text field")
        noteField.typeText("Need a selfie too")
        app.alerts.buttons["Send back"].tap()
        XCTAssertTrue(try partner.waitForIncomingNote(playId: aPlay) == "Need a selfie too")

        try partner.mutation("plays:completeWithProof", [
            "playId": aPlay, "proofType": "text", "proofText": "Selfie sent on WhatsApp", "proofStorageId": NSNull(),
        ])
        let accept = app.buttons["Accept"]
        XCTAssertTrue(accept.waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 5) // let the "sent proof" banner clear before the screenshot
        snapshot("02-inbox-review")
        accept.tap()
        XCTAssertTrue(app.staticTexts["No Nudges yet."].waitForExistence(timeout: 10))

        // B Nudges A; A completes it with a note in the proof sheet; B accepts.
        let bFirst = try partner.playFirstActionCard()
        let complete = app.buttons["Complete"]
        XCTAssertTrue(complete.waitForExistence(timeout: 15), "Partner's Nudge didn't arrive")
        snapshot("03-inbox-incoming")
        complete.tap()
        app.segmentedControls.buttons["Note"].tap()
        let proofField = app.textFields["Tell them how it went"].exists
            ? app.textFields["Tell them how it went"] : app.textViews.firstMatch
        proofField.tap()
        proofField.typeText("Done! Sent you a voice memo on the walk home.")
        tapWhenReady(app.navigationBars.buttons["Send"])
        try partner.waitForState(playId: bFirst, state: "proofSubmitted")
        try partner.mutation("plays:acceptProof", ["playId": bFirst])
        try partner.waitForState(playId: bFirst, state: "completed")

        // B plays again; A passes, so B steals one of A's Nudges.
        let handBefore = try partner.handCount()
        let bSecond = try partner.playFirstActionCard()
        let refuse = app.buttons["Pass"]
        XCTAssertTrue(refuse.waitForExistence(timeout: 15))
        refuse.tap()
        let confirmRefuse = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pass \"")).firstMatch
        XCTAssertTrue(confirmRefuse.waitForExistence(timeout: 5))
        snapshot("04-refuse-confirm")
        confirmRefuse.tap()
        try partner.waitForState(playId: bSecond, state: "refused")
        XCTAssertEqual(try partner.handCount(), handBefore, "Partner should have played one Nudge and stolen one")
        XCTAssertNotNil(try partner.stolenTitle(playId: bSecond), "Pass didn't steal a Nudge")

        // B plays again; A blocks it with a counter.
        let bThird = try partner.playFirstActionCard()
        let counter = app.buttons["Counter"]
        XCTAssertTrue(counter.waitForExistence(timeout: 15))
        counter.tap()
        let counterCard = app.collectionViews.buttons.firstMatch
        XCTAssertTrue(counterCard.waitForExistence(timeout: 5), "No counters to pick")
        counterCard.tap()
        try partner.waitForState(playId: bThird, state: "countered")

        app.tabBars.buttons["Timeline"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "steal")).firstMatch.waitForExistence(timeout: 5)
            || app.cells.count >= 5)
        snapshot("05-timeline")
    }

    /// The session token lives in the Keychain, which survives reinstalls, so an earlier run may still be signed in.
    private func signOutIfNeeded(_ nameField: XCUIElement) {
        if nameField.waitForExistence(timeout: 8) { return }
        let settingsTab = app.tabBars.buttons["Settings"]
        if settingsTab.exists {
            settingsTab.tap()
            let signOut = app.buttons["openSignOut"]
            for _ in 0..<4 where !signOut.waitForExistence(timeout: 1) || !signOut.isHittable {
                app.swipeUp()
            }
            if signOut.exists {
                signOut.tap()
                let confirm = app.buttons["confirmSignOut"]
                if confirm.waitForExistence(timeout: 3) { confirm.tap() }
            } else if app.buttons["Sign out"].exists {
                app.buttons["Sign out"].firstMatch.tap()
            }
        } else if app.buttons["Sign out"].exists {
            app.buttons["Sign out"].firstMatch.tap()
        }
    }

    private func tapWhenReady(_ element: XCUIElement, timeout: TimeInterval = 10) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout))
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: element)
        wait(for: [enabled], timeout: timeout)
        element.tap()
    }

    /// The app asks for notification permission at sign-in, but the system prompt can show up much later.
    private func dismissNotificationPrompt(timeout: TimeInterval = 3) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: timeout) { allow.tap() }
    }

    private func snapshot(_ name: String) {
        dismissNotificationPrompt(timeout: 1)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Settings account sheets against a local Convex deployment + Simulator.
final class AccountSettingsUITests: XCTestCase {
    private let app = XCUIApplication()
    private let partner = PartnerClient(baseURL: URL(string: "http://127.0.0.1:3210")!)
    private let suffix = String(Int(Date().timeIntervalSince1970) % 100_000)

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments += [
            "-EnableDevSignIn", "YES",
            "-ConvexURL", "http://127.0.0.1:3210",
        ]
        app.launch()
    }

    func testSignOutAndDeleteAccountSheets() throws {
        let nameField = app.textFields["Your name"]
        signOutIfNeeded(nameField)
        XCTAssertTrue(nameField.waitForExistence(timeout: 20))

        // Sign in + pair so Settings is available.
        let alex = "AlexAcct\(suffix)"
        try signInDev(as: alex)
        let create = app.buttons["Create invite"]
        XCTAssertTrue(create.waitForExistence(timeout: 15), "Pairing screen didn't appear after sign-in. \(app.debugDescription)")
        create.tap()
        let codeLabel = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^[A-Z0-9]{6}$")).firstMatch
        XCTAssertTrue(codeLabel.waitForExistence(timeout: 15))
        try partner.signIn(name: "BlairAcct\(suffix)")
        try partner.mutation("couples:join", ["inviteCode": codeLabel.label])
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 20))
        dismissNotificationPrompt()

        // Sign out: open sheet, cancel, then confirm.
        openSettingsAccountSection()
        app.buttons["openSignOut"].tap()
        XCTAssertTrue(app.staticTexts["Sign out?"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        app.buttons["openSignOut"].tap()
        XCTAssertTrue(app.staticTexts["Sign out?"].waitForExistence(timeout: 5))
        app.buttons["confirmSignOut"].tap()
        XCTAssertTrue(nameField.waitForExistence(timeout: 15), "Sign out should return to sign-in")

        // Sign in again, pair, delete account: cancel then confirm.
        try signInDev(as: alex)
        XCTAssertTrue(create.waitForExistence(timeout: 15), "Pairing screen didn't appear after re-sign-in. \(app.debugDescription)")
        create.tap()
        XCTAssertTrue(codeLabel.waitForExistence(timeout: 15))
        try partner.signIn(name: "BlairAcct2\(suffix)")
        try partner.mutation("couples:join", ["inviteCode": codeLabel.label])
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 20))
        dismissNotificationPrompt()

        openSettingsAccountSection()
        app.buttons["openDeleteAccount"].tap()
        XCTAssertTrue(app.staticTexts["Delete account?"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        app.buttons["openDeleteAccount"].tap()
        XCTAssertTrue(app.staticTexts["Delete account?"].waitForExistence(timeout: 5))
        app.buttons["confirmDeleteAccount"].tap()
        XCTAssertTrue(nameField.waitForExistence(timeout: 15), "Delete account should return to sign-in")

        // Partner should be unpaired after delete.
        let couple = try partner.query("couples:current")
        XCTAssertTrue(couple is NSNull, "Partner should be unpaired after account delete")
    }

    private func openSettingsAccountSection() {
        app.tabBars.buttons["Settings"].tap()
        let signOut = app.buttons["openSignOut"]
        for _ in 0..<6 where !signOut.isHittable { app.swipeUp() }
        XCTAssertTrue(signOut.waitForExistence(timeout: 5))
    }

    /// Prefer keyboard Go — the on-screen Start button is often covered by the keyboard.
    private func signInDev(as name: String) throws {
        let nameField = app.textFields["Your name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.tap()
        nameField.typeText(name)
        if app.keyboards.buttons["Go"].waitForExistence(timeout: 2) {
            app.keyboards.buttons["go"].tap()
        } else if app.keyboards.buttons["go"].waitForExistence(timeout: 1) {
            app.keyboards.buttons["go"].tap()
        } else {
            app.buttons["Start"].tap()
        }
        dismissNotificationPrompt()
        if app.alerts.firstMatch.waitForExistence(timeout: 1) {
            let message = app.alerts.firstMatch.label
            app.alerts.buttons.firstMatch.tap()
            XCTFail("Sign-in showed an alert: \(message)")
        }
    }

    private func signOutIfNeeded(_ nameField: XCUIElement) {
        if nameField.waitForExistence(timeout: 8) { return }
        let settingsTab = app.tabBars.buttons["Settings"]
        if settingsTab.exists {
            settingsTab.tap()
            let signOut = app.buttons["openSignOut"]
            for _ in 0..<4 where !signOut.waitForExistence(timeout: 1) || !signOut.isHittable {
                app.swipeUp()
            }
            if signOut.exists {
                signOut.tap()
                let confirm = app.buttons["confirmSignOut"]
                if confirm.waitForExistence(timeout: 3) { confirm.tap() }
            } else if app.buttons["Sign out"].exists {
                // Pairing screen still uses a plain Sign out button.
                app.buttons["Sign out"].firstMatch.tap()
            }
        } else if app.buttons["Sign out"].exists {
            app.buttons["Sign out"].firstMatch.tap()
        }
    }
    private func dismissNotificationPrompt(timeout: TimeInterval = 3) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: timeout) { allow.tap() }
    }
}

/// The second player, driven through Convex's HTTP API.
private final class PartnerClient {
    let baseURL: URL
    private var token = ""

    init(baseURL: URL) { self.baseURL = baseURL }

    func signIn(name: String) throws {
        token = try call("mutation", "auth:signInDev", ["name": name, "timeZone": "Europe/London", "utcOffsetMinutes": 60],
                         authed: false) as! String
    }

    @discardableResult
    func mutation(_ path: String, _ args: [String: Any] = [:]) throws -> Any {
        try call("mutation", path, args)
    }

    func query(_ path: String) throws -> Any { try call("query", path, [:]) }

    func playFirstActionCard() throws -> String {
        let hand = try query("cards:myHand") as! [String: Any]
        let cards = hand["cards"] as! [[String: Any]]
        let card = try XCTUnwrap(cards.first { $0["kind"] as? String == "action" }, "Partner has no action cards")
        try mutation("plays:playCard", ["handId": card["handId"]!, "stackedOnPlayId": NSNull()])
        let inbox = try query("plays:inbox") as! [String: Any]
        let waiting = inbox["waitingOnPartner"] as! [[String: Any]]
        return try XCTUnwrap(waiting.first?["_id"] as? String)
    }

    func handCount() throws -> Int {
        ((try query("cards:myHand") as! [String: Any])["cards"] as! [Any]).count
    }

    func waitForIncoming() throws -> String {
        try poll { (try self.incoming().first?["_id"]) as? String }
    }

    func waitForIncomingNote(playId: String) throws -> String? {
        try poll { try self.incoming().first { $0["_id"] as? String == playId }?["proofRejectedNote"] as? String }
    }

    func waitForState(playId: String, state: String) throws {
        _ = try poll { try self.timelinePlay(playId)?["state"] as? String == state ? true : nil }
    }

    func stolenTitle(playId: String) throws -> String? {
        try timelinePlay(playId)?["stolenCardTitle"] as? String
    }

    private func incoming() throws -> [[String: Any]] {
        (try query("plays:inbox") as! [String: Any])["incoming"] as! [[String: Any]]
    }

    private func timelinePlay(_ id: String) throws -> [String: Any]? {
        (try query("plays:timeline") as! [[String: Any]]).first { $0["_id"] as? String == id }
    }

    private func poll<T>(timeout: TimeInterval = 15, _ body: () throws -> T?) throws -> T {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let value = try body() { return value }
            Thread.sleep(forTimeInterval: 0.5)
        }
        throw NSError(domain: "PartnerClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting on the backend"])
    }

    private func call(_ kind: String, _ path: String, _ args: [String: Any], authed: Bool = true) throws -> Any {
        var args = args
        if authed { args["sessionToken"] = token }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/\(kind)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["path": path, "args": args, "format": "json"])

        var result: Result<Data, Error> = .failure(NSError(domain: "PartnerClient", code: 2))
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, _, error in
            result = data.map { .success($0) } ?? .failure(error ?? NSError(domain: "PartnerClient", code: 3))
            done.signal()
        }.resume()
        done.wait()

        let json = try JSONSerialization.jsonObject(with: result.get()) as! [String: Any]
        guard json["status"] as? String == "success" else {
            throw NSError(domain: "PartnerClient", code: 4, userInfo: [NSLocalizedDescriptionKey: "\(path): \(json["errorMessage"] ?? json)"])
        }
        return json["value"] ?? NSNull()
    }
}

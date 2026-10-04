import AuthenticationServices
import XCTest
@testable import NudgeDeck

final class GameFormattingTests: XCTestCase {
    private let posix = Locale(identifier: "en_US_POSIX")

    /// Newer ICU versions put a narrow no-break space before AM/PM.
    private func plain(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    func testQuietHoursWrapPastMidnight() {
        let quiet = QuietHours(startMinutes: 22 * 60, endMinutes: 7 * 60)
        XCTAssertTrue(quiet.contains(minuteOfDay: 23 * 60))
        XCTAssertTrue(quiet.contains(minuteOfDay: 3 * 60))
        XCTAssertFalse(quiet.contains(minuteOfDay: 7 * 60))
        XCTAssertFalse(quiet.contains(minuteOfDay: 12 * 60))
    }

    func testQuietHoursSameDayRangeAndEmptyRange() {
        XCTAssertTrue(QuietHours(startMinutes: 60, endMinutes: 120).contains(minuteOfDay: 90))
        XCTAssertFalse(QuietHours(startMinutes: 60, endMinutes: 60).contains(minuteOfDay: 60))
    }

    func testQuietHoursUsePlayersOffset() {
        // 18:00 UTC is 23:30 in India (UTC+5:30).
        let date = ISO8601DateFormatter().date(from: "2026-03-01T18:00:00Z")!
        let quiet = QuietHours(startMinutes: 23 * 60, endMinutes: 8 * 60)
        XCTAssertTrue(quiet.contains(date: date, utcOffsetMinutes: 330))
        XCTAssertFalse(quiet.contains(date: date, utcOffsetMinutes: 0))
        XCTAssertEqual(GameFormatting.minuteOfDay(date: date, utcOffsetMinutes: -300), 13 * 60)
    }

    func testClockTimeInPartnersZone() {
        let date = ISO8601DateFormatter().date(from: "2026-03-01T18:00:00Z")!
        let tokyo = GameFormatting.timeZone(identifier: "Asia/Tokyo", utcOffsetMinutes: 540)
        XCTAssertEqual(plain(GameFormatting.clockTime(date, timeZone: tokyo, locale: posix)), "3:00 AM")
    }

    func testUnknownTimeZoneFallsBackToOffset() {
        let zone = GameFormatting.timeZone(identifier: "Not/AZone", utcOffsetMinutes: -300)
        XCTAssertEqual(zone.secondsFromGMT(), -300 * 60)
    }

    func testTimeOfDay() {
        XCTAssertEqual(plain(GameFormatting.timeOfDay(minutes: 22 * 60, locale: posix)), "10:00 PM")
        XCTAssertEqual(plain(GameFormatting.timeOfDay(minutes: 7 * 60 + 5, locale: posix)), "7:05 AM")
    }

    func testMinutesRoundTrip() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let date = GameFormatting.date(fromMinutes: 1305, calendar: calendar)
        XCTAssertEqual(GameFormatting.minutes(from: date, calendar: calendar), 1305)
    }

    func testSeasonProgressAndDaysLeft() {
        let start = 1_000_000.0
        let end = start + 10 * 86_400_000
        let midway = Date(timeIntervalSince1970: (start + 5 * 86_400_000) / 1000)
        XCTAssertEqual(GameFormatting.seasonProgress(startedAt: start, endsAt: end, now: midway), 0.5, accuracy: 0.0001)
        XCTAssertEqual(GameFormatting.daysLeft(endsAt: end, now: midway), 5)
        XCTAssertEqual(GameFormatting.seasonProgress(startedAt: nil, endsAt: end, now: midway), 0)
        XCTAssertEqual(GameFormatting.daysLeft(endsAt: start, now: midway), 0)
    }

    func testConvexErrorMessageDecoding() {
        XCTAssertEqual(
            GameFormatting.convexErrorMessage(fromData: "\"You've already used that card.\""),
            "You've already used that card."
        )
        XCTAssertEqual(GameFormatting.convexErrorMessage(fromData: "{\"code\":1}"), "{\"code\":1}")
    }

    func testInviteCodeNormalization() {
        XCTAssertEqual(GameFormatting.normalizedInviteCode(" ab-c 23x "), "ABC23X")
    }

    func testConvexURLResolution() {
        XCTAssertEqual(AppConfig.resolveConvexURL("https://loyal-lapwing-231.convex.cloud"), "https://loyal-lapwing-231.convex.cloud")
        XCTAssertEqual(AppConfig.resolveConvexURL("http://127.0.0.1:3210"), "http://127.0.0.1:3210")
        XCTAssertEqual(AppConfig.resolveConvexURL("$(CONVEX_URL)"), AppConfig.fallbackConvexURL)
        XCTAssertEqual(AppConfig.resolveConvexURL("https:"), AppConfig.fallbackConvexURL)
        XCTAssertEqual(AppConfig.resolveConvexURL(nil), AppConfig.fallbackConvexURL)
    }

    func testProofFileSizeLimit() {
        XCTAssertEqual(GameFormatting.maxProofBytes, 3 * 1024 * 1024)
        XCTAssertTrue(GameFormatting.isProofFileWithinLimit(Data(count: GameFormatting.maxProofBytes)))
        XCTAssertFalse(GameFormatting.isProofFileWithinLimit(Data(count: GameFormatting.maxProofBytes + 1)))
        XCTAssertTrue(GameFormatting.proofFileTooLargeMessage(for: .photo).contains("3 MB"))
        XCTAssertTrue(GameFormatting.proofFileTooLargeMessage(for: .audio).contains("3 MB"))
    }

    func testAlignStorageURLRewritesLocalLoopbackToLANHost() {
        let upload = "http://127.0.0.1:3210/api/storage/upload?token=abc"
        XCTAssertEqual(
            AppConfig.alignStorageURL(upload, to: "http://mini.local:3210"),
            "http://mini.local:3210/api/storage/upload?token=abc"
        )
        let cloud = "https://loyal-lapwing-231.convex.cloud/api/storage/xyz"
        XCTAssertEqual(
            AppConfig.alignStorageURL(cloud, to: "https://loyal-lapwing-231.convex.cloud"),
            cloud
        )
    }

    func testBundledConvexURLIsConfigured() {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CONVEX_URL") as? String
        XCTAssertEqual(raw.map { AppConfig.resolveConvexURL($0) }, raw, "CONVEX_URL build setting should expand to a full URL")
    }

    func testDevSignInFlagResolution() {
        XCTAssertTrue(AppConfig.resolveDevSignIn(buildSetting: "YES", launchOverride: nil))
        XCTAssertFalse(AppConfig.resolveDevSignIn(buildSetting: "NO", launchOverride: nil))
        XCTAssertFalse(AppConfig.resolveDevSignIn(buildSetting: "$(ENABLE_DEV_SIGNIN)", launchOverride: nil))
        XCTAssertFalse(AppConfig.resolveDevSignIn(buildSetting: nil, launchOverride: nil))
        XCTAssertTrue(AppConfig.resolveDevSignIn(buildSetting: "NO", launchOverride: "YES"))
        XCTAssertFalse(AppConfig.resolveDevSignIn(buildSetting: "YES", launchOverride: "NO"))
    }

    func testAppleSignInErrorsOnlyExplainSetupWhenItsTheLikelyCause() {
        XCTAssertNil(SessionStore.appleSignInErrorMessage(for: ASAuthorizationError(.canceled)))
        XCTAssertTrue(SessionStore.appleSignInErrorMessage(for: ASAuthorizationError(.unknown))?.contains("capability") == true)
        XCTAssertTrue(SessionStore.appleSignInErrorMessage(for: ASAuthorizationError(.failed))?.contains("capability") == true)
        XCTAssertTrue(SessionStore.appleSignInErrorMessage(for: ASAuthorizationError(.invalidResponse))?.hasPrefix("Sign in with Apple failed") == true)
    }

    func testAppleDisplayNameUsesGivenAndFamilyNames() {
        var components = PersonNameComponents()
        components.givenName = "Jamie"
        components.familyName = "Lee"
        XCTAssertEqual(AppleDisplayName.from(components), "Jamie Lee")
        XCTAssertNil(AppleDisplayName.from(PersonNameComponents()))
        XCTAssertNil(AppleDisplayName.from(nil))
    }

    func testAppleDisplayNameCacheRoundTripsByAppleUserId() {
        let userId = "apple.test.\(UUID().uuidString)"
        XCTAssertNil(AppleDisplayName.cached(forAppleUserId: userId))
        AppleDisplayName.cache("  Theo  ", forAppleUserId: userId)
        XCTAssertEqual(AppleDisplayName.cached(forAppleUserId: userId), "Theo")
    }

    func testBundledDevSignInFlagIsExpanded() {
        let raw = Bundle.main.object(forInfoDictionaryKey: "ENABLE_DEV_SIGNIN") as? String
        XCTAssertTrue(["YES", "NO"].contains(raw ?? ""), "ENABLE_DEV_SIGNIN should expand to YES or NO, got \(raw ?? "nil")")
    }

    func testTimeframeLabels() {
        XCTAssertEqual(GameFormatting.timeframeLabel(days: 7), "1 week")
        XCTAssertEqual(GameFormatting.timeframeLabel(days: 180), "6 months")
        XCTAssertEqual(GameFormatting.timeframeLabel(days: 12), "12 days")
    }
}

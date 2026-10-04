import XCTest
@testable import NudgeDeck

final class NotificationEventTests: XCTestCase {
    private func play(id: String, state: PlayState, stacked: Bool = false, rejectedNote: String? = nil) -> Play {
        Play(
            id: id, cardId: "c-\(id)", title: "Card \(id)", body: "", category: "Calls", kind: .action,
            fromId: "u1", toId: "u2", fromName: "Alice", toName: "Bob", state: state,
            stackedOnPlayId: stacked ? "base" : nil, stackedOnTitle: nil,
            counteredPlayId: nil, counteredTitle: nil, delivered: true, deliverAt: 0, playedAt: 0,
            respondedAt: nil, proofType: nil, proofText: nil, proofUrl: nil,
            proofRejectedNote: rejectedNote, stolenCardTitle: nil
        )
    }

    func testOnlyPendingIncomingAndProofsBecomeEvents() {
        let inbox = Inbox(
            incoming: [play(id: "1", state: .pending), play(id: "2", state: .proofSubmitted)],
            toReview: [play(id: "3", state: .proofSubmitted)],
            waitingOnPartner: [play(id: "4", state: .pending)]
        )
        let events = NotificationService.events(in: inbox)
        XCTAssertEqual(events.map(\.title), ["👀 You've been nudged.", "Bob sent proof"])
        XCTAssertEqual(events.map(\.body), ["Your person sent you something.", "A Nudge is waiting for your review."])
        XCTAssertEqual(events.map(\.screen), [.inbox, .inbox])
        XCTAssertEqual(events.map(\.playId), ["1", "3"])
    }

    func testStackedAndRejectedCardsGetDistinctKeysAndTitles() {
        let stacked = NotificationService.events(in: Inbox(incoming: [play(id: "1", state: .pending, stacked: true)], toReview: [], waitingOnPartner: []))
        XCTAssertEqual(stacked.first?.title, "👀 You've been nudged.")
        XCTAssertEqual(stacked.first?.body, "Someone stacked another Nudge on you.")
        XCTAssertEqual(stacked.first?.screen, .inbox)

        let retry = NotificationService.events(in: Inbox(incoming: [play(id: "1", state: .pending, rejectedNote: "Closer!")], toReview: [], waitingOnPartner: []))
        XCTAssertEqual(retry.first?.title, "Alice wants another try")
        XCTAssertEqual(retry.first?.body, "Someone wants your attention.")
        XCTAssertNotEqual(retry.first?.key, stacked.first?.key)
    }

    @MainActor
    func testRouterReadsScreenAndPlayIdFromUserInfo() {
        let router = NotificationRouter.shared
        router.consume()
        router.handle(userInfo: ["screen": "recap", "playId": "p1"])
        XCTAssertEqual(router.destination, .recap)
        XCTAssertEqual(router.playId, "p1")
        router.consume()
        XCTAssertNil(router.destination)
        XCTAssertNil(router.playId)
    }

    @MainActor
    func testRouterDefaultsPlayIdOnlyPayloadToInbox() {
        let router = NotificationRouter.shared
        router.consume()
        router.handle(userInfo: ["playId": "sim"])
        XCTAssertEqual(router.destination, .inbox)
        XCTAssertEqual(router.playId, "sim")
        router.consume()
    }
}

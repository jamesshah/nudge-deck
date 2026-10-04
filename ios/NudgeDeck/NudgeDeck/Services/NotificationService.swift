import Foundation
import UIKit
import UserNotifications

/// Local-notification fallback: while the app is running, inbox and season changes
/// become banners. Skipped once APNs is fully ready, since the backend then sends real pushes.
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private var seenKeys: Set<String>?
    /// Nil until the first `coupleDidUpdate` baseline is recorded.
    private var previousCouple: Couple?
    private var hasCoupleBaseline = false

    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func inboxDidUpdate(_ inbox: Inbox) {
        syncBadge(count: inbox.needsAttentionCount)
        let events = Self.events(in: inbox)
        let keys = Set(events.map(\.key))
        defer { seenKeys = (seenKeys ?? []).union(keys) }
        // The first snapshot after launch is existing state, not news.
        guard let seen = seenKeys else { return }
        // A device token alone is not enough: keep the foreground fallback until
        // the backend confirms all APNs provider credentials are configured.
        guard !PushRegistration.shared.isRemotePushReady else { return }
        for event in events where !seen.contains(event.key) {
            post(
                title: event.title,
                body: event.body,
                id: event.key,
                screen: event.screen,
                playId: event.playId,
                badge: inbox.needsAttentionCount
            )
        }
    }

    func coupleDidUpdate(_ couple: Couple?) {
        defer {
            previousCouple = couple
            hasCoupleBaseline = true
        }
        // First snapshot after launch / sign-in is existing state, not news.
        guard hasCoupleBaseline else { return }
        guard !PushRegistration.shared.isRemotePushReady else { return }

        if let prev = previousCouple, couple == nil {
            post(
                title: "Unpaired",
                body: "You can start a new season anytime.",
                id: "unpaired:\(prev.id)",
                screen: .deck,
                badge: 0
            )
            return
        }

        if let prev = previousCouple, let next = couple, prev.id != next.id, next.status == .active {
            post(
                title: "New season!",
                body: "Your Deck is ready — Nudge them.",
                id: "new-season:\(next.id)",
                screen: .deck
            )
            return
        }

        if let prev = previousCouple, prev.status == .active,
           let next = couple, next.id == prev.id, next.status == .ended {
            post(
                title: "That's a wrap!",
                body: "Open Nudge Deck for your season recap.",
                id: "season-ended:\(next.id)",
                screen: .recap
            )
        }
    }

    func reset() {
        seenKeys = nil
        previousCouple = nil
        hasCoupleBaseline = false
        syncBadge(count: 0)
    }

    func syncBadge(count: Int) {
        Task {
            try? await UNUserNotificationCenter.current().setBadgeCount(count)
        }
    }

    struct Event: Equatable {
        let key: String
        let title: String
        let body: String
        let screen: NotificationDestination
        let playId: String
    }

    nonisolated static func events(in inbox: Inbox) -> [Event] {
        let incoming = inbox.incoming
            .filter { $0.state == .pending }
            .map { play in
                Event(
                    key: "\(play.id):\(play.state.rawValue):\(play.proofRejectedNote ?? "")",
                    title: play.proofRejectedNote == nil
                        ? "👀 You've been nudged."
                        : "\(play.fromName) wants another try",
                    body: play.proofRejectedNote == nil
                        ? (play.stackedOnPlayId == nil
                            ? "Your person sent you something."
                            : "Someone stacked another Nudge on you.")
                        : "Someone wants your attention.",
                    screen: .inbox,
                    playId: play.id
                )
            }
        let proofs = inbox.toReview.map { play in
            Event(
                key: "\(play.id):proof",
                title: "\(play.toName) sent proof",
                body: "A Nudge is waiting for your review.",
                screen: .inbox,
                playId: play.id
            )
        }
        return incoming + proofs
    }

    private func post(
        title: String,
        body: String,
        id: String,
        screen: NotificationDestination,
        playId: String? = nil,
        badge: Int? = nil
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        var userInfo: [String: String] = ["screen": screen.rawValue]
        if let playId { userInfo["playId"] = playId }
        content.userInfo = userInfo
        if let badge { content.badge = NSNumber(value: badge) }
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

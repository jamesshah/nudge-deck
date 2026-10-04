import Combine
import Foundation

/// Destination for a tapped push / local notification.
enum NotificationDestination: String, Equatable {
    case inbox
    case deck
    case recap
    case timeline
}

/// Holds a pending deep link until `MainTabView` (or another screen) can consume it.
@MainActor
final class NotificationRouter: ObservableObject {
    static let shared = NotificationRouter()

    @Published private(set) var destination: NotificationDestination?
    @Published private(set) var playId: String?

    func handle(userInfo: [AnyHashable: Any]) {
        if let raw = userInfo["screen"] as? String,
           let screen = NotificationDestination(rawValue: raw) {
            destination = screen
        } else if userInfo["playId"] != nil {
            // Sample / older payloads with only playId still mean "open Inbox".
            destination = .inbox
        }
        if let id = userInfo["playId"] as? String, !id.isEmpty {
            playId = id
        }
    }

    func consume() {
        destination = nil
        playId = nil
    }
}

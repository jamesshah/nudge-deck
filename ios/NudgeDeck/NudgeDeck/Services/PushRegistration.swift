import ConvexMobile
import Foundation

/// Connects the APNs device token to the signed-in player's account.
@MainActor
final class PushRegistration {
    static let shared = PushRegistration()

    private(set) var deviceToken: String?
    private var sessionToken: String?
    private(set) var backendCanPush = false

    var isRemotePushReady: Bool { deviceToken != nil && backendCanPush }

    private var environment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    func didRegister(deviceToken data: Data) {
        deviceToken = data.map { String(format: "%02x", $0) }.joined()
        Task { await registerIfReady() }
    }

    func didFailToRegister(_ error: Error) {
        // Expected without an APNs entitlement (e.g. Simulator builds with no team).
        print("APNs registration unavailable, using local notifications: \(error.localizedDescription)")
    }

    func sessionDidStart(token: String) {
        sessionToken = token
        Task {
            await NotificationService.shared.requestAuthorization()
            await registerIfReady()
        }
    }

    func sessionDidEnd() {
        if let deviceToken, let sessionToken {
            let args: [String: ConvexEncodable?] = ["sessionToken": sessionToken, "apnsToken": deviceToken]
            Task { try? await Backend.client.mutation("devices:unregister", with: args) }
        }
        sessionToken = nil
        backendCanPush = false
        NotificationService.shared.reset()
        NotificationRouter.shared.consume()
    }

    private func registerIfReady() async {
        guard let deviceToken, let sessionToken else { return }
        do {
            let configured: Bool = try await Backend.client.mutation(
                "devices:register",
                with: ["sessionToken": sessionToken, "apnsToken": deviceToken, "environment": environment]
            )
            backendCanPush = configured
            if !configured {
                print("Device token saved, but APNs provider credentials are not configured; using foreground fallback.")
            }
        } catch {
            backendCanPush = false
            print("Couldn't register device for push: \(Backend.message(for: error))")
        }
    }
}

import AuthenticationServices
import Combine
import ConvexMobile
import Foundation

@MainActor
final class SessionStore: ObservableObject {
    enum State: Equatable {
        case loading
        case signedOut
        case signedIn(token: String, me: Me)
    }

    struct PendingAppleCredentials: Equatable {
        let identityToken: String
        let appleUserId: String
    }

    @Published private(set) var state: State = .loading
    @Published var errorMessage: String?
    @Published private(set) var isWorking = false
    /// Set when Apple authorizes but doesn't return a usable name (common after the first auth).
    @Published private(set) var pendingAppleCredentials: PendingAppleCredentials?

    /// Nil only for previews, which must never open a connection.
    private let client: ConvexClient?
    private var meSubscription: AnyCancellable?

    init(client: ConvexClient = Backend.client) {
        self.client = client
        if let token = KeychainStore.readToken() {
            watchSession(token: token)
        } else {
            state = .signedOut
        }
    }

    #if DEBUG
    /// Offline session for SwiftUI previews. Skips the Keychain and never calls the backend.
    init(previewState: State, isWorking: Bool = false) {
        client = nil
        state = previewState
        self.isWorking = isWorking
    }
    #endif

    var token: String? {
        if case .signedIn(let token, _) = state { return token }
        return nil
    }

    #if DEBUG
    func signInDev(name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Enter a name to sign in."
            return
        }
        var args = Backend.deviceTimeArgs
        args["name"] = trimmed
        guard let client else { return }
        await signIn {
            let token: String = try await client.mutation("auth:signInDev", with: args)
            return token
        }
    }
    #endif

    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if let message = Self.appleSignInErrorMessage(for: error) { errorMessage = message }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8)
            else {
                errorMessage = "Apple didn't return an identity token. Please try again."
                return
            }
            let appleUserId = credential.user
            let name = AppleDisplayName.from(credential.fullName)
                ?? AppleDisplayName.cached(forAppleUserId: appleUserId)
            if let name {
                AppleDisplayName.cache(name, forAppleUserId: appleUserId)
                await completeAppleSignIn(identityToken: identityToken, name: name)
            } else {
                // Apple only shares the name on the first authorization for this app.
                pendingAppleCredentials = PendingAppleCredentials(
                    identityToken: identityToken,
                    appleUserId: appleUserId
                )
            }
        }
    }

    func submitAppleDisplayName(_ name: String) async {
        guard let pending = pendingAppleCredentials else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Enter a name to continue."
            return
        }
        AppleDisplayName.cache(trimmed, forAppleUserId: pending.appleUserId)
        pendingAppleCredentials = nil
        await completeAppleSignIn(identityToken: pending.identityToken, name: trimmed)
    }

    func cancelPendingAppleSignIn() {
        pendingAppleCredentials = nil
    }

    private func completeAppleSignIn(identityToken: String, name: String) async {
        var args = Backend.deviceTimeArgs
        args["identityToken"] = identityToken
        args["name"] = name
        guard let client else { return }
        await signIn {
            let token: String = try await client.action("auth:signInWithApple", with: args)
            return token
        }
    }

    /// Nil when the user cancelled. Unsigned builds, or builds without the Sign in with Apple
    /// capability, fail with `.unknown` or `.failed`, so those get a setup hint.
    nonisolated static func appleSignInErrorMessage(for error: Error) -> String? {
        switch (error as? ASAuthorizationError)?.code {
        case .canceled:
            return nil
        case .unknown, .failed, .notHandled:
            return "Sign in with Apple isn't available in this build. It needs to be signed with the Sign in with Apple capability enabled."
        default:
            return "Sign in with Apple failed: \(error.localizedDescription)"
        }
    }

    func signOut() async {
        guard let token, let client else { return }
        PushRegistration.shared.sessionDidEnd()
        try? await client.mutation("auth:signOut", with: ["sessionToken": token])
        endSession()
    }

    private func signIn(_ call: @escaping () async throws -> String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let token = try await call()
            KeychainStore.saveToken(token)
            state = .loading
            watchSession(token: token)
        } catch {
            errorMessage = Backend.message(for: error)
        }
    }

    private func watchSession(token: String) {
        meSubscription = client?
            .subscribe(to: "users:me", with: ["sessionToken": token], yielding: Me?.self)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.errorMessage = Backend.message(for: error)
                    }
                },
                receiveValue: { [weak self] me in
                    guard let self else { return }
                    if let me {
                        let wasSignedIn = self.token != nil
                        self.state = .signedIn(token: token, me: me)
                        if !wasSignedIn { PushRegistration.shared.sessionDidStart(token: token) }
                    } else {
                        self.endSession()
                    }
                }
            )
    }

    private func endSession() {
        meSubscription = nil
        KeychainStore.deleteToken()
        state = .signedOut
    }
}

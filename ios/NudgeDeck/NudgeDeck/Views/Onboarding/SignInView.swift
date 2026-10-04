import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var appleName = ""
    @State private var devName = ""
    @FocusState private var nameFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    private let showsDevSignIn: Bool

    init(showsDevSignIn: Bool = AppConfig.devSignInEnabled) {
        self.showsDevSignIn = showsDevSignIn
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                // Equal spacers center the content when it fits; they collapse and the view scrolls when it doesn't.
                VStack(spacing: 0) {
                    Spacer(minLength: 24)
                    content
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.canvas.ignoresSafeArea())
        .onChange(of: session.pendingAppleCredentials) { _, pending in
            if pending == nil { appleName = "" }
        }
    }

    private var content: some View {
        VStack(spacing: 28) {
            hero

            if session.pendingAppleCredentials != nil {
                appleNamePrompt
            } else {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName]
                } onCompletion: { result in
                    Task { await session.handleAppleSignIn(result) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                // The underlying Apple button keeps its first style, so rebuild it when the scheme changes.
                .id(colorScheme)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            #if DEBUG
            if showsDevSignIn && session.pendingAppleCredentials == nil { devSignIn }
            #endif
        }
    }

    private var appleNamePrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What should we call you?")
                .font(.headline)
            Text("Apple only shares your name the first time you sign in. Enter it once and we’ll remember it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                TextField("Your name", text: $appleName)
                    .textContentType(.givenName)
                    .submitLabel(.go)
                    .focused($nameFocused)
                    .onSubmit(submitAppleName)
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Button(action: submitAppleName) {
                    if session.isWorking {
                        ProgressView()
                    } else {
                        Text("Continue")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(appleName.trimmingCharacters(in: .whitespaces).isEmpty || session.isWorking)
            }
            Button("Back") {
                session.cancelPendingAppleSignIn()
            }
            .font(.subheadline)
            .disabled(session.isWorking)
        }
        .padding(16)
        .calmSurface(radius: 18)
        .onAppear { nameFocused = true }
    }

    private func submitAppleName() {
        nameFocused = false
        Task { await session.submitAppleDisplayName(appleName) }
    }

    private var hero: some View {
        VStack(spacing: 16) {
            Image("BrandIcon")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 112, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                .shadow(color: .black.opacity(0.14), radius: 14, y: 8)
                .accessibilityHidden(true)

            Text("Nudge Deck")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
            Text("Little things. More together.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    #if DEBUG
    private var devSignIn: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Quick sign-in for testing", systemImage: "hammer.fill")
                .font(.subheadline.weight(.semibold))
            Text("Creates a throwaway account with just a name. Use a different name on each Simulator to pair two players.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                TextField("Your name", text: $devName)
                    .textContentType(.givenName)
                    .submitLabel(.go)
                    .focused($nameFocused)
                    .onSubmit(signInDev)
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Button(action: signInDev) {
                    if session.isWorking {
                        ProgressView()
                    } else {
                        Text("Start")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(devName.trimmingCharacters(in: .whitespaces).isEmpty || session.isWorking)
            }
        }
        .padding(16)
        .calmSurface(radius: 18)
    }

    private func signInDev() {
        nameFocused = false
        Task { await session.signInDev(name: devName) }
    }
    #endif
}

#if DEBUG
#Preview("Sign in · dev sign-in hidden") {
    SignInView(showsDevSignIn: false).previewEnvironment(session: .previewSignedOut())
}

#Preview("Sign in · dev sign-in hidden · dark") {
    SignInView(showsDevSignIn: false)
        .previewEnvironment(session: .previewSignedOut())
        .preferredColorScheme(.dark)
}

#Preview("Sign in · dev sign-in") {
    SignInView(showsDevSignIn: true).previewEnvironment(session: .previewSignedOut())
}

#Preview("Sign in · dev sign-in · dark") {
    SignInView(showsDevSignIn: true)
        .previewEnvironment(session: .previewSignedOut())
        .preferredColorScheme(.dark)
}

#Preview("Sign in · signing in") {
    SignInView(showsDevSignIn: true).previewEnvironment(session: .previewSignedOut(isWorking: true))
}

#Preview("Sign in · SE · hidden", traits: .fixedLayout(width: 375, height: 667)) {
    SignInView(showsDevSignIn: false).previewEnvironment(session: .previewSignedOut())
}

#Preview("Sign in · SE · dev sign-in · dark", traits: .fixedLayout(width: 375, height: 667)) {
    SignInView(showsDevSignIn: true)
        .previewEnvironment(session: .previewSignedOut())
        .preferredColorScheme(.dark)
}

#Preview("Sign in · Pro Max · hidden", traits: .fixedLayout(width: 440, height: 956)) {
    SignInView(showsDevSignIn: false).previewEnvironment(session: .previewSignedOut())
}

#Preview("Sign in · Pro Max · dev sign-in · dark", traits: .fixedLayout(width: 440, height: 956)) {
    SignInView(showsDevSignIn: true)
        .previewEnvironment(session: .previewSignedOut())
        .preferredColorScheme(.dark)
}
#endif

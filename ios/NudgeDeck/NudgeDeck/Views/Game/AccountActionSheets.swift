import SwiftUI

struct SignOutSheet: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.brand)
                    .padding(.top, 12)
                Text("Sign out?")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("You'll need to sign in again to keep playing. Your account and data stay until you delete them.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
                Button(role: .destructive) {
                    Task {
                        await session.signOut()
                        dismiss()
                    }
                } label: {
                    if session.isWorking {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Sign out").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .disabled(session.isWorking)
                .accessibilityIdentifier("confirmSignOut")
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(session.isWorking)
                }
            }
        }
    }
}

struct DeleteAccountSheet: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    private var pairedMessage: String {
        if store.couple?.partner != nil {
            return "This permanently deletes your account and signs you out. You'll also unpair from \(store.partnerName)."
        }
        return "This permanently deletes your account, any open invite, and signs you out. This can't be undone."
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "trash")
                    .font(.system(size: 40))
                    .foregroundStyle(.red)
                    .padding(.top, 12)
                Text("Delete account?")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(pairedMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
                Button(role: .destructive) {
                    Task {
                        if await session.deleteAccount() {
                            dismiss()
                        }
                    }
                } label: {
                    if session.isWorking {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Delete account").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .disabled(session.isWorking)
                .accessibilityIdentifier("confirmDeleteAccount")
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(session.isWorking)
                }
            }
        }
    }
}

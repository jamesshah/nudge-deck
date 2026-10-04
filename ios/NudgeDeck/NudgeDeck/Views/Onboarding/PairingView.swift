import SwiftUI

struct PairingView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var store: GameStore
    @State private var timeframeDays = 30
    @State private var inviteCode = ""

    private let timeframes = [7, 30, 90, 180]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    startCard
                    Text("or")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    joinCard
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.canvas)
            .navigationTitle("Pair up")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign out") { Task { await session.signOut() } }
                }
            }
        }
    }

    private var startCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Start a season", systemImage: "sparkles")
                .font(.title3.weight(.bold))
            Text("Pick how long you two want to play. Send little Nudges, respond, and Nudge back. When it ends, you'll get a recap of the season.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker("Timeframe", selection: $timeframeDays) {
                ForEach(timeframes, id: \.self) { days in
                    Text(GameFormatting.timeframeLabel(days: days)).tag(days)
                }
            }
            .pickerStyle(.segmented)
            Button {
                Task { await store.createCouple(timeframeDays: timeframeDays) }
            } label: {
                Text("Create invite").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(store.isWorking)
        }
        .padding(18)
        .calmSurface()
    }

    private var joinCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Join your partner", systemImage: "person.2.fill")
                .font(.title3.weight(.bold))
            Text("Got a 6-character code from your person? Enter it here and you'll both get a Deck of Nudges.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("Invite code", text: $inviteCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.title2.monospaced().weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(12)
                .background(Theme.secondarySurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 0.75)
                }
            Button {
                Task { await store.joinCouple(code: inviteCode) }
            } label: {
                Text("Join").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(GameFormatting.normalizedInviteCode(inviteCode).count < 6 || store.isWorking)
        }
        .padding(18)
        .calmSurface()
    }
}

struct WaitingForPartnerView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var store: GameStore
    let couple: Couple
    @State private var showingCustomCard = false
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 10) {
                        Text("Share this code with your partner")
                            .font(.headline)
                        Text(couple.inviteCode)
                            .font(.system(size: 44, weight: .heavy, design: .monospaced))
                            .kerning(6)
                            .textSelection(.enabled)
                        Text("\(GameFormatting.timeframeLabel(days: Int(couple.timeframeDays))) season · starts when they join")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack {
                            ShareLink(item: Self.inviteShareText(code: couple.inviteCode)) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.borderedProminent)
                            Button {
                                UIPasteboard.general.string = couple.inviteCode
                                copied = true
                            } label: {
                                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                        }
                        .controlSize(.large)
                        .padding(.top, 6)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .calmSurface(radius: 24)

                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Waiting for your partner to join…")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("While you wait")
                            .font(.headline)
                        Text("Write up to \(Int(store.hand.customCardsLeftToWrite)) custom Nudges only you two would get. They'll land in your Deck.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Write a custom Nudge") { showingCustomCard = true }
                            .disabled(store.hand.customCardsLeftToWrite < 1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.canvas)
            .navigationTitle("Invite sent")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel invite", role: .destructive) { Task { await store.cancelInvite() } }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign out") { Task { await session.signOut() } }
                }
            }
            .sheet(isPresented: $showingCustomCard) { CustomCardSheet() }
        }
    }

    static func inviteShareText(code: String) -> String {
        """
        Nudge with me on Nudge Deck. Join with code \(code).

        Get the app: \(AppConfig.appStoreURL.absoluteString)
        """
    }
}

#if DEBUG
#Preview("Pair up") {
    PairingView().previewEnvironment(.previewUnpaired())
}

#Preview("Pair up · dark") {
    PairingView()
        .previewEnvironment(.previewUnpaired())
        .preferredColorScheme(.dark)
}

#Preview("Invite code") {
    WaitingForPartnerView(couple: PreviewData.waitingCouple).previewEnvironment(.previewWaiting())
}

#Preview("Invite code · dark") {
    WaitingForPartnerView(couple: PreviewData.waitingCouple)
        .previewEnvironment(.previewWaiting())
        .preferredColorScheme(.dark)
}
#endif

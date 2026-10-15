import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var store: GameStore

    @State private var name = ""
    @State private var quietEnabled = false
    @State private var quietStart = GameFormatting.date(fromMinutes: 22 * 60)
    @State private var quietEnd = GameFormatting.date(fromMinutes: 7 * 60)
    /// Last successfully saved quiet hours (`nil` = off). Draft is compared against this.
    @State private var savedQuietHours: QuietHours?
    @State private var loaded = false
    @State private var showingCustomCard = false
    @State private var confirmingStartNewSeason = false
    @State private var confirmingUnpair = false
    @State private var confirmingSignOut = false
    @State private var confirmingDeleteAccount = false

    private var me: Player? { store.couple?.me }
    private var canManageSeason: Bool {
        guard let status = store.couple?.status else { return false }
        return status == .active || status == .ended
    }

    private var seasonAlreadyOver: Bool {
        store.couple?.status == .ended
    }

    /// True when the draft differs from the last saved quiet-hours setting.
    private var hasUnsavedQuietHours: Bool {
        guard loaded else { return false }
        if quietEnabled {
            let start = GameFormatting.minutes(from: quietStart)
            let end = GameFormatting.minutes(from: quietEnd)
            guard let saved = savedQuietHours else { return true }
            return saved.startMinutes != start || saved.endMinutes != end
        }
        return savedQuietHours != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    HStack {
                        TextField("Name", text: $name)
                            .textContentType(.givenName)
                        if let me, name.trimmingCharacters(in: .whitespaces) != me.name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button("Save") { Task { await store.rename(to: name.trimmingCharacters(in: .whitespaces)) } }
                        }
                    }
                    if let me {
                        LabeledContent("Time zone", value: me.timeZone)
                    }
                }

                Section {
                    Toggle("Quiet hours", isOn: $quietEnabled)
                    if quietEnabled {
                        DatePicker("From", selection: $quietStart, displayedComponents: .hourAndMinute)
                        DatePicker("Until", selection: $quietEnd, displayedComponents: .hourAndMinute)
                    }
                    Button {
                        Task { await saveQuietHours() }
                    } label: {
                        if store.isWorking {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text(hasUnsavedQuietHours ? "Save quiet hours" : "Quiet hours saved")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isWorking || !hasUnsavedQuietHours)
                } footer: {
                    Text("Nudges \(store.partnerName) sends during quiet hours are held and delivered when they end.")
                }

                Section("Season") {
                    if let couple = store.couple {
                        LabeledContent("Length", value: GameFormatting.timeframeLabel(days: Int(couple.timeframeDays)))
                        if let end = couple.endsAt {
                            LabeledContent(couple.status == .ended ? "Ended" : "Ends",
                                           value: Date(timeIntervalSince1970: end / 1000).formatted(date: .abbreviated, time: .shortened))
                        }
                        if let partner = couple.partner {
                            LabeledContent("Partner", value: partner.name)
                        }
                    }
                    Button("Write a custom Nudge (\(Int(store.hand.customCardsLeftToWrite)) left)") {
                        showingCustomCard = true
                    }
                    .disabled(store.hand.customCardsLeftToWrite < 1 || store.couple?.status != .active)
                }

                if canManageSeason {
                    Section {
                        Button("Start new season") {
                            confirmingStartNewSeason = true
                        }
                        .disabled(store.isWorking)
                        Button("Unpair", role: .destructive) {
                            confirmingUnpair = true
                        }
                        .disabled(store.isWorking)
                    } footer: {
                        Text(seasonAlreadyOver
                            ? "Start a new season with \(store.partnerName), or unpair to invite someone else."
                            : "Start a new season early with \(store.partnerName), or unpair to end and leave pairing.")
                    }
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        confirmingSignOut = true
                    }
                    .disabled(session.isWorking)
                    .accessibilityIdentifier("openSignOut")
                    Button("Delete account", role: .destructive) {
                        confirmingDeleteAccount = true
                    }
                    .disabled(session.isWorking || store.isWorking)
                    .accessibilityIdentifier("openDeleteAccount")
                } footer: {
                    Text("Delete account permanently removes your profile and unpairs you if you're in a season.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle("Settings")
            .sheet(isPresented: $showingCustomCard) { CustomCardSheet() }
            .sheet(isPresented: $confirmingStartNewSeason) {
                StartNewSeasonSheet(seasonAlreadyOver: seasonAlreadyOver)
                    .presentationDetents([.medium, .large])
                    .environmentObject(store)
            }
            .sheet(isPresented: $confirmingUnpair) {
                UnpairSheet(seasonAlreadyOver: seasonAlreadyOver)
                    .presentationDetents([.medium])
                    .environmentObject(store)
            }
            .sheet(isPresented: $confirmingSignOut) {
                SignOutSheet()
                    .presentationDetents([.medium])
                    .environmentObject(session)
            }
            .sheet(isPresented: $confirmingDeleteAccount) {
                DeleteAccountSheet()
                    .presentationDetents([.medium])
                    .environmentObject(session)
                    .environmentObject(store)
            }
            .onAppear(perform: loadFromProfile)
        }
    }

    private func loadFromProfile() {
        guard !loaded, let me else { return }
        name = me.name
        savedQuietHours = me.quietHours
        if let quiet = me.quietHours {
            quietEnabled = true
            quietStart = GameFormatting.date(fromMinutes: quiet.startMinutes)
            quietEnd = GameFormatting.date(fromMinutes: quiet.endMinutes)
        }
        loaded = true
    }

    private func saveQuietHours() async {
        guard loaded, hasUnsavedQuietHours else { return }
        let start = GameFormatting.minutes(from: quietStart)
        let end = GameFormatting.minutes(from: quietEnd)
        if quietEnabled {
            if await store.setQuietHours(startMinutes: start, endMinutes: end) {
                savedQuietHours = QuietHours(startMinutes: start, endMinutes: end)
            }
        } else if await store.setQuietHours(startMinutes: nil, endMinutes: nil) {
            savedQuietHours = nil
        }
    }
}

#if DEBUG
#Preview("Settings") {
    SettingsView().previewEnvironment()
}

#Preview("Settings · dark") {
    SettingsView()
        .previewEnvironment()
        .preferredColorScheme(.dark)
}
#endif

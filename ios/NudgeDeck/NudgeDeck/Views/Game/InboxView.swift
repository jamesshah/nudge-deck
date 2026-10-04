import SwiftUI

struct InboxView: View {
    @EnvironmentObject private var store: GameStore
    @State private var completing: Play?
    @State private var countering: Play?
    @State private var refusing: Play?
    @State private var rejecting: Play?
    @State private var rejectNote = ""

    private var inbox: Inbox { store.inbox }
    private var isEmpty: Bool {
        inbox.incoming.isEmpty && inbox.toReview.isEmpty && inbox.waitingOnPartner.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if isEmpty {
                    ContentUnavailableView(
                        "No Nudges yet.",
                        systemImage: "tray",
                        description: Text("Fix that. 👀 When \(store.partnerName) sends one, it lands here. Your move: Nudge them back from your Deck.")
                    )
                } else {
                    list
                }
            }
            .background(Theme.canvas)
            .navigationTitle("Inbox")
            .sheet(item: $completing) { play in CompleteProofSheet(play: play) }
            .sheet(item: $countering) { play in
                CounterSheet(play: play)
                    .presentationDetents([.medium, .large])
            }
            .confirmationDialog(
                "Not feeling it?",
                isPresented: Binding(get: { refusing != nil }, set: { if !$0 { refusing = nil } }),
                titleVisibility: .visible,
                presenting: refusing
            ) { play in
                Button("Pass \"\(play.title)\"", role: .destructive) {
                    Task { await store.refuse(play) }
                }
            } message: { _ in
                Text("We'll pretend that didn't happen. \(store.partnerName) gets one Nudge from your Deck to send back.")
            }
            .alert(
                "Ask for another try",
                isPresented: Binding(get: { rejecting != nil }, set: { if !$0 { rejecting = nil } }),
                presenting: rejecting
            ) { play in
                TextField("What's missing?", text: $rejectNote)
                Button("Send back") {
                    let note = rejectNote
                    rejectNote = ""
                    Task { await store.rejectProof(play, note: note) }
                }
                Button("Cancel", role: .cancel) { rejectNote = "" }
            } message: { _ in
                Text("The Nudge goes back to \(store.partnerName) to try again.")
            }
        }
    }

    private var list: some View {
        List {
            if !inbox.incoming.isEmpty {
                Section("Nudges on you") {
                    ForEach(inbox.incoming) { play in
                        IncomingRow(
                            play: play,
                            partnerName: store.partnerName,
                            hasCounter: !store.hand.counterCards.isEmpty,
                            onComplete: { completing = play },
                            onCounter: { countering = play },
                            onRefuse: { refusing = play }
                        )
                        .listRowBackground(Theme.surface)
                    }
                }
            }
            if !inbox.toReview.isEmpty {
                Section("Proof to review") {
                    ForEach(inbox.toReview) { play in
                        VStack(alignment: .leading, spacing: 12) {
                            CardFace(play: play)
                            ProofView(play: play)
                            HStack {
                                Button {
                                    Task { await store.acceptProof(play) }
                                } label: {
                                    Label("Accept", systemImage: "checkmark.seal.fill").frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                Button {
                                    rejecting = play
                                } label: {
                                    Label("Try again", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(Theme.secondaryText)
                            }
                            // Inside a List row the automatic label style drops the icon.
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                            .font(.subheadline.weight(.semibold))
                            .disabled(store.isWorking)
                        }
                        .padding(.vertical, 6)
                        .listRowBackground(Theme.surface)
                    }
                }
            }
            if !inbox.waitingOnPartner.isEmpty {
                Section("Your Nudge is waiting… 👀") {
                    ForEach(inbox.waitingOnPartner) { play in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(play.title).font(.headline)
                            if play.delivered {
                                Text("Sent \(play.playedDate.formatted(.relative(presentation: .named)))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                Label(
                                    heldDeliveryMessage(for: play),
                                    systemImage: "moon.zzz.fill"
                                )
                                .font(.subheadline)
                                .foregroundStyle(Theme.warning)
                            }
                        }
                        .listRowBackground(Theme.surface)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
    }

    private func heldDeliveryMessage(for play: Play) -> String {
        guard let me = store.couple?.me else {
            return "Held for quiet hours. It will arrive when they end."
        }
        let zone = GameFormatting.timeZone(identifier: me.timeZone, utcOffsetMinutes: me.utcOffsetMinutes)
        return "Held for quiet hours. Arrives \(GameFormatting.clockTime(play.deliverDate, timeZone: zone)) your time."
    }
}

private struct IncomingRow: View {
    let play: Play
    let partnerName: String
    let hasCounter: Bool
    let onComplete: () -> Void
    let onCounter: () -> Void
    let onRefuse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardFace(play: play)
            if let stackedOn = play.stackedOnTitle {
                Label("Stacked on \"\(stackedOn)\"", systemImage: "square.stack.3d.up.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let note = play.proofRejectedNote {
                Label("\(partnerName) asked for another try: \(note)", systemImage: "arrow.uturn.backward.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
            }
            if play.state == .proofSubmitted {
                Label("Proof sent. Waiting for \(partnerName) — nice work.", systemImage: "paperplane.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    Button(action: onComplete) {
                        Label("Complete", systemImage: "checkmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    HStack(spacing: 8) {
                        Button(action: onCounter) {
                            Label("Counter", systemImage: "shield.lefthalf.filled").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.secondaryText)
                        .disabled(!hasCounter)
                        Button(role: .destructive, action: onRefuse) {
                            Label("Pass", systemImage: "hand.raised.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.destructive)
                    }
                }
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.vertical, 6)
    }
}

struct CounterSheet: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    let play: Play

    var body: some View {
        NavigationStack {
            List {
                Section {
                    CardFace(play: play)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } footer: {
                    Text("A counter knocks this Nudge out for good. Your counter is used up too.")
                }
                Section("Your counters") {
                    if store.hand.counterCards.isEmpty {
                        Text("You're out of counters.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.hand.counterCards) { card in
                        Button {
                            Task {
                                if await store.counter(play, with: card) { dismiss() }
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "shield.lefthalf.filled")
                                    .font(.title3)
                                    .foregroundStyle(Theme.brand)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(card.title)
                                        .font(.headline)
                                        .foregroundStyle(Theme.primaryText)
                                    Text(card.body)
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(store.isWorking)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle("Block this Nudge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// Shows a submitted proof: text, photo, or voice note.
struct ProofView: View {
    let play: Play
    @StateObject private var audio = AudioProofPlayer()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch play.proofType {
            case .some(.photo):
                if let url = play.reachableProofURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit()
                        case .failure:
                            Label("Couldn't load the photo", systemImage: "photo.badge.exclamationmark")
                                .foregroundStyle(.secondary)
                        default:
                            ProgressView().frame(maxWidth: .infinity, minHeight: 160)
                        }
                    }
                    .frame(maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            case .some(.audio):
                if let url = play.reachableProofURL {
                    Button {
                        audio.toggle(url: url)
                    } label: {
                        Label(audio.isPlaying ? "Pause voice note" : "Play voice note",
                              systemImage: audio.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    }
                    .buttonStyle(.bordered)
                }
            case .some(.text), .none:
                EmptyView()
            }
            if let text = play.proofText {
                Text("“\(text)”")
                    .font(.body)
                    .italic()
            }
        }
    }
}

#if DEBUG
#Preview("Inbox") {
    InboxView().previewEnvironment()
}

#Preview("Inbox · empty") {
    InboxView().previewEnvironment(.previewPaired(inbox: .empty))
}

#Preview("Inbox · pending proof") {
    InboxView().previewEnvironment(.previewPaired(inbox: PreviewData.pendingProofInbox))
}

#Preview("Inbox · pending proof · dark") {
    InboxView()
        .previewEnvironment(.previewPaired(inbox: PreviewData.pendingProofInbox))
        .preferredColorScheme(.dark)
}

#Preview("Inbox · held for quiet hours") {
    InboxView().previewEnvironment(.previewPaired(inbox: PreviewData.quietHoursInbox))
}

#Preview("Inbox · dark") {
    InboxView()
        .previewEnvironment()
        .preferredColorScheme(.dark)
}

#Preview("Counter sheet") {
    CounterSheet(play: PreviewData.incomingPending).previewEnvironment()
}

#Preview("Counter sheet · dark") {
    CounterSheet(play: PreviewData.incomingPending)
        .previewEnvironment()
        .preferredColorScheme(.dark)
}

#Preview("Counter sheet · none left") {
    CounterSheet(play: PreviewData.incomingPending).previewEnvironment(.previewPaired(hand: PreviewData.emptyHand))
}

#Preview("Text proof", traits: .sizeThatFitsLayout) {
    ProofView(play: PreviewData.pendingProofReview).padding()
}
#endif

import SwiftUI

private enum AppTab: Hashable {
    case deck
    case inbox
    case timeline
    case recap
    case settings
}

struct MainTabView: View {
    @EnvironmentObject private var store: GameStore
    @ObservedObject private var notificationRouter = NotificationRouter.shared
    @State private var selectedTab: AppTab = .deck

    private var seasonEnded: Bool {
        store.couple?.status == .ended
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            if !seasonEnded {
                HandView()
                    .tabItem { Label("Deck", systemImage: "rectangle.stack.fill") }
                    .tag(AppTab.deck)
                InboxView()
                    .tabItem { Label("Inbox", systemImage: "tray.full.fill") }
                    .badge(store.inbox.needsAttentionCount)
                    .tag(AppTab.inbox)
            }
            TimelineScreen()
                .tabItem { Label("Timeline", systemImage: "clock.fill") }
                .tag(AppTab.timeline)
            RecapView()
                .tabItem { Label("Recap", systemImage: "trophy.fill") }
                .tag(AppTab.recap)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .onAppear {
            syncSelectedTab()
            applyPendingNotificationRoute()
        }
        .onChange(of: store.couple?.status) { _, _ in
            syncSelectedTab()
            applyPendingNotificationRoute()
        }
        .onChange(of: notificationRouter.destination) { _, _ in
            applyPendingNotificationRoute()
        }
    }

    private func syncSelectedTab() {
        if seasonEnded {
            if selectedTab == .deck || selectedTab == .inbox {
                selectedTab = .recap
            }
        }
    }

    private func applyPendingNotificationRoute() {
        guard let destination = notificationRouter.destination else { return }
        selectedTab = tab(for: destination)
        notificationRouter.consume()
    }

    private func tab(for destination: NotificationDestination) -> AppTab {
        switch destination {
        case .inbox:
            return seasonEnded ? .recap : .inbox
        case .deck:
            return seasonEnded ? .recap : .deck
        case .timeline:
            return .timeline
        case .recap:
            return .recap
        }
    }
}

struct SeasonHeader: View {
    let couple: Couple

    var body: some View {
        TimelineView(.periodic(from: .now, by: 3600)) { context in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(couple.status == .ended ? "Season over" : "\(GameFormatting.daysLeft(endsAt: couple.endsAt, now: context.date)) days left")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(GameFormatting.timeframeLabel(days: Int(couple.timeframeDays)) + " season")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: GameFormatting.seasonProgress(startedAt: couple.startedAt, endsAt: couple.endsAt, now: context.date))
                    .tint(Theme.brand)
            }
        }
    }
}

#if DEBUG
#Preview("Main tabs") {
    MainTabView().previewEnvironment()
}

#Preview("Main tabs · Dark") {
    MainTabView().previewEnvironment()
        .preferredColorScheme(.dark)
}

#Preview("Main tabs · season over") {
    MainTabView().previewEnvironment(.previewEnded())
}

#Preview("Main tabs · season over · Dark") {
    MainTabView().previewEnvironment(.previewEnded())
        .preferredColorScheme(.dark)
}

#Preview("Season header", traits: .sizeThatFitsLayout) {
    SeasonHeader(couple: PreviewData.pairedCouple).padding()
}
#endif

import SwiftUI

enum MainTab: Hashable, CaseIterable {
    case calendar, lists, home, budget, more

    var icon: String {
        switch self {
        case .calendar:  "calendar"
        case .lists:     "list.bullet.rectangle.fill"
        case .home:      "house.fill"
        case .budget:    "creditcard.fill"
        case .more:      "ellipsis.circle.fill"
        }
    }
}

struct ContentView: View {
    @Environment(AuthService.self) private var authService

    var body: some View {
        if authService.isRestoringSession {
            ZStack {
                AmbientBackground(style: .home)
                ProgressView()
                    .tint(WarmPalette.ink2)
            }
        } else if authService.isAuthenticated {
            MainTabView()
        } else {
            LoginView()
        }
    }
}

struct MainTabView: View {
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @State private var selectedTab: MainTab = .home
    @State private var loadedTabs: Set<MainTab> = [.home]
    @State private var showingChat = false
    @State private var chatInitialThread: ChatSheet.ChatThread?
    @State private var unreadCount = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                if loadedTabs.contains(tab) {
                    tabView(for: tab)
                        .opacity(selectedTab == tab ? 1 : 0)
                        .allowsHitTesting(selectedTab == tab)
                }
            }

            VStack {
                Spacer()
                FloatingTabBar(selectedTab: $selectedTab)
            }

            // Floating chat button — visible on all tabs
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button { showingChat = true } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.white)
                                .frame(width: 52, height: 52)
                                .background(TabAccent.home.color, in: Circle())
                                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

                            if unreadCount > 0 {
                                Text("\(unreadCount)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(minWidth: 18, minHeight: 18)
                                    .background(AccentTheme.rose.color, in: Circle())
                                    .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 80)
                }
            }
        }
        .ignoresSafeArea(.keyboard)
        .onChange(of: selectedTab) {
            loadedTabs.insert(selectedTab)
        }
        .sheet(isPresented: $showingChat) {
            ChatSheet(initialThread: chatInitialThread)
        }
        .onChange(of: showingChat) { _, showing in
            if !showing { chatInitialThread = nil }
        }
        .task {
            await pollUnread()
        }
    }

    private func pollUnread() async {
        while !Task.isCancelled {
            // Update badge count
            unreadCount = (try? await api.fetchUnreadMessageCount()) ?? 0

            // Fire local notifications for new messages
            if await NotificationService.shared.isAuthorized() {
                if let convos = try? await api.fetchConversations() {
                    NotificationService.shared.checkForNewMessages(convos)
                }
                let currentUser = auth.currentUser?.name ?? ""
                if let feed = try? await api.fetchActivity() {
                    NotificationService.shared.checkForNewFeedItems(
                        feed,
                        currentUser: currentUser
                    )
                }
            }

            try? await Task.sleep(for: .seconds(15))
        }
    }

    @ViewBuilder
    private func tabView(for tab: MainTab) -> some View {
        switch tab {
        case .calendar:  NavigationStack { CalendarView() }
        case .lists:     NavigationStack { FamilyListsView() }
        case .home:      NavigationStack { HomeView(selectedTab: $selectedTab) }
        case .budget:    NavigationStack { ExpensesView() }
        case .more:      NavigationStack { MoreView() }
        }
    }
}

// MARK: - Floating Glass Tab Bar

struct FloatingTabBar: View {
    @Binding var selectedTab: MainTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Image(systemName: tab.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(selectedTab == tab ? accentColor(for: tab) : WarmPalette.ink3)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                        .background {
                            if selectedTab == tab {
                                Circle()
                                    .fill(accentColor(for: tab).opacity(0.15))
                                    .frame(width: 40, height: 40)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
        .padding(.horizontal, 40)
        .padding(.bottom, 20)
    }

    private func accentColor(for tab: MainTab) -> Color {
        switch tab {
        case .calendar:  TabAccent.calendar.color
        case .lists:     TabAccent.home.color
        case .home:      TabAccent.home.color
        case .budget:    AccentTheme.terracotta.color
        case .more:      WarmPalette.ink2
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthService())
        .environment(APIService())
        .environment(HouseholdService())
        .environment(ProfileImageCache())
        .environment(MessageCache())
}

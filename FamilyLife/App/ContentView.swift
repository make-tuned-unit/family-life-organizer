import SwiftUI

enum MainTab: Hashable, CaseIterable {
    case calendar, lists, home, decisions, more

    var icon: String {
        switch self {
        case .calendar:  "calendar"
        case .lists:     "list.bullet.rectangle.fill"
        case .home:      "house.fill"
        case .decisions: "bubble.left.and.bubble.right.fill"
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
    @State private var selectedTab: MainTab = .home
    @State private var loadedTabs: Set<MainTab> = [.home]

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
        }
        .ignoresSafeArea(.keyboard)
        .onChange(of: selectedTab) {
            loadedTabs.insert(selectedTab)
        }
    }

    @ViewBuilder
    private func tabView(for tab: MainTab) -> some View {
        switch tab {
        case .calendar:  NavigationStack { CalendarView() }
        case .lists:     NavigationStack { FamilyListsView() }
        case .home:      NavigationStack { HomeView(selectedTab: $selectedTab) }
        case .decisions: NavigationStack { DecisionsView() }
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
        case .decisions: TabAccent.decisions.color
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
}

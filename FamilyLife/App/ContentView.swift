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
        if authService.isAuthenticated {
            MainTabView()
        } else {
            LoginView()
        }
    }
}

struct MainTabView: View {
    @State private var selectedTab: MainTab = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            switch selectedTab {
            case .calendar:
                NavigationStack { CalendarView() }
            case .lists:
                NavigationStack { FamilyListsView() }
            case .home:
                NavigationStack { HomeView(selectedTab: $selectedTab) }
            case .decisions:
                NavigationStack { DecisionsView() }
            case .more:
                NavigationStack { MoreView() }
            }

            VStack {
                Spacer()
                FloatingTabBar(selectedTab: $selectedTab)
            }
        }
        .ignoresSafeArea(.keyboard)
    }
}

// MARK: - Floating Glass Tab Bar

struct FloatingTabBar: View {
    @Binding var selectedTab: MainTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = tab
                    }
                } label: {
                    Image(systemName: tab.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(selectedTab == tab ? accentColor(for: tab) : WarmPalette.ink3)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .contentShape(Rectangle())
                        .background {
                            if selectedTab == tab {
                                Circle()
                                    .fill(.clear)
                                    .frame(width: 48, height: 48)
                                    .glassEffect(.regular.tint(accentColor(for: tab).opacity(0.2)), in: .circle)
                                    .shadow(color: accentColor(for: tab).opacity(0.25), radius: 8, y: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .glassEffect(.regular.tint(WarmPalette.ink1.opacity(0.08)), in: .capsule)
        .shadow(color: .white.opacity(0.6), radius: 0.5, y: -0.5)
        .shadow(color: Color(hex: "#501e0a").opacity(0.3), radius: 18, y: 8)
        .shadow(color: Color(hex: "#501e0a").opacity(0.2), radius: 5, y: 2)
        .padding(.horizontal, 16)
        .padding(.bottom, 22)
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
}

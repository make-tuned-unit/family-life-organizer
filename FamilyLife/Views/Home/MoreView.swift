import SwiftUI

struct MoreView: View {

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("More")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(WarmPalette.ink1)
                    Spacer()
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 18)

                VStack(spacing: 18) {
                    // FAMILY
                    section("Family") {
                        NavigationLink { DecisionsView() } label: {
                            moreRow(icon: "chart.bar.fill", title: "Decisions", subtitle: "Polls and family decisions", color: TabAccent.decisions.color)
                        }
                        NavigationLink { RivalriesView() } label: {
                            moreRow(icon: "flag.2.crossed.fill", title: "Rivalries", subtitle: "Family competitions and leaderboards", color: TabAccent.rivalries.color)
                        }
                        NavigationLink { PeopleView() } label: {
                            moreRow(icon: "person.2.fill", title: "People", subtitle: "Milestones, gifts, dates & ideas", color: AccentTheme.rose.color)
                        }
                        NavigationLink { MyCoverageRequestsView() } label: {
                            moreRow(icon: "arrow.triangle.swap", title: "Coverage", subtitle: "Your requests and incoming help", color: TabAccent.care.color)
                        }
                    }

                    // HOUSEHOLD
                    section("Household") {
                        NavigationLink { CookView() } label: {
                            moreRow(icon: "fork.knife", title: "Cook", subtitle: "Recipe ideas from what's in your pantry", color: AccentTheme.terracotta.color)
                        }
                        NavigationLink { NotesView() } label: {
                            moreRow(icon: "note.text", title: "Notes", subtitle: "Private notes you can share & co-edit", color: AccentTheme.saffron.color)
                        }
                        NavigationLink { TravelHubView() } label: {
                            moreRow(icon: "airplane", title: "Travel", subtitle: "Trips, itineraries, and saved places", color: AccentTheme.ocean.color)
                        }
                    }

                    // SYSTEM
                    section("") {
                        NavigationLink { ConciergeIntroView() } label: {
                            moreRow(icon: "sparkles", title: "AI Concierge", subtitle: "Daily brief and a chat that helps", color: AccentTheme.saffron.color)
                        }
                        NavigationLink { SettingsView() } label: {
                            moreRow(icon: "gearshape.fill", title: "Settings", subtitle: "Server, notifications, and account", color: WarmPalette.ink3)
                        }
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            }
            .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
        }
        .background { AmbientBackground(style: .home) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 10) {
            if !title.isEmpty {
                WarmSectionHeader(title: title)
            }
            content()
        }
    }

    private func moreRow(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink1)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(WarmPalette.ink3)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WarmPalette.ink4)
        }
        .padding(14)
        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
    }
}

#Preview {
    NavigationStack {
        MoreView()
    }
    .environment(APIService())
    .environment(SubscriptionService())
}

import SwiftUI

struct MoreView: View {
    @Environment(APIService.self) private var api
    @State private var unreadCount = 0

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

                VStack(spacing: 10) {
                    NavigationLink { MessagesView() } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(AccentTheme.ocean.color)
                                .frame(width: 36, height: 36)
                                .background(AccentTheme.ocean.color.opacity(0.15))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Messages")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(WarmPalette.ink1)
                                Text("Private messages with family")
                                    .font(.system(size: 13))
                                    .foregroundStyle(WarmPalette.ink3)
                            }

                            Spacer()

                            if unreadCount > 0 {
                                Text("\(unreadCount)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(minWidth: 22, minHeight: 22)
                                    .background(AccentTheme.rose.color, in: Circle())
                            }

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(WarmPalette.ink4)
                        }
                        .padding(14)
                        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                    }

                    NavigationLink { ExpensesView() } label: {
                        moreRow(icon: "creditcard.fill", title: "Budget", subtitle: "Track spending, receipts, and categories", color: AccentTheme.terracotta.color)
                    }

                    NavigationLink { RivalriesView() } label: {
                        moreRow(icon: "flag.2.crossed.fill", title: "Rivalries", subtitle: "Family competitions and leaderboards", color: TabAccent.rivalries.color)
                    }

                    NavigationLink { GiftsView() } label: {
                        moreRow(icon: "gift.fill", title: "Gifts", subtitle: "Track people, occasions, and gift ideas", color: AccentTheme.rose.color)
                    }

                    NavigationLink { TripsView() } label: {
                        moreRow(icon: "car.fill", title: "Trips", subtitle: "Share departures and ETA updates", color: AccentTheme.ocean.color)
                    }

                    NavigationLink { FamilyAddressesView() } label: {
                        moreRow(icon: "mappin.and.ellipse", title: "Addresses", subtitle: "Saved family locations", color: TabAccent.home.color)
                    }

                    NavigationLink { SettingsView() } label: {
                        moreRow(icon: "gearshape.fill", title: "Settings", subtitle: "Server, notifications, and account", color: WarmPalette.ink3)
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            }
            .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
        }
        .background { AmbientBackground(style: .home) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .task { await loadUnread() }
        .onAppear { Task { await loadUnread() } }
    }

    private func loadUnread() async {
        unreadCount = (try? await api.fetchUnreadMessageCount()) ?? 0
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
}

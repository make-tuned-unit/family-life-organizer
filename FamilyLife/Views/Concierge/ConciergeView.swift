import SwiftUI

/// The AI life concierge. A read-only daily brief (Phase 1): a warm summary
/// plus an ordered list of "needs you" cards that route into the rest of the app.
struct ConciergeView: View {
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @Environment(SubscriptionService.self) private var subscription
    @Environment(ConciergeLaunch.self) private var launch
    @Binding var selectedTab: MainTab

    @State private var viewModel = ConciergeViewModel()
    @State private var showingChat = false
    @State private var showingPaywall = false
    @State private var chatPrompt: String?
    @AppStorage("cloudAIEnabled") private var cloudAIEnabled = true

    var body: some View {
        ZStack {
            AmbientBackground(style: .home)

            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sectionGap) {
                    header
                    askBar
                    content
                }
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                .padding(.top, 8)
                .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
            }
            .refreshable { await viewModel.load(api: api, force: true) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { selectedTab = .home } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink2)
                }
                .accessibilityLabel("Back to home")
            }
        }
        .sheet(isPresented: $showingChat) {
            ConciergeChatView(initialPrompt: chatPrompt)
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
        .task {
            if case .idle = viewModel.state { await viewModel.load(api: api) }
            handleLaunchRequest()
        }
        .onChange(of: launch.requestedPrompt) { handleLaunchRequest() }
    }

    // Open the chat (premium) or paywall in response to an Ask-the-butler request.
    private func handleLaunchRequest() {
        guard let prompt = launch.consume() else { return }
        guard cloudAIEnabled else { return }   // chat sends data; respect the privacy toggle
        guard subscription.isPremium else { showingPaywall = true; return }
        if showingChat {
            // A chat is already open — dismiss and re-present seeded with the new prompt.
            showingChat = false
            chatPrompt = prompt
            Task { @MainActor in showingChat = true }
        } else {
            chatPrompt = prompt
            showingChat = true
        }
    }

    private var askBar: some View {
        Button {
            if !cloudAIEnabled { return }
            if subscription.isPremium { chatPrompt = nil; showingChat = true } else { showingPaywall = true }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
                Text(cloudAIEnabled ? "Ask your concierge…" : "Chat is off (cloud AI disabled)")
                    .font(.system(size: 16))
                    .foregroundStyle(WarmPalette.ink3)
                Spacer()
                if !cloudAIEnabled {
                    Image(systemName: "cloud.slash")
                        .font(.system(size: 18))
                        .foregroundStyle(WarmPalette.ink3)
                } else if subscription.isPremium {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(accent)
                } else {
                    Label("Premium", systemImage: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(accent.opacity(0.15), in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .flCard(tint: accent, interactive: true)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(accent)
                Text("Concierge")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(WarmPalette.ink1)
            }
            Text(greeting)
                .font(.system(size: 15))
                .foregroundStyle(WarmPalette.ink3)
        }
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            loadingCard
        case let .failed(message):
            errorCard(message)
        case let .loaded(brief):
            summaryCard(brief)
            if brief.isAllClear {
                allClearCard
            } else {
                WarmSectionHeader(title: "Needs you", trailing: "\(brief.cards.count)")
                VStack(spacing: DesignTokens.Spacing.cardGap) {
                    ForEach(brief.cards) { card in
                        cardRow(card)
                    }
                }
            }
        }
    }

    private func summaryCard(_ brief: ConciergeBrief) -> some View {
        let onDevice = viewModel.onDeviceSummary
        let summaryText = onDevice ?? brief.summary
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: onDevice != nil ? "iphone" : (brief.aiEnabled ? "sparkles" : "text.alignleft"))
                    .font(.system(size: 12, weight: .semibold))
                Text(onDevice != nil ? "On-device brief" : (brief.aiEnabled ? "Your brief" : "Today at a glance"))
                    .font(.system(size: 12, weight: .semibold))
                    .textCase(.uppercase)
            }
            .foregroundStyle(accent)

            briefBody(summaryText)
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .flCard(tint: accent)
    }

    // Renders the brief as an optional preamble paragraph followed by bullet
    // rows with hanging indentation (wrapped lines align under the text, not
    // the bullet). Falls back to a plain paragraph when there are no bullets
    // (e.g. the on-device summary).
    @ViewBuilder
    private func briefBody(_ text: String) -> some View {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let preamble = lines.filter { !$0.hasPrefix("•") }
        let bullets = lines
            .filter { $0.hasPrefix("•") }
            .map { $0.dropFirst().trimmingCharacters(in: .whitespaces) }

        VStack(alignment: .leading, spacing: 10) {
            if !preamble.isEmpty {
                Text(preamble.joined(separator: " "))
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(WarmPalette.ink1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !bullets.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(accent)
                            Text(bullet)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(WarmPalette.ink1)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    private func cardRow(_ card: ConciergeCard) -> some View {
        Button {
            selectedTab = card.destinationTab
        } label: {
            HStack(spacing: 14) {
                Image(systemName: card.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint(for: card.kind))
                    .frame(width: 38, height: 38)
                    .background(tint(for: card.kind).opacity(0.15), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink1)
                        .multilineTextAlignment(.leading)
                    Text(card.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(WarmPalette.ink3)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink3.opacity(0.6))
            }
            .padding(DesignTokens.Spacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .flCard(tint: tint(for: card.kind), interactive: true)
        }
        .buttonStyle(.plain)
    }

    private var allClearCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(AccentTheme.sage.color)
            Text("All caught up")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(WarmPalette.ink1)
            Text("Nothing needs your attention right now.")
                .font(.system(size: 14))
                .foregroundStyle(WarmPalette.ink3)
                .multilineTextAlignment(.center)
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .frame(maxWidth: .infinity)
        .flCard(tint: AccentTheme.sage.color)
    }

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView().tint(accent)
            Text("Gathering your day…")
                .font(.system(size: 15))
                .foregroundStyle(WarmPalette.ink3)
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .flCard(tint: accent)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Couldn't load your brief", systemImage: "exclamationmark.triangle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WarmPalette.ink1)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(WarmPalette.ink3)
            Button("Try again") { Task { await viewModel.load(api: api) } }
                .buttonStyle(FLSecondaryButtonStyle())
                .padding(.top, 4)
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .flCard(tint: AccentTheme.terracotta.color)
    }

    // MARK: - Helpers

    private var accent: Color { AccentTheme.saffron.color }

    private var greeting: String {
        let name = auth.currentUser?.name.split(separator: " ").first.map(String.init) ?? ""
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        return name.isEmpty ? part : "\(part), \(name)"
    }

    private func tint(for kind: String) -> Color {
        switch kind {
        case "task":        AccentTheme.sage.color
        case "appointment": TabAccent.calendar.color
        case "budget":      AccentTheme.terracotta.color
        case "decision":    AccentTheme.mauve.color
        case "coverage":    AccentTheme.ocean.color
        case "event":       AccentTheme.saffron.color
        case "pantry":      AccentTheme.ocean.color
        default:            AccentTheme.saffron.color
        }
    }
}

#Preview {
    @Previewable @State var tab: MainTab = .home
    return NavigationStack {
        ConciergeView(selectedTab: $tab)
            .environment(APIService())
            .environment(AuthService())
            .environment(SubscriptionService())
            .environment(ConciergeLaunch())
    }
}

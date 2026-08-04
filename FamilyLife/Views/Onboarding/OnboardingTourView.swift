import SwiftUI

/// First-run welcome tour: six swipeable pages introducing the app's shape,
/// with a deliberate spotlight on the AI Concierge — shown even when the
/// concierge toggle is off, so every household knows what it can do.
///
/// Presented from ContentView the first time an authenticated session appears
/// (`hasSeenOnboardingTour`), and replayable from Settings → About.
struct OnboardingTourView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasSeenOnboardingTour") private var hasSeenOnboardingTour = false
    @AppStorage("aiConciergeEnabled") private var aiConciergeEnabled = false
    @AppStorage("household_invite_code") private var householdInviteCode = ""

    @State private var page = 0
    private let pageCount = 6

    var body: some View {
        ZStack {
            AmbientBackground(style: .login)

            VStack(spacing: 0) {
                topBar

                TabView(selection: $page) {
                    welcomePage.tag(0)
                    calendarPage.tag(1)
                    listsPage.tag(2)
                    householdPage.tag(3)
                    conciergePage.tag(4)
                    readyPage.tag(5)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.25), value: page)

                pageDots
                    .padding(.bottom, DesignTokens.Spacing.cardGap)

                Button {
                    if page < pageCount - 1 {
                        page += 1
                    } else {
                        finish()
                    }
                } label: {
                    Text(page < pageCount - 1 ? "Next" : "Start rowing")
                }
                .buttonStyle(.flCTA)
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                .padding(.bottom, DesignTokens.Spacing.sectionGap)
            }
        }
        .preferredColorScheme(.light)
    }

    private func finish() {
        hasSeenOnboardingTour = true
        dismiss()
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Spacer()
            if page < pageCount - 1 {
                Button("Skip") { finish() }
                    .font(.flSubheadline.weight(.medium))
                    .foregroundStyle(WarmPalette.ink3)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
        .padding(.top, DesignTokens.Spacing.cardPadding)
        .frame(minHeight: 44)
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { i in
                Capsule()
                    .fill(i == page ? WarmPalette.ink1 : WarmPalette.ink4.opacity(0.5))
                    .frame(width: i == page ? 22 : 7, height: 7)
                    .animation(.spring(duration: 0.3), value: page)
            }
        }
        .accessibilityLabel("Page \(page + 1) of \(pageCount)")
    }

    // MARK: - Pages

    private var welcomePage: some View {
        tourPage(
            icon: "house.fill",
            accent: TabAccent.home.color,
            eyebrow: "Welcome to Kinrows",
            title: "One calm place for the whole household.",
            body: "The calendar, the lists, the meals, the trips, the little decisions — out of scattered group chats and into a home everyone can see."
        ) {
            featureCard([
                ("calendar", TabAccent.calendar.color, "A calendar the whole house keeps up"),
                ("list.bullet.rectangle.fill", TabAccent.home.color, "Lists that update from the store aisle"),
                ("bubble.left.and.text.bubble.right.fill", AccentTheme.ocean.color, "A family chat that isn't buried"),
            ])
        }
    }

    private var calendarPage: some View {
        tourPage(
            icon: "calendar",
            accent: TabAccent.calendar.color,
            eyebrow: "Calendar",
            title: "The week, in everyone's pocket.",
            body: "Add it once and the whole household sees it. Sync your existing Apple or Google calendars into one merged view, colored by person."
        ) {
            featureCard([
                ("person.2.fill", TabAccent.calendar.color, "Everyone's events, color-coded by person"),
                ("arrow.triangle.2.circlepath", TabAccent.home.color, "Mirrors the calendars you already use"),
                ("location.fill", AccentTheme.ocean.color, "\u{201C}Time to leave\u{201D} nudges for located events"),
            ])
        }
    }

    private var listsPage: some View {
        tourPage(
            icon: "list.bullet.rectangle.fill",
            accent: TabAccent.home.color,
            eyebrow: "Lists, meals & home",
            title: "The running of the house, shared.",
            body: "Groceries that check off in real time, a pantry that knows what's expiring, dinner ideas from what you already have, and notes for everything else."
        ) {
            featureCard([
                ("cart.fill", TabAccent.home.color, "Shared grocery and to-do lists"),
                ("cabinet.fill", AccentTheme.ocean.color, "Pantry with expiry tracking"),
                ("fork.knife", AccentTheme.terracotta.color, "Cook suggests meals from your pantry"),
            ])
        }
    }

    private var householdPage: some View {
        tourPage(
            icon: "person.2.fill",
            accent: AccentTheme.terracotta.color,
            eyebrow: "Your people",
            title: "A family does better when it rows together.",
            body: "Invite your partner with your household code. Add kids under People — no account needed. Connect grandparents through clans while daily life stays private to your household."
        ) {
            featureCard([
                ("creditcard.fill", AccentTheme.terracotta.color, "Budget, receipts & recurring payments"),
                ("airplane", AccentTheme.ocean.color, "Trips, itineraries & packing lists"),
                ("flag.2.crossed.fill", AccentTheme.rose.color, "Friendly rivalries & family milestones"),
            ])
        }
    }

    /// The Concierge spotlight. Deliberately shown to everyone — including
    /// households that keep the concierge switched off — so they know what
    /// the assistant can do before deciding.
    private var conciergePage: some View {
        tourPage(
            icon: "sparkles",
            accent: AccentTheme.saffron.color,
            eyebrow: "Meet the Concierge",
            title: "An assistant for the invisible work.",
            body: "It knows your family's calendar, lists, budget and birthdays — briefs you each morning, does the doing when you ask, and nudges before things slip."
        ) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.inset) {
                conciergeBubble("Add swim practice every Tuesday at 4", fromUser: true)
                conciergeBubble("What should we make for dinner tonight?", fromUser: true)
                conciergeBubble("Done — and taco night works: you have everything but cilantro. Added it to Groceries.", fromUser: false)

                if aiConciergeEnabled {
                    Label("Concierge is on — look for the \u{2728} launcher.", systemImage: "checkmark.seal.fill")
                        .font(.flFootnote.weight(.semibold))
                        .foregroundStyle(WarmPalette.good)
                        .padding(.top, DesignTokens.Spacing.tinyLabel)
                } else {
                    Button {
                        aiConciergeEnabled = true
                    } label: {
                        Label("Turn it on now", systemImage: "sparkles")
                            .font(.flSubheadline.weight(.semibold))
                            .foregroundStyle(AccentTheme.saffron.color)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DesignTokens.Spacing.inset)
                            .background(
                                AccentTheme.saffron.color.opacity(DesignTokens.Opacity.interactiveTint),
                                in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small)
                            )
                    }
                    .buttonStyle(.flCardPress)
                    .padding(.top, DesignTokens.Spacing.tinyLabel)

                    Text("Off by default — nothing runs until you say so. The daily brief is free; you can change your mind any time under More → AI Concierge.")
                        .font(.flCaption)
                        .foregroundStyle(WarmPalette.ink3)
                }
            }
            .padding(DesignTokens.Spacing.cardPadding)
            .flCard(tint: AccentTheme.saffron.color)
        }
    }

    private var readyPage: some View {
        tourPage(
            icon: "figure.2.and.child.holdinghands",
            accent: TabAccent.home.color,
            eyebrow: "You're ready",
            title: "Start with the week you're in.",
            body: "Put tonight on the calendar, start a grocery list, say hello in the feed. Kinrows really begins when your people join you."
        ) {
            if !householdInviteCode.isEmpty {
                VStack(spacing: DesignTokens.Spacing.tinyLabel) {
                    Text("Your household invite code")
                        .font(.flOverline)
                        .tracking(0.4)
                        .textCase(.uppercase)
                        .foregroundStyle(WarmPalette.ink3)
                    // Monospaced invite codes are an allowed typography exemption.
                    Text(householdInviteCode)
                        .font(.system(.title2, design: .monospaced).weight(.bold))
                        .foregroundStyle(WarmPalette.ink1)
                    Text("Share it from More → Household")
                        .font(.flCaption)
                        .foregroundStyle(WarmPalette.ink3)
                }
                .frame(maxWidth: .infinity)
                .padding(DesignTokens.Spacing.cardPadding)
                .flCard(tint: AccentTheme.saffron.color)
            } else {
                featureCard([
                    ("person.badge.plus", AccentTheme.terracotta.color, "Invite your partner from More → Household"),
                    ("sparkles", AccentTheme.saffron.color, "Replay this tour any time in Settings"),
                ])
            }
        }
    }

    // MARK: - Building blocks

    private func tourPage(
        icon: String,
        accent: Color,
        eyebrow: String,
        title: String,
        body: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: DesignTokens.Spacing.sectionGap) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(DesignTokens.Opacity.interactiveTint))
                        .frame(width: 84, height: 84)
                    Image(systemName: icon)
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .padding(.top, DesignTokens.Spacing.sectionGap)

                VStack(spacing: DesignTokens.Spacing.rowVertical) {
                    Text(eyebrow)
                        .font(.flOverline)
                        .tracking(0.4)
                        .textCase(.uppercase)
                        .foregroundStyle(accent)
                    Text(title)
                        .font(.flTitle)
                        .foregroundStyle(WarmPalette.ink1)
                        .multilineTextAlignment(.center)
                    Text(body)
                        .font(.flBody)
                        .foregroundStyle(WarmPalette.ink2)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                content()
            }
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.bottom, DesignTokens.Spacing.sectionGap)
            .frame(maxWidth: .infinity)
        }
    }

    private func featureCard(_ rows: [(icon: String, tint: Color, text: String)]) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.cardGap) {
            ForEach(rows, id: \.text) { row in
                HStack(spacing: DesignTokens.Spacing.chipPadding) {
                    Image(systemName: row.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(row.tint)
                        .frame(width: 30)
                    Text(row.text)
                        .font(.flSubheadline)
                        .foregroundStyle(WarmPalette.ink1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .flCard()
    }

    private func conciergeBubble(_ text: String, fromUser: Bool) -> some View {
        HStack {
            if fromUser { Spacer(minLength: DesignTokens.Spacing.large) }
            Text(text)
                .font(.flSubheadline)
                .foregroundStyle(fromUser ? WarmPalette.cream1 : WarmPalette.ink1)
                .padding(.horizontal, DesignTokens.Spacing.chipPadding)
                .padding(.vertical, DesignTokens.Spacing.rowVertical)
                .background(
                    fromUser ? WarmPalette.ink1 : WarmPalette.cream2,
                    in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.tile)
                )
            if !fromUser { Spacer(minLength: DesignTokens.Spacing.large) }
        }
    }
}

#Preview {
    OnboardingTourView()
}

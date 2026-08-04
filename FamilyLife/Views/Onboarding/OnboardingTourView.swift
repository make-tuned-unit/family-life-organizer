import SwiftUI

/// First-run welcome tour: five swipeable pages introducing the app's shape,
/// with a deliberate spotlight on the AI Concierge — shown even when the
/// concierge toggle is off, so every household knows what it can do.
///
/// Presented from ContentView the first time an authenticated session appears
/// (`hasSeenOnboardingTour`), and replayable from Settings → About.
///
/// Design notes: lives on the warm cream `.home` ambient (NOT `.login`, which
/// is the app's one dark backdrop and swallows ink text). Titles/body are
/// ink1/ink2 on cream for WCAG AA contrast; accents mark icons and eyebrows
/// only. Five pages max, benefit-led copy, skip always available.
struct OnboardingTourView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasSeenOnboardingTour") private var hasSeenOnboardingTour = false
    @AppStorage("aiConciergeEnabled") private var aiConciergeEnabled = false
    @AppStorage("household_invite_code") private var householdInviteCode = ""

    @State private var page = 0
    private let pageCount = 5

    init() {
        #if DEBUG
        // Screenshot harness: jump straight to a tour page (0-4).
        if let v = ProcessInfo.processInfo.environment["UITEST_TOUR_PAGE"], let n = Int(v) {
            _page = State(initialValue: min(max(n, 0), 4))
        }
        #endif
    }

    var body: some View {
        ZStack {
            AmbientBackground(style: .home)

            VStack(spacing: 0) {
                topBar

                TabView(selection: $page) {
                    welcomePage.tag(0)
                    weekPage.tag(1)
                    peoplePage.tag(2)
                    conciergePage.tag(3)
                    readyPage.tag(4)
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
                    .foregroundStyle(WarmPalette.ink2)
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
                    .fill(i == page ? WarmPalette.ink1 : WarmPalette.ink4)
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
            accent: AccentTheme.sage.color,
            eyebrow: "Welcome to Kinrows",
            title: "One calm place for the whole household.",
            body: "The calendar, the lists, the meals, the trips — out of scattered group chats and into a home everyone can see."
        ) {
            featureCard([
                ("calendar", TabAccent.calendar.color, "A calendar the whole house keeps up"),
                ("list.bullet.rectangle.fill", AccentTheme.sage.color, "Lists that update from the store aisle"),
                ("bubble.left.and.text.bubble.right.fill", AccentTheme.ocean.color, "A family chat that isn't buried"),
            ])
        }
    }

    private var weekPage: some View {
        tourPage(
            icon: "calendar",
            accent: TabAccent.calendar.color,
            eyebrow: "Your week, sorted",
            title: "Add it once. Everyone knows.",
            body: "Events, groceries and dinner plans land in everyone's pocket the moment you add them — and your existing Apple or Google calendars merge right in."
        ) {
            featureCard([
                ("person.2.fill", TabAccent.calendar.color, "One merged calendar, colored by person"),
                ("cart.fill", AccentTheme.sage.color, "Grocery lists that check off in real time"),
                ("fork.knife", AccentTheme.terracotta.color, "Dinner ideas from what's in your pantry"),
                ("creditcard.fill", AccentTheme.terracotta.color, "Budget, trips and more as you need them"),
            ])
        }
    }

    private var peoplePage: some View {
        tourPage(
            icon: "person.2.fill",
            accent: AccentTheme.terracotta.color,
            eyebrow: "Your people",
            title: "A family does better when it rows together.",
            body: "Kinrows really begins when your people join — the calendar fills itself in and the mental load finally gets shared."
        ) {
            featureCard([
                ("person.badge.plus", AccentTheme.terracotta.color, "Your partner joins with one invite code"),
                ("figure.and.child.holdinghands", AccentTheme.sage.color, "Kids join People — no phone needed"),
                ("house.and.flag.fill", AccentTheme.mauve.color, "Clans link grandparents & cousins, privately"),
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
                        // Dark ink on saffron clears WCAG AA (~7:1); cream text on
                        // saffron would not (~2:1).
                        Label("Turn it on now", systemImage: "sparkles")
                            .font(.flSubheadline.weight(.semibold))
                            .foregroundStyle(WarmPalette.ink1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DesignTokens.Spacing.inset)
                            .background(
                                AccentTheme.saffron.color,
                                in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small)
                            )
                    }
                    .buttonStyle(.flCardPress)
                    .padding(.top, DesignTokens.Spacing.tinyLabel)

                    Text("Off by default — nothing runs until you say so. The daily brief is free; change your mind any time under More → AI Concierge.")
                        .font(.flCaption)
                        .foregroundStyle(WarmPalette.ink2)
                }
            }
            .padding(DesignTokens.Spacing.cardPadding)
            .flCard(tint: AccentTheme.saffron.color)
        }
    }

    private var readyPage: some View {
        tourPage(
            icon: "figure.2.and.child.holdinghands",
            accent: AccentTheme.sage.color,
            eyebrow: "You're ready",
            title: "Start with the week you're in.",
            body: "Put tonight on the calendar, start a grocery list, say hello in the feed — small wins first."
        ) {
            if !householdInviteCode.isEmpty {
                VStack(spacing: DesignTokens.Spacing.tinyLabel) {
                    Text("Your household invite code")
                        .font(.flOverline)
                        .tracking(0.4)
                        .textCase(.uppercase)
                        .foregroundStyle(WarmPalette.ink2)
                    // Monospaced invite codes are an allowed typography exemption.
                    Text(householdInviteCode)
                        .font(.system(.title2, design: .monospaced).weight(.bold))
                        .foregroundStyle(WarmPalette.ink1)
                    Text("Share it from More → Household")
                        .font(.flCaption)
                        .foregroundStyle(WarmPalette.ink2)
                }
                .frame(maxWidth: .infinity)
                .padding(DesignTokens.Spacing.cardPadding)
                .flCard(tint: AccentTheme.sage.color)
            } else {
                featureCard([
                    ("person.badge.plus", AccentTheme.terracotta.color, "Invite your partner from More → Household"),
                    ("sparkles", AccentTheme.saffron.color, "Replay this tour any time in Settings"),
                ])
            }
        }
    }

    // MARK: - Building blocks

    /// Shared page scaffold: icon badge, eyebrow, title, body, custom content —
    /// vertically centered, scrolling only when it must (small screens / large
    /// Dynamic Type).
    private func tourPage(
        icon: String,
        accent: Color,
        eyebrow: String,
        title: String,
        body: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        // Materialize the builder up front — the GeometryReader closure is
        // escaping and can't capture the non-escaping parameter.
        let inner = content()
        return GeometryReader { geo in
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

                    VStack(spacing: DesignTokens.Spacing.rowVertical) {
                        Text(eyebrow)
                            .font(.flOverline)
                            .tracking(0.4)
                            .textCase(.uppercase)
                            .foregroundStyle(WarmPalette.ink2)
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

                    inner
                }
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                .padding(.vertical, DesignTokens.Spacing.sectionGap)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
        }
    }

    private func featureCard(_ rows: [(icon: String, tint: Color, text: String)]) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.cardGap) {
            ForEach(rows, id: \.text) { row in
                HStack(spacing: DesignTokens.Spacing.chipPadding) {
                    Image(systemName: row.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(row.tint)
                        .frame(width: 34, height: 34)
                        .background(row.tint.opacity(DesignTokens.Opacity.badgeFill), in: Circle())
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

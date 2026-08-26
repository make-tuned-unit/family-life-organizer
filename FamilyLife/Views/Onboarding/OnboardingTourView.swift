import SwiftUI

/// Pre-signup product story (and Settings replay). Six swipeable pages:
/// welcome, week, lists/dinner, people, Concierge, then create/join/sign-in.
///
/// Pre-auth: presented as the unauthenticated root. Skip jumps to the commit
/// page. Replay: full-screen cover from Settings; last page shows the invite.
struct OnboardingTourView: View {
    enum Mode {
        case preAuth
        case replay
    }

    var mode: Mode = .preAuth
    var onSignIn: (() -> Void)?
    var onCreateHousehold: (() -> Void)?
    var onJoinHousehold: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("aiConciergeEnabled") private var aiConciergeEnabled = false
    @AppStorage("household_invite_code") private var householdInviteCode = ""

    @State private var page = 0
    private let pageCount = 6

    init(
        mode: Mode = .preAuth,
        onSignIn: (() -> Void)? = nil,
        onCreateHousehold: (() -> Void)? = nil,
        onJoinHousehold: (() -> Void)? = nil
    ) {
        self.mode = mode
        self.onSignIn = onSignIn
        self.onCreateHousehold = onCreateHousehold
        self.onJoinHousehold = onJoinHousehold
        #if DEBUG
        if let v = ProcessInfo.processInfo.environment["UITEST_TOUR_PAGE"], let n = Int(v) {
            _page = State(initialValue: min(max(n, 0), 5))
        }
        #endif
    }

    var body: some View {
        ZStack {
            AmbientBackground(style: ambientStyle)

            VStack(spacing: 0) {
                topBar

                TabView(selection: $page) {
                    welcomePage.tag(0)
                    weekPage.tag(1)
                    listsPage.tag(2)
                    peoplePage.tag(3)
                    conciergePage.tag(4)
                    readyPage.tag(5)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: page)

                pageDots
                    .padding(.bottom, DesignTokens.Spacing.cardGap)

                bottomChrome
                    .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                    .padding(.bottom, DesignTokens.Spacing.sectionGap)
            }
        }
        .preferredColorScheme(.light)
    }

    private var ambientStyle: AmbientBackground.AmbientStyle {
        switch page {
        case 1: .calendar
        case 2: .pantry
        default: .home
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            if mode == .preAuth {
                Button("Sign in") { finishPreAuth { onSignIn?() } }
                    .font(.flSubheadline.weight(.medium))
                    .foregroundStyle(WarmPalette.ink2)
                    .opacity(page == 0 ? 1 : 0)
                    .allowsHitTesting(page == 0)
            } else {
                Color.clear.frame(width: 1, height: 1)
            }
            Spacer()
            if page < pageCount - 1 {
                Button("Skip") { page = pageCount - 1 }
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
                    .animation(reduceMotion ? nil : .spring(duration: 0.3), value: page)
            }
        }
        .accessibilityLabel("Page \(page + 1) of \(pageCount)")
    }

    @ViewBuilder
    private var bottomChrome: some View {
        if page < pageCount - 1 {
            Button { page += 1 } label: { Text("Next") }
                .buttonStyle(.flCTA)
                .accessibilityHint("Goes to the next page")
        } else if mode == .preAuth {
            VStack(spacing: DesignTokens.Spacing.cardGap) {
                Button { finishPreAuth { onCreateHousehold?() } } label: {
                    Text("Create household")
                }
                .buttonStyle(.flCTA(fill: AccentTheme.sage.color))

                Button { finishPreAuth { onJoinHousehold?() } } label: {
                    Text("I have an invite code")
                        .font(.flSubheadline.weight(.semibold))
                        .foregroundStyle(WarmPalette.ink1)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .background(
                            WarmPalette.cardSurface,
                            in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                                .stroke(WarmPalette.ink4.opacity(0.5), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button { finishPreAuth { onSignIn?() } } label: {
                    Text("Sign in")
                        .font(.flSubheadline.weight(.medium))
                        .foregroundStyle(WarmPalette.ink2)
                }

                Text("Free · Private to your family · No ads")
                    .font(.flCaption)
                    .foregroundStyle(WarmPalette.ink3)
                    .multilineTextAlignment(.center)
            }
        } else {
            Button { dismiss() } label: { Text("Start rowing") }
                .buttonStyle(.flCTA)
        }
    }

    private func finishPreAuth(_ action: () -> Void) {
        action()
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
            VStack(spacing: DesignTokens.Spacing.cardGap) {
                OnboardingAvatarCluster()
                OnboardingChipRow(items: [
                    ("calendar", TabAccent.calendar.color, "Calendar"),
                    ("list.bullet.rectangle.fill", AccentTheme.sage.color, "Lists"),
                    ("bubble.left.and.text.bubble.right.fill", AccentTheme.ocean.color, "Family chat"),
                ])
            }
        }
    }

    private var weekPage: some View {
        tourPage(
            icon: "calendar",
            accent: TabAccent.calendar.color,
            eyebrow: "Your week, sorted",
            title: "Add it once. Everyone knows.",
            body: "Events land in everyone's pocket the moment you add them — and the calendars you already keep merge right in."
        ) {
            OnboardingWeekRail()
        }
    }

    private var listsPage: some View {
        tourPage(
            icon: "cart.fill",
            accent: AccentTheme.sage.color,
            eyebrow: "From the aisle, and the pantry",
            title: "The list in her pocket updates while you shop.",
            body: "Groceries check off in real time. Dinner ideas come from what's actually in the pantry."
        ) {
            OnboardingGroceryMock(animateCheck: page == 2)
        }
    }

    private var peoplePage: some View {
        tourPage(
            icon: "person.2.fill",
            accent: AccentTheme.terracotta.color,
            eyebrow: "Your people",
            title: "A family does better when it rows together.",
            body: "The mental load gets shared the moment your people join — a partner with a code, kids without a phone."
        ) {
            OnboardingPeopleMock()
        }
    }

    private var conciergePage: some View {
        tourPage(
            icon: "sparkles",
            accent: AccentTheme.saffron.color,
            eyebrow: "Meet the Concierge",
            title: "An assistant for the invisible work.",
            body: "It knows the calendar, lists and birthdays — briefs you each morning, and does the doing when you ask. Off until you say so."
        ) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.inset) {
                OnboardingConciergeMock()
                if mode == .replay {
                    if aiConciergeEnabled {
                        Label("Concierge is on — look for the \u{2728} launcher.", systemImage: "checkmark.seal.fill")
                            .font(.flFootnote.weight(.semibold))
                            .foregroundStyle(WarmPalette.good)
                    } else {
                        Button { aiConciergeEnabled = true } label: {
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
                    }
                }
            }
        }
    }

    private var readyPage: some View {
        tourPage(
            icon: "figure.2.and.child.holdinghands",
            accent: AccentTheme.sage.color,
            eyebrow: mode == .preAuth ? "You're ready" : "You're ready",
            title: "Start with the week you're in.",
            body: mode == .preAuth
                ? "Your household lives here — not on this phone. Create one so your partner can join with a code."
                : "Put tonight on the calendar, start a grocery list, say hello in the feed — small wins first."
        ) {
            if mode == .replay, !householdInviteCode.isEmpty {
                VStack(spacing: DesignTokens.Spacing.tinyLabel) {
                    Text("Your household invite code")
                        .font(.flOverline)
                        .tracking(0.4)
                        .textCase(.uppercase)
                        .foregroundStyle(WarmPalette.ink2)
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
            }
        }
    }

    private func tourPage(
        icon: String,
        accent: Color,
        eyebrow: String,
        title: String,
        body: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
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
                    .accessibilityElement(children: .combine)

                    inner
                }
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                .padding(.vertical, DesignTokens.Spacing.sectionGap)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
        }
    }
}

#Preview("Pre-auth") {
    OnboardingTourView(mode: .preAuth)
}

#Preview("Replay") {
    OnboardingTourView(mode: .replay)
}

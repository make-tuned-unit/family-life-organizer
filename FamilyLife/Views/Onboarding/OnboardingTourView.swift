import SwiftUI

/// Pre-signup product story (and Settings replay), told in the five brand
/// beats from the Kinrows kit with Rowan heading each page:
///   01 Welcome · 02 Plan · 03 Stay in sync · 04 Make time · 05 Further together
/// The last beat is also the commit page (create / join / sign in).
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
    private let pageCount = 5

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
            _page = State(initialValue: min(max(n, 0), 4))
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
                    planPage.tag(1)
                    syncPage.tag(2)
                    timePage.tag(3)
                    togetherPage.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(reduceMotion ? nil : KinrowsBrand.Motion.standardCurve, value: page)

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
        case 2: .care
        case 3: .home
        case 4: .trips
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
                    .fill(i == page ? KinrowsBrand.evergreen : WarmPalette.ink4)
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
                .buttonStyle(.flCTA)

                Button { finishPreAuth { onJoinHousehold?() } } label: {
                    Text("I have an invite code")
                        .font(.flSubheadline.weight(.semibold))
                        .foregroundStyle(KinrowsBrand.evergreen)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .background(
                            WarmPalette.cardSurface,
                            in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                                .stroke(KinrowsBrand.sage.opacity(0.7), lineWidth: 1)
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

    // MARK: - Pages (the five kit beats)

    /// 01 — Welcome. Rowan waves; the illustrated crew lockup sits above.
    private var welcomePage: some View {
        tourPage(
            hero: .motion(.wave),
            eyebrow: "Welcome",
            title: "A calmer home together.",
            body: "The calendar, the lists, the meals, the trips — out of scattered group chats and into one home everyone can see.",
            isActive: page == 0
        ) {
            VStack(spacing: DesignTokens.Spacing.cardGap) {
                KinrowsIllustration(.logo(.lockup), accessibility: .label("Kinrows"), maxWidth: 200)
                    .padding(.bottom, DesignTokens.Spacing.tinyLabel)
                OnboardingChipRow(items: [
                    (.calendar, "Calendar"),
                    (.lists, "Lists"),
                    (.family, "Family"),
                ])
            }
        }
    }

    /// 02 — Plan. Rowan checks the list; the week rail + grocery mock show it.
    private var planPage: some View {
        tourPage(
            hero: .motion(.onIt),
            eyebrow: "Plan",
            title: "Plan meals. Organize life.",
            body: "Add it once and everyone knows. Groceries check off from the aisle, and dinner comes from what's actually in the pantry.",
            isActive: page == 1
        ) {
            VStack(spacing: DesignTokens.Spacing.cardGap) {
                OnboardingWeekRail()
                OnboardingGroceryMock(animateCheck: page == 1)
            }
        }
    }

    /// 03 — Stay in sync. Rowan thinks it over; the people mock shows how.
    private var syncPage: some View {
        tourPage(
            hero: .motion(.thinking, loops: true),
            eyebrow: "Stay in sync",
            title: "Keep everyone on the same page.",
            body: "The mental load gets shared the moment your people join — a partner with a code, kids without a phone.",
            isActive: page == 2
        ) {
            OnboardingPeopleMock()
        }
    }

    /// 04 — Make time. Rowan hugs the heart; the Concierge does the invisible work.
    private var timePage: some View {
        tourPage(
            hero: .motion(.grateful),
            eyebrow: "Make time",
            title: "More time for what matters.",
            body: "Rowan, your Concierge, knows the calendar, lists and birthdays — briefs you each morning and does the doing when you ask. Off until you say so.",
            isActive: page == 3
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
                                .foregroundStyle(WarmPalette.cream1)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DesignTokens.Spacing.inset)
                                .background(
                                    KinrowsBrand.evergreen,
                                    in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small)
                                )
                        }
                        .buttonStyle(.flCardPress)
                    }
                }
            }
        }
    }

    /// 05 — Further together. The whole crew rows; this is the commit page.
    private var togetherPage: some View {
        tourPage(
            hero: .scenic,
            eyebrow: "Further together",
            title: "Kin that rows together.",
            body: mode == .preAuth
                ? "Your household lives here — not on this phone. Create one so your partner can join with a code."
                : "Put tonight on the calendar, start a grocery list, say hello in the feed — small wins first.",
            isActive: page == 4
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
            } else {
                OnboardingAvatarCluster()
            }
        }
    }

    // MARK: - Page scaffold

    private enum Hero {
        case motion(KinrowsAsset.RowanPose, loops: Bool = false)
        case scenic
    }

    private func tourPage(
        hero: Hero,
        eyebrow: String,
        title: String,
        body: String,
        isActive: Bool,
        @ViewBuilder content: () -> some View
    ) -> some View {
        let inner = content()
        return GeometryReader { geo in
            ScrollView(showsIndicators: false) {
                VStack(spacing: DesignTokens.Spacing.sectionGap) {
                    heroView(hero, isActive: isActive)

                    VStack(spacing: DesignTokens.Spacing.rowVertical) {
                        Text(eyebrow)
                            .font(.flOverline)
                            .tracking(0.4)
                            .textCase(.uppercase)
                            .foregroundStyle(AccentTheme.sage.color)
                        Text(title)
                            .font(.flDisplay)
                            .foregroundStyle(KinrowsBrand.evergreen)
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

    @ViewBuilder
    private func heroView(_ hero: Hero, isActive: Bool) -> some View {
        switch hero {
        case let .motion(pose, loops):
            RowanMotionView(pose: pose, loops: loops, isActive: isActive, maxWidth: 170, maxHeight: 170)
                .frame(height: 170)
        case .scenic:
            // Beat 05 ships as the still: generated motion kept redrawing the
            // crew's faces (rejected per the brand guide), so the card gets a
            // slow native float instead — off under Reduce Motion.
            KinrowsIllustration(.scenicRow, accessibility: .decorative)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.cardLarge, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.cardLarge, style: .continuous)
                        .stroke(KinrowsBrand.sage.opacity(0.35), lineWidth: 1)
                )
                .modifier(ScenicFloat(isActive: isActive && !reduceMotion))
                .accessibilityLabel("A family rowing a canoe together across a calm lake")
                .accessibilityAddTraits(.isImage)
        }
    }
}

/// A 6-second, 4pt vertical bob — the boat "on the water" without touching
/// the artwork. Restarts whenever the page becomes active.
private struct ScenicFloat: ViewModifier {
    var isActive: Bool
    @State private var up = false

    func body(content: Content) -> some View {
        content
            .offset(y: up ? -4 : 4)
            .animation(isActive ? .easeInOut(duration: 3).repeatForever(autoreverses: true) : .default, value: up)
            .onChange(of: isActive, initial: true) { _, active in
                up = active
            }
    }
}

#Preview("Pre-auth") {
    OnboardingTourView(mode: .preAuth)
}

#Preview("Replay") {
    OnboardingTourView(mode: .replay)
}

#Preview("Further together") {
    OnboardingTourView(mode: .preAuth)
}

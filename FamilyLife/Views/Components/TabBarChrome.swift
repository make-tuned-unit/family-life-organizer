import SwiftUI

// MARK: - Tab Bar Chrome
// The system "tab bar gets out of the way while you read" behavior, for our
// own floating bar: scrolling DOWN past a short threshold collapses the bar to
// a single-icon pill; scrolling back up — or returning to the top — restores
// it. State lives here (shared via the environment) so any scroll surface
// inside a tab can feed it without owning the animation.

@MainActor
@Observable
final class TabBarChrome {
    /// True while the bar is collapsed to its single-icon pill.
    private(set) var isMinimized = false

    /// The tab currently on screen. Inactive tabs stay mounted (hidden behind
    /// `opacity(0)`), so their scroll views can still emit geometry changes as
    /// their content loads — those must not shrink the visible bar.
    var activeTab: MainTab = .home

    /// Mirrors `accessibilityReduceMotion`; swaps the spring for a plain fade.
    var reduceMotion = false

    /// Distance scrolled since the last direction change. The bar flips state
    /// only after a deliberate swipe, never on a few points of jitter.
    private var travel: CGFloat = 0

    /// Within this far from the top the bar is always full size — it also
    /// swallows the rubber-band bounce at the top of a short list.
    private static let topThreshold: CGFloat = 24
    private static let minimizeTravel: CGFloat = 44
    private static let expandTravel: CGFloat = 28

    func expand() {
        travel = 0
        setMinimized(false)
    }

    /// Feed a scroll offset change. `tab` is the tab that owns the reporting
    /// scroll view (nil when unknown, e.g. previews).
    func scrolled(from old: CGFloat, to new: CGFloat, in tab: MainTab?) {
        guard tab == nil || tab == activeTab else { return }
        if new < Self.topThreshold {
            expand()
            return
        }
        let delta = new - old
        guard abs(delta) > 0.5 else { return }
        if (delta > 0) != (travel > 0) { travel = 0 }  // direction change
        travel += delta
        if travel > Self.minimizeTravel {
            setMinimized(true)
        } else if travel < -Self.expandTravel {
            setMinimized(false)
        }
    }

    private func setMinimized(_ value: Bool) {
        guard value != isMinimized else { return }
        travel = 0
        withAnimation(
            reduceMotion
                ? .easeInOut(duration: 0.2)
                : .spring(response: 0.32, dampingFraction: 0.85)
        ) {
            isMinimized = value
        }
    }
}

// MARK: - Tab Identity

private struct FLTabIdentityKey: EnvironmentKey {
    static let defaultValue: MainTab? = nil
}

extension EnvironmentValues {
    /// Which tab a subtree belongs to — set once per tab root by `MainTabView`.
    var flTabIdentity: MainTab? {
        get { self[FLTabIdentityKey.self] }
        set { self[FLTabIdentityKey.self] = newValue }
    }
}

// MARK: - Scroll Reporting

private struct MinimizesTabBarOnScroll: ViewModifier {
    @Environment(TabBarChrome.self) private var chrome: TabBarChrome?
    @Environment(\.flTabIdentity) private var tab

    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { old, new in
            chrome?.scrolled(from: old, to: new, in: tab)
        }
    }
}

extension View {
    /// Let this scroll view drive the floating tab bar's shrink-on-scroll.
    /// Attach to a screen's primary VERTICAL scroll container only — horizontal
    /// rails never move `contentOffset.y`, so they'd just re-expand the bar.
    /// Safe without a `TabBarChrome` in the environment (sheets, previews).
    func flMinimizesTabBar() -> some View {
        modifier(MinimizesTabBarOnScroll())
    }
}

#Preview("Tab bar shrink on scroll") {
    @Previewable @State var chrome = TabBarChrome()
    @Previewable @State var tab: MainTab = .home

    ZStack(alignment: .bottom) {
        AmbientBackground(style: .home)

        ScrollView(showsIndicators: false) {
            VStack(spacing: DesignTokens.Spacing.cardGap) {
                ForEach(0..<20, id: \.self) { i in
                    HStack {
                        Text("Row \(i + 1)")
                            .font(.flHeadline)
                            .foregroundStyle(WarmPalette.ink1)
                        Spacer()
                    }
                    .flCard()
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
        }
        .flMinimizesTabBar()

        FloatingTabBar(
            selectedTab: $tab,
            isMinimized: chrome.isMinimized,
            onExpand: { chrome.expand() }
        )
    }
    .environment(chrome)
}

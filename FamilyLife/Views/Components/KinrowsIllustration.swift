import SwiftUI

// MARK: - Kinrows brand assets
// The one component that knows where brand artwork lives. Views ask for a
// semantic key (`.mascot(.wave)`, `.logo(.wordmark)`) and never touch asset
// names directly, so the kit can be re-exported without a codebase sweep.
//
// Illustration density (brand/docs/BRAND_USAGE.md):
//   high   — onboarding, launch, milestone screens
//   medium — empty states, Concierge, family setup
//   low    — calendar grids, budget tables, list rows, forms, settings
// Rowan appears at high-emotion / high-explanation moments, never as a
// status indicator without accompanying text.

enum KinrowsAsset: Hashable {
    case logo(Logo)
    case mascot(RowanPose)
    case illustration(Illustration)
    case productIcon(ProductIcon)
    case scenicRow

    enum Logo: String {
        case primary = "BrandPrimary"        // illustrated crew + wordmark — launch/marketing/onboarding
        case lockup = "BrandLockup"          // boat mark + wordmark, horizontal
        case wordmark = "BrandWordmark"      // dense UI (min 120pt wide)
        case boatMark = "BrandBoatMark"      // dense UI (min 28pt)
        case lettermark = "BrandLettermark"
        case crew = "BrandCrew"              // the illustrated crew alone (launch screen, brand moments)
    }

    /// Rowan poses. Suggested mapping (brand/docs/CLAUDE_CODEX_HANDOFF.md):
    /// welcome → wave · planning/list creation → onIt · background work/AI →
    /// thinking · empty state/cooperation → rowing · completion → celebrating ·
    /// positive acknowledgement → grateful · neutral helper → idleSmile.
    enum RowanPose: String, CaseIterable {
        case wave = "RowanWave"
        case onIt = "RowanOnIt"
        case thinking = "RowanThinking"
        case rowing = "RowanRowing"
        case celebrating = "RowanCelebrating"
        case grateful = "RowanGrateful"
        case idleSmile = "RowanIdleSmile"
        case excited = "RowanExcited"
        case settled = "RowanSettled"
        case walking = "RowanWalking"
        case running = "RowanRunning"

        /// Bundled Higgsfield motion clip for this pose (HEVC + alpha .mov),
        /// if one was generated. Poses without a clip render the still.
        var motionClipName: String? {
            switch self {
            case .wave: "rowan-wave"
            case .onIt: "rowan-on-it"
            case .thinking: "rowan-thinking"
            case .grateful: "rowan-grateful"
            case .idleSmile: "rowan-idle"
            case .celebrating: "rowan-celebrating"
            default: nil
            }
        }
    }

    enum Illustration: String {
        case boat = "IlloBoat", oar = "IlloOar", waves = "IlloWaves", leaf = "IlloLeaf"
        case sun = "IlloSun", mountains = "IlloMountains", trees = "IlloTrees"
        case home = "IlloHome", cloud = "IlloCloud", foliage = "IlloFoliage"
    }

    /// Kit product icons (evergreen rounded strokes, 128 viewBox). Vector
    /// assets — tint-free, so they read in one colour when scaled.
    enum ProductIcon: String {
        case home = "IconHome", calendar = "IconCalendar", lists = "IconLists", budgets = "IconBudgets"
        case meals = "IconMeals", family = "IconFamily", moments = "IconMoments"
        case trips = "IconTrips", growth = "IconGrowth", settings = "IconSettings"
    }

    var imageName: String {
        switch self {
        case .logo(let l): l.rawValue
        case .mascot(let p): p.rawValue
        case .illustration(let i): i.rawValue
        case .productIcon(let i): i.rawValue
        case .scenicRow: "BrandScenicRow"
        }
    }
}

/// Aspect-fit brand artwork with a required accessibility stance: pass a
/// `label` when the picture carries meaning, or `.decorative` when the
/// adjacent text already says it (the common case for Rowan).
struct KinrowsIllustration: View {
    enum Accessibility: Equatable {
        case decorative
        case label(String)
    }

    let asset: KinrowsAsset
    var accessibility: Accessibility = .decorative
    /// Cap on the rendered width in points (height follows the aspect ratio).
    var maxWidth: CGFloat? = nil
    var maxHeight: CGFloat? = nil

    init(_ asset: KinrowsAsset, accessibility: Accessibility = .decorative, maxWidth: CGFloat? = nil, maxHeight: CGFloat? = nil) {
        self.asset = asset
        self.accessibility = accessibility
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
    }

    var body: some View {
        let image = Image(asset.imageName)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: maxWidth, maxHeight: maxHeight)

        switch accessibility {
        case .decorative:
            image.accessibilityHidden(true)
        case .label(let text):
            image
                .accessibilityLabel(text)
                .accessibilityAddTraits(.isImage)
        }
    }
}

/// Kit product icon rendered as a template so it takes the current
/// foreground colour (one-colour readability is part of the icon system).
struct KinrowsProductIcon: View {
    let icon: KinrowsAsset.ProductIcon
    var size: CGFloat = 24

    var body: some View {
        Image(icon.rawValue)
            .resizable()
            .renderingMode(.original)
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

#Preview("Logos") {
    ZStack {
        AmbientBackground(style: .home)
        VStack(spacing: 24) {
            KinrowsIllustration(.logo(.primary), accessibility: .label("Kinrows"), maxWidth: 220)
            KinrowsIllustration(.logo(.lockup), accessibility: .label("Kinrows"), maxWidth: 220)
            KinrowsIllustration(.logo(.wordmark), accessibility: .label("Kinrows"), maxWidth: 160)
            HStack(spacing: 20) {
                KinrowsIllustration(.logo(.boatMark), maxWidth: 56)
                KinrowsIllustration(.logo(.lettermark), maxWidth: 48)
            }
        }
        .padding()
    }
}

#Preview("Rowan poses") {
    ZStack {
        AmbientBackground(style: .home)
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 16) {
                ForEach(KinrowsAsset.RowanPose.allCases, id: \.self) { pose in
                    VStack(spacing: 6) {
                        KinrowsIllustration(.mascot(pose), maxWidth: 100, maxHeight: 110)
                        Text(pose.rawValue.replacingOccurrences(of: "Rowan", with: ""))
                            .font(.flCaption)
                            .foregroundStyle(WarmPalette.ink3)
                    }
                }
            }
            .padding()
        }
    }
}

#Preview("Product icons") {
    ZStack {
        AmbientBackground(style: .home)
        HStack(spacing: 18) {
            KinrowsProductIcon(icon: .home, size: 32)
            KinrowsProductIcon(icon: .calendar, size: 32)
            KinrowsProductIcon(icon: .lists, size: 32)
            KinrowsProductIcon(icon: .budgets, size: 32)
            KinrowsProductIcon(icon: .meals, size: 32)
            KinrowsProductIcon(icon: .family, size: 32)
        }
        .padding()
    }
}

import SwiftUI

// MARK: - Family Tier System

enum FamilyTier: Int, CaseIterable, Identifiable {
    case rookie = 1
    case contender
    case competitor
    case champ
    case alpha
    case legend
    case goat

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .rookie: "Rookie"
        case .contender: "Contender"
        case .competitor: "Competitor"
        case .champ: "Champ"
        case .alpha: "Alpha"
        case .legend: "Legend"
        case .goat: "G.O.A.T."
        }
    }

    var icon: String {
        switch self {
        case .rookie: "figure.walk"
        case .contender: "figure.run"
        case .competitor: "flame.fill"
        case .champ: "star.fill"
        case .alpha: "bolt.fill"
        case .legend: "crown.fill"
        case .goat: "trophy.fill"
        }
    }

    var minXP: Int {
        switch self {
        case .rookie: 0
        case .contender: 100
        case .competitor: 300
        case .champ: 600
        case .alpha: 1000
        case .legend: 1500
        case .goat: 2500
        }
    }

    var maxXP: Int? {
        switch self {
        case .goat: nil
        default: FamilyTier(rawValue: rawValue + 1)?.minXP
        }
    }

    var color: Color {
        switch self {
        case .rookie: WarmPalette.ink3
        case .contender: AccentTheme.ocean.color
        case .competitor: AccentTheme.saffron.color
        case .champ: TabAccent.home.color
        case .alpha: AccentTheme.sage.color
        case .legend: TabAccent.decisions.color
        case .goat: AccentTheme.saffron.color
        }
    }

    static func tier(for xp: Int) -> FamilyTier {
        for tier in FamilyTier.allCases.reversed() {
            if xp >= tier.minXP { return tier }
        }
        return .rookie
    }

    static func progress(for xp: Int) -> Double {
        let tier = tier(for: xp)
        guard let max = tier.maxXP else { return 1.0 }
        let range = max - tier.minXP
        guard range > 0 else { return 1.0 }
        return Double(xp - tier.minXP) / Double(range)
    }

    static func xpToNextLevel(for xp: Int) -> Int? {
        let tier = tier(for: xp)
        guard let max = tier.maxXP else { return nil }
        return max - xp
    }
}

// MARK: - Level Badge

struct LevelBadge: View {
    let xp: Int
    var compact: Bool = false

    private var tier: FamilyTier { FamilyTier.tier(for: xp) }

    var body: some View {
        if compact {
            HStack(spacing: 4) {
                Image(systemName: tier.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(tier.color)
                Text(tier.name)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tier.color)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tier.color.opacity(0.12), in: Capsule())
        } else {
            VStack(spacing: 8) {
                Image(systemName: tier.icon)
                    .font(.system(size: 28))
                    .foregroundStyle(tier.color)
                Text(tier.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(tier.color)
                Text("\(xp) XP")
                    .font(.system(size: 12))
                    .foregroundStyle(WarmPalette.ink3)

                if let needed = FamilyTier.xpToNextLevel(for: xp) {
                    VStack(spacing: 4) {
                        ProgressView(value: FamilyTier.progress(for: xp))
                            .tint(tier.color)
                        Text("\(needed) XP to \(FamilyTier(rawValue: tier.rawValue + 1)?.name ?? "next")")
                            .font(.system(size: 10))
                            .foregroundStyle(WarmPalette.ink4)
                    }
                } else {
                    Text("Max level reached")
                        .font(.system(size: 10))
                        .foregroundStyle(tier.color)
                }
            }
        }
    }
}

// MARK: - Level Up Celebration

struct LevelUpCelebration: View, Identifiable {
    let tier: FamilyTier
    var id: Int { tier.rawValue }
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Text("LEVEL UP!")
                    .font(.system(size: 14, weight: .heavy))
                    .tracking(4)
                    .foregroundStyle(WarmPalette.ink3)

                Image(systemName: tier.icon)
                    .font(.system(size: 72))
                    .foregroundStyle(tier.color)
                    .shadow(color: tier.color.opacity(0.5), radius: 20)

                Text(tier.name)
                    .font(.system(size: 36, weight: .black))
                    .foregroundStyle(.white)

                Text("You've reached a new tier!")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Let's Go")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(tier.color, in: Capsule())
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        LevelBadge(xp: 0, compact: true)
        LevelBadge(xp: 350)
        LevelBadge(xp: 2500, compact: true)
    }
}

import SwiftUI

/// A full-surface confetti burst rendered with `TimelineView` + `Canvas` —
/// no third-party dependency, no persistent cost once the pieces settle.
/// Drop it in an `.overlay` and bump `trigger` for every celebration; each
/// bump fires a fresh burst from `origin` (unit coordinates).
struct ConfettiCelebration: View {
    var trigger: Int
    var origin: UnitPoint = UnitPoint(x: 0.5, y: 0.4)
    /// Pieces per burst — bump for a bigger moment (e.g. "all done").
    var intensity: Int = 42

    @State private var bursts: [Burst] = []

    private struct Burst: Identifiable {
        let id = UUID()
        let start: Date
        let seed: UInt64
        let pieces: Int
    }

    private static let lifetime: TimeInterval = 1.8
    private static let gravity: Double = 1050
    private static let colors: [Color] = [
        AccentTheme.terracotta.color,
        AccentTheme.saffron.color,
        AccentTheme.rose.color,
        AccentTheme.sage.color,
        AccentTheme.ocean.color,
        TabAccent.routines.color,
        WarmPalette.peach,
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: bursts.isEmpty)) { timeline in
            Canvas { context, size in
                let now = timeline.date
                for burst in bursts {
                    let t = now.timeIntervalSince(burst.start)
                    guard t >= 0, t <= Self.lifetime else { continue }
                    draw(burst: burst, at: t, in: context, size: size)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, newValue in
            guard newValue > 0 else { return }
            let burst = Burst(start: Date(), seed: UInt64.random(in: .min ... .max), pieces: intensity)
            bursts.append(burst)
            Task {
                try? await Task.sleep(for: .seconds(Self.lifetime + 0.2))
                bursts.removeAll { Date().timeIntervalSince($0.start) > Self.lifetime }
            }
        }
    }

    private func draw(burst: Burst, at t: TimeInterval, in context: GraphicsContext, size: CGSize) {
        var rng = SplitMix64(seed: burst.seed)
        let ox = origin.x * size.width
        let oy = origin.y * size.height
        let fade = t > Self.lifetime * 0.7
            ? max(0, 1 - (t - Self.lifetime * 0.7) / (Self.lifetime * 0.3))
            : 1
        for i in 0..<burst.pieces {
            let angle = Double.random(in: (-Double.pi * 0.9)...(-Double.pi * 0.1), using: &rng)
            let speed = Double.random(in: 260...640, using: &rng)
            let drag = Double.random(in: 0.72...0.92, using: &rng)
            let spin = Double.random(in: -9...9, using: &rng)
            let tilt = Double.random(in: 0...(2 * Double.pi), using: &rng)
            let w = CGFloat.random(in: 5...9, using: &rng)
            let h = CGFloat.random(in: 9...15, using: &rng)
            let color = Self.colors[i % Self.colors.count]

            // Simple damped ballistic arc: launch fan, then gravity wins.
            let damp = 1 - pow(1 - drag, t + 0.0001)
            let x = ox + cos(angle) * speed * t * damp
            let y = oy + sin(angle) * speed * t * damp + 0.5 * Self.gravity * t * t
            guard y < size.height + 20 else { continue }

            // A cosine on the tumble narrows the piece — reads as a 3D flip.
            let flip = abs(cos(tilt + spin * t))
            var piece = context
            piece.opacity = fade
            piece.translateBy(x: x, y: y)
            piece.rotate(by: .radians(tilt + spin * t))
            let rect = CGRect(x: -w / 2, y: -(h * flip) / 2, width: w, height: max(2, h * flip))
            piece.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(color))
        }
    }
}

/// Deterministic PRNG so a burst's pieces stay coherent frame to frame —
/// the Canvas re-derives every particle from the burst seed each frame.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

#Preview {
    struct ConfettiPreview: View {
        @State private var trigger = 0
        var body: some View {
            VStack {
                Spacer()
                Button("Celebrate") { trigger += 1 }
                    .buttonStyle(.flCTA)
                    .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { AmbientBackground(style: .home) }
            .overlay { ConfettiCelebration(trigger: trigger) }
        }
    }
    return ConfettiPreview()
}

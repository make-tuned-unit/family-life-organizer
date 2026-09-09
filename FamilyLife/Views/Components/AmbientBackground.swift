import SwiftUI

/// Warm gradient backgrounds that give Liquid Glass surfaces something to refract through.
/// Oat base with soft orbs of the Kinrows support colours (sage / river / clay / sun tints) —
/// every colour here resolves to a KinrowsBrand token or WarmPalette role.
struct AmbientBackground: View {
    var style: AmbientStyle = .home

    enum AmbientStyle {
        case home, calendar, pantry, expenses, trips, cook, rivalries, decisions, gifts, settings, login, care
    }

    var body: some View {
        Canvas { context, size in
            // Base gradient — drawn as a single rect fill
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .linearGradient(
                Gradient(stops: baseGradientStops),
                startPoint: CGPoint(x: size.width / 2, y: 0),
                endPoint: CGPoint(x: size.width / 2, y: size.height)
            ))
            // Orbs — soft radial fills, no GeometryReader needed
            drawOrb(in: &context, size: size, color: orbColor1, opacity: 0.3, radius: 0.3,
                    offsetX: -0.25, offsetY: -0.05, orbSize: 0.7)
            drawOrb(in: &context, size: size, color: orbColor2, opacity: 0.2, radius: 0.25,
                    offsetX: 0.45, offsetY: 0.25, orbSize: 0.6)
            drawOrb(in: &context, size: size, color: orbColor3, opacity: 0.18, radius: 0.28,
                    offsetX: 0.05, offsetY: 0.55, orbSize: 0.65)
        }
        .ignoresSafeArea()
    }

    private func drawOrb(in context: inout GraphicsContext, size: CGSize,
                         color: Color, opacity: Double, radius: CGFloat,
                         offsetX: CGFloat, offsetY: CGFloat, orbSize: CGFloat) {
        let w = size.width * orbSize
        let center = CGPoint(x: size.width * offsetX + w / 2, y: size.height * offsetY + w / 2)
        let ellipseRect = CGRect(x: center.x - w / 2, y: center.y - w / 2, width: w, height: w)
        context.fill(Path(ellipseIn: ellipseRect), with: .radialGradient(
            Gradient(colors: [color.opacity(opacity), color.opacity(0)]),
            center: center,
            startRadius: 0,
            endRadius: size.width * radius
        ))
    }

    private var baseGradientStops: [Gradient.Stop] {
        let colors: [Color] = switch style {
        case .home:                [WarmPalette.cream1, WarmPalette.cream2, KinrowsBrand.sage.opacity(0.18)]
        case .calendar, .cook, .care: [WarmPalette.cream1, WarmPalette.cream2.opacity(0.8)]
        case .pantry:              [WarmPalette.cream1, WarmPalette.cream2, WarmPalette.cream3.opacity(0.4)]
        case .expenses:            [WarmPalette.cream1, WarmPalette.peach.opacity(0.4), WarmPalette.sunset.opacity(0.2)]
        case .trips:               [WarmPalette.cream1, KinrowsBrand.river.opacity(0.18)]
        case .rivalries:           [WarmPalette.cream1, WarmPalette.rose.opacity(0.15)]
        case .decisions:           [WarmPalette.cream1, WarmPalette.mauve.opacity(0.12)]
        case .gifts:               [WarmPalette.cream1, WarmPalette.peach.opacity(0.3)]
        case .settings:            [WarmPalette.cream1, WarmPalette.cream2]
        case .login:               [Color(hex: "#0A2622"), KinrowsBrand.evergreen, Color(hex: "#0A2622")]
        }
        return colors.enumerated().map { i, color in
            Gradient.Stop(color: color, location: CGFloat(i) / CGFloat(max(colors.count - 1, 1)))
        }
    }

    private var orbColor1: Color {
        switch style {
        case .home:       KinrowsBrand.sage
        case .calendar:   WarmPalette.peach.opacity(0.5)
        case .pantry:     KinrowsBrand.river.opacity(0.6)
        case .expenses:   WarmPalette.sunset
        case .trips:      KinrowsBrand.river
        case .cook:       WarmPalette.peach
        case .rivalries:  WarmPalette.rose
        case .decisions:  WarmPalette.mauve
        case .gifts:      WarmPalette.peach
        case .settings:   WarmPalette.cream3
        case .login:      KinrowsBrand.sage.opacity(0.5)
        case .care:       AccentTheme.sage.soft
        }
    }

    private var orbColor2: Color {
        switch style {
        case .home:       WarmPalette.peach
        case .calendar:   WarmPalette.mauve.opacity(0.4)
        case .pantry:     KinrowsBrand.sage
        case .expenses:   WarmPalette.peach
        case .trips:      Color(hex: "#A9BFD3")
        case .cook:       WarmPalette.sunset
        case .rivalries:  WarmPalette.sunset
        case .decisions:  Color(hex: "#A9BFD3")
        case .gifts:      WarmPalette.sunset
        case .settings:   WarmPalette.cream2
        case .login:      KinrowsBrand.river.opacity(0.4)
        case .care:       AccentTheme.sage.color
        }
    }

    private var orbColor3: Color {
        switch style {
        case .home:       KinrowsBrand.river
        case .calendar:   WarmPalette.cream3
        case .pantry:     WarmPalette.peach
        case .expenses:   AccentTheme.terracotta.color
        case .trips:      WarmPalette.cream3
        case .cook:       WarmPalette.peach
        case .rivalries:  WarmPalette.peach
        case .decisions:  WarmPalette.cream3
        case .gifts:      WarmPalette.mauve
        case .settings:   WarmPalette.cream3
        case .login:      KinrowsBrand.sageDeep
        case .care:       WarmPalette.cream3
        }
    }
}

#Preview("Home") {
    AmbientBackground(style: .home)
}

#Preview("Paper") {
    AmbientBackground(style: .calendar)
}

#Preview("Photo") {
    AmbientBackground(style: .pantry)
}

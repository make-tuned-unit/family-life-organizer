import SwiftUI

/// Warm gradient backgrounds that give Liquid Glass surfaces something to refract through.
/// Inspired by the aurora/photo/paper variants from the design prototype.
struct AmbientBackground: View {
    var style: AmbientStyle = .home

    enum AmbientStyle {
        case home, calendar, pantry, expenses, trips, cook, rivalries, decisions, gifts, settings, login, care
    }

    var body: some View {
        ZStack {
            baseGradient
            GeometryReader { geo in
                orb1(geo: geo)
                orb2(geo: geo)
                orb3(geo: geo)
            }
        }
        .drawingGroup()
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var baseGradient: some View {
        switch style {
        case .home:
            // Aurora — warm peach/rose radial gradients
            ZStack {
                LinearGradient(
                    colors: [WarmPalette.cream1, WarmPalette.cream2, WarmPalette.sunset.opacity(0.3)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        case .calendar, .cook, .care:
            // Paper — cream with warm undertones
            ZStack {
                LinearGradient(
                    colors: [WarmPalette.cream1, WarmPalette.cream2.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        case .pantry:
            // Soft warm cream (matching home feel)
            ZStack {
                LinearGradient(
                    colors: [WarmPalette.cream1, WarmPalette.cream2, WarmPalette.cream3.opacity(0.4)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        case .expenses:
            // Aurora warm
            ZStack {
                LinearGradient(
                    colors: [WarmPalette.cream1, WarmPalette.peach.opacity(0.4), WarmPalette.sunset.opacity(0.2)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        case .trips:
            LinearGradient(
                colors: [WarmPalette.cream1, Color(hex: "#8eaec4").opacity(0.2)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .rivalries:
            LinearGradient(
                colors: [WarmPalette.cream1, WarmPalette.rose.opacity(0.15)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .decisions:
            LinearGradient(
                colors: [WarmPalette.cream1, WarmPalette.mauve.opacity(0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .gifts:
            LinearGradient(
                colors: [WarmPalette.cream1, WarmPalette.peach.opacity(0.3)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .settings:
            LinearGradient(
                colors: [WarmPalette.cream1, WarmPalette.cream2],
                startPoint: .top,
                endPoint: .bottom
            )
        case .login:
            LinearGradient(
                colors: [Color(hex: "#1a0f0a"), Color(hex: "#2a1810"), Color(hex: "#1a0d0a")],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func orb1(geo: GeometryProxy) -> some View {
        Ellipse()
            .fill(
                RadialGradient(colors: [orbColor1.opacity(0.3), orbColor1.opacity(0)],
                               center: .center, startRadius: 0, endRadius: geo.size.width * 0.3)
            )
            .frame(width: geo.size.width * 0.7, height: geo.size.width * 0.7)
            .offset(x: -geo.size.width * 0.25, y: -geo.size.height * 0.05)
    }

    private func orb2(geo: GeometryProxy) -> some View {
        Ellipse()
            .fill(
                RadialGradient(colors: [orbColor2.opacity(0.2), orbColor2.opacity(0)],
                               center: .center, startRadius: 0, endRadius: geo.size.width * 0.25)
            )
            .frame(width: geo.size.width * 0.6, height: geo.size.width * 0.6)
            .offset(x: geo.size.width * 0.45, y: geo.size.height * 0.25)
    }

    private func orb3(geo: GeometryProxy) -> some View {
        Ellipse()
            .fill(
                RadialGradient(colors: [orbColor3.opacity(0.18), orbColor3.opacity(0)],
                               center: .center, startRadius: 0, endRadius: geo.size.width * 0.28)
            )
            .frame(width: geo.size.width * 0.65, height: geo.size.width * 0.65)
            .offset(x: geo.size.width * 0.05, y: geo.size.height * 0.55)
    }

    private var orbColor1: Color {
        switch style {
        case .home:       WarmPalette.peach
        case .calendar:   WarmPalette.peach.opacity(0.5)
        case .pantry:     Color(hex: "#d4a574")
        case .expenses:   WarmPalette.sunset
        case .trips:      Color(hex: "#5a87a0")
        case .cook:       WarmPalette.peach
        case .rivalries:  WarmPalette.rose
        case .decisions:  WarmPalette.mauve
        case .gifts:      WarmPalette.peach
        case .settings:   WarmPalette.cream3
        case .login:      Color(hex: "#5a2e1a")
        case .care:       AccentTheme.sage.soft
        }
    }

    private var orbColor2: Color {
        switch style {
        case .home:       WarmPalette.rose
        case .calendar:   WarmPalette.mauve.opacity(0.4)
        case .pantry:     Color(hex: "#a87560")
        case .expenses:   WarmPalette.peach
        case .trips:      Color(hex: "#8eaec4")
        case .cook:       WarmPalette.sunset
        case .rivalries:  WarmPalette.sunset
        case .decisions:  Color(hex: "#b89cb4")
        case .gifts:      WarmPalette.sunset
        case .settings:   WarmPalette.cream2
        case .login:      Color(hex: "#4a2818")
        case .care:       AccentTheme.sage.color
        }
    }

    private var orbColor3: Color {
        switch style {
        case .home:       WarmPalette.mauve
        case .calendar:   WarmPalette.cream3
        case .pantry:     WarmPalette.peach
        case .expenses:   AccentTheme.terracotta.color
        case .trips:      WarmPalette.cream3
        case .cook:       WarmPalette.peach
        case .rivalries:  WarmPalette.peach
        case .decisions:  WarmPalette.cream3
        case .gifts:      WarmPalette.mauve
        case .settings:   WarmPalette.cream3
        case .login:      Color(hex: "#3a1c1a")
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

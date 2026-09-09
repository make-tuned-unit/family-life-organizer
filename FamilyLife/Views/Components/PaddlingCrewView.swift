import SwiftUI

/// The Kinrows crew paddling — built from the illustrated logo split into
/// layers (`CrewBody` + three `CrewOar*` on one canvas), so the oars swing
/// about the rowers' hands in one synchronized stroke while the boat rides
/// the water. Perfectly periodic, so it loops forever without a seam; the
/// artwork itself is untouched. Static under Reduce Motion or when paused.
struct PaddlingCrewView: View {
    /// Pauses the stroke (offscreen pages, backgrounded app).
    var isActive: Bool = true
    var maxWidth: CGFloat = 300
    var accessibility: KinrowsIllustration.Accessibility = .label("The Kinrows family paddling together")

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Layer geometry from brand/logos/dehaloed/kinrows-crew-layers.json
    private static let aspect: CGFloat = 1.7486
    private static let oars: [(name: String, pivot: UnitPoint)] = [
        ("CrewOar1", UnitPoint(x: 0.2984, y: 0.6278)),
        ("CrewOar2", UnitPoint(x: 0.4481, y: 0.5365)),
        ("CrewOar3", UnitPoint(x: 0.6481, y: 0.5506)),
    ]
    /// One full stroke.
    private static let period: Double = 2.0

    var body: some View {
        let animating = isActive && !reduceMotion
        TimelineView(.animation(paused: !animating)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = animating ? (t.truncatingRemainder(dividingBy: Self.period)) / Self.period * 2 * .pi : 0
            // Stroke: pull is quicker than the recovery, so ease the sine.
            let stroke = sin(phase)
            let oarAngle = Angle.degrees(11 * stroke)
            let boatRoll = Angle.degrees(1.2 * sin(phase - .pi / 3))
            let bob = 2.5 * sin(phase - .pi / 3)

            ZStack {
                Image("CrewBody")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                ForEach(Self.oars, id: \.name) { oar in
                    Image(oar.name)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .rotationEffect(oarAngle, anchor: oar.pivot)
                }
            }
            .aspectRatio(Self.aspect, contentMode: .fit)
            .rotationEffect(boatRoll)
            .offset(y: bob)
        }
        .frame(maxWidth: maxWidth)
        .modifier(CrewAccessibility(accessibility: accessibility))
    }
}

private struct CrewAccessibility: ViewModifier {
    let accessibility: KinrowsIllustration.Accessibility
    func body(content: Content) -> some View {
        switch accessibility {
        case .decorative:
            content.accessibilityHidden(true)
        case .label(let text):
            content.accessibilityElement(children: .ignore).accessibilityLabel(text).accessibilityAddTraits(.isImage)
        }
    }
}

#Preview("Paddling") {
    ZStack {
        AmbientBackground(style: .home)
        PaddlingCrewView(maxWidth: 300)
    }
}

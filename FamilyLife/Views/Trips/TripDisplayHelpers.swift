import Foundation

enum TripDisplayHelpers {
    static func etaText(_ minutes: Int?) -> String {
        guard let minutes else { return "ETA unavailable" }
        let clamped = max(0, minutes)
        if clamped <= 0 { return "Arriving now" }
        if clamped < 60 { return "\(clamped) min" }

        let roundedHours = max(1, Int((Double(clamped) / 60.0).rounded()))
        return "\(roundedHours) hour\(roundedHours == 1 ? "" : "s")"
    }
}

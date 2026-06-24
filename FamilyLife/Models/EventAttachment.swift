import SwiftUI

// An item (list, note, decision, receipt, trip, itinerary) linked to a calendar
// event. The backend resolves `title`/`subtitle` from the source entity so the
// client can render a preview row without a fetch per attachment.
struct EventAttachmentResponse: Codable, Identifiable {
    let id: Int
    let appointment_id: Int?
    let attachment_type: String
    let attachment_id: Int
    let title: String?
    let subtitle: String?
    let missing: Bool?
    let created_at: String?

    var kind: AttachmentKind? { AttachmentKind(rawValue: attachment_type) }
}

enum AttachmentKind: String, CaseIterable, Identifiable {
    case list, note, decision, receipt, trip, itinerary

    var id: String { rawValue }

    var label: String {
        switch self {
        case .list: "List"
        case .note: "Note"
        case .decision: "Decision"
        case .receipt: "Receipt"
        case .trip: "Trip"
        case .itinerary: "Itinerary"
        }
    }

    var icon: String {
        switch self {
        case .list: "checklist"
        case .note: "note.text"
        case .decision: "checkmark.seal"
        case .receipt: "receipt"
        case .trip: "airplane"
        case .itinerary: "map"
        }
    }

    var color: Color {
        switch self {
        case .list: AccentTheme.ocean.color
        case .note: AccentTheme.saffron.color
        case .decision: AccentTheme.mauve.color
        case .receipt: WarmPalette.good
        case .trip: TabAccent.calendar.color
        case .itinerary: AccentTheme.ocean.color
        }
    }
}

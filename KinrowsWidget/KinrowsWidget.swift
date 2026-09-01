import WidgetKit
import SwiftUI

// The Kinrows day-ahead widget: the Concierge's brief plus today's key counts,
// rendered from the App Group snapshot the app writes (WidgetDataStore) — the
// widget itself never touches the network or the keychain.

@main
struct KinrowsWidgetBundle: WidgetBundle {
    var body: some Widget {
        KinrowsDayAheadWidget()
    }
}

struct DayAheadEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetDaySnapshot?
}

struct DayAheadProvider: TimelineProvider {
    func placeholder(in context: Context) -> DayAheadEntry {
        DayAheadEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (DayAheadEntry) -> Void) {
        completion(DayAheadEntry(date: .now, snapshot: WidgetDataStore.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayAheadEntry>) -> Void) {
        // The app pushes reloads on every Home refresh; the hourly entry is
        // just a fallback so a stale morning brief doesn't sit there all day.
        let entry = DayAheadEntry(date: .now, snapshot: WidgetDataStore.load())
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct KinrowsDayAheadWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KinrowsDayAhead", provider: DayAheadProvider()) { entry in
            DayAheadWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [WarmPalette.cream1, WarmPalette.cream2],
                                   startPoint: .top, endPoint: .bottom)
                }
        }
        .configurationDisplayName("Day ahead")
        .description("Your Concierge's brief, today's chores, and what's next.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct DayAheadWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DayAheadEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .systemSmall: SmallDayAheadView(snapshot: snapshot)
            default: MediumDayAheadView(snapshot: snapshot)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AccentTheme.saffron.color)
                Text("Open Kinrows once to fill your day ahead.")
                    .font(.flCaption)
                    .foregroundStyle(WarmPalette.ink2)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

private struct SmallDayAheadView: View {
    let snapshot: WidgetDaySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AccentTheme.saffron.color)
                Text("TODAY")
                    .font(.flOverline)
                    .foregroundStyle(WarmPalette.ink3)
                    .tracking(0.4)
                Spacer(minLength: 0)
            }
            Text(snapshot.briefBody ?? "All quiet — enjoy the day.")
                .font(.flCaption)
                .foregroundStyle(WarmPalette.ink1)
                .lineLimit(4)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if snapshot.choresTotal > 0 {
                    statChip(icon: "checkmark.seal.fill",
                             text: "\(snapshot.choresDone)/\(snapshot.choresTotal)",
                             color: WidgetPalette.routines)
                }
                statChip(icon: "calendar", text: "\(snapshot.eventsTodayCount)",
                         color: AccentTheme.sage.color)
            }
        }
    }
}

private struct MediumDayAheadView: View {
    let snapshot: WidgetDaySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AccentTheme.saffron.color)
                Text((snapshot.briefTitle ?? "Today's brief").uppercased())
                    .font(.flOverline)
                    .foregroundStyle(WarmPalette.ink3)
                    .tracking(0.4)
                Spacer(minLength: 0)
                Text("Kinrows")
                    .font(.flCaption2)
                    .foregroundStyle(WarmPalette.ink4)
            }
            Text(snapshot.briefBody ?? "All quiet — enjoy the day.")
                .font(.flCaption)
                .foregroundStyle(WarmPalette.ink1)
                .lineLimit(3)
                .lineSpacing(2)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                if snapshot.choresTotal > 0 {
                    statChip(icon: "checkmark.seal.fill",
                             text: "\(snapshot.choresDone) of \(snapshot.choresTotal) chores",
                             color: WidgetPalette.routines)
                }
                if let next = snapshot.nextEventTitle {
                    statChip(icon: "calendar",
                             text: snapshot.nextEventTime.map { "\($0) · \(next)" } ?? next,
                             color: AccentTheme.sage.color)
                } else {
                    statChip(icon: "calendar",
                             text: snapshot.eventsTodayCount == 0
                                ? "No events today"
                                : "\(snapshot.eventsTodayCount) events today",
                             color: AccentTheme.sage.color)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// The one accent DesignTokens exposes only through TabAccent (which is
/// compiled in too, but this keeps the glyph colors in one obvious place).
private enum WidgetPalette {
    static let routines = TabAccent.routines.color
}

private func statChip(icon: String, text: String, color: Color) -> some View {
    HStack(spacing: 4) {
        Image(systemName: icon)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
        Text(text)
            .font(.flCaption2)
            .foregroundStyle(WarmPalette.ink2)
            .lineLimit(1)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(Capsule().fill(color.opacity(0.12)))
}

extension WidgetDaySnapshot {
    static let placeholder = WidgetDaySnapshot(
        date: "2026-09-01",
        briefTitle: "Monday's brief",
        briefBody: "Dentist at 2:30 for the kids, two chores still open, and the grocery list has 5 items for tonight.",
        choresDone: 1,
        choresTotal: 3,
        eventsTodayCount: 2,
        nextEventTitle: "Dentist",
        nextEventTime: "14:30",
        updatedAt: .now
    )
}

#Preview("Medium", as: .systemMedium) {
    KinrowsDayAheadWidget()
} timeline: {
    DayAheadEntry(date: .now, snapshot: .placeholder)
}

#Preview("Small", as: .systemSmall) {
    KinrowsDayAheadWidget()
} timeline: {
    DayAheadEntry(date: .now, snapshot: .placeholder)
}

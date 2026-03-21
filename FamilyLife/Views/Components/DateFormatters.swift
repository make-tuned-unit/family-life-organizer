import Foundation

// MARK: - Cached DateFormatters
// All date formatters used in the app as static properties.
// NEVER create DateFormatter() inline in a view body, computed property,
// or function called during rendering — it allocates a new object every render.
//
// Thread safety: These are used only from the main thread (SwiftUI rendering).
// Do not call from async/background contexts without MainActor.run {}.

extension DateFormatter {
    /// "yyyy-MM-dd" — API date strings, pantry expiry dates, server round-trips
    static let isoDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Short time display, locale-aware (e.g. "3:45 PM")
    static let shortTime: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    /// Short date display, locale-aware (e.g. "3/20/26")
    static let shortDisplay: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()

    /// "MMMM yyyy" — calendar month/year header and expenses month header (e.g. "March 2026")
    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    /// Medium date display, locale-aware (e.g. "Mar 20, 2026")
    static let mediumDisplay: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    /// "HH:mm" — 24-hour time for appointment fields
    static let hourMinute: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// Long date display, locale-aware (e.g. "March 20, 2026") — calendar selected date header
    static let longDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()

    /// "EEE" — short weekday name (e.g. "Mon") — week strip headers
    static let shortWeekday: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    /// "yyyy-MM" — month parameter for API expense queries
    static let yearMonth: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f
    }()

    /// "MM-dd" — recurring event dates for birthdays/anniversaries
    static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd"
        return f
    }()

    /// "MMM d" — short month+day display (e.g. "Mar 20") — gift/event list
    static let shortMonthDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    /// "MMMM d" — long month+day display (e.g. "March 20") — gift person detail
    static let longMonthDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d"
        return f
    }()

    /// "yyyy-MM-dd HH:mm:ss" — SQLite datetime strings (trip duration)
    static let sqliteDateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    /// "yyyy-MM-dd HH:mm" — compact datetime (notifications)
    static let dateTimeMinute: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}

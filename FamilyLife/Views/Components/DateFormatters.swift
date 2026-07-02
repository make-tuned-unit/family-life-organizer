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

    /// "yyyy-MM-dd HH:mm:ss" — SQLite datetime strings (CURRENT_TIMESTAMP is
    /// UTC on the server, so parse as UTC — not device-local, which shifted
    /// every trip timestamp by the UTC offset).
    static let sqliteDateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// "yyyy-MM-dd HH:mm" — compact datetime (notifications)
    static let dateTimeMinute: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}

/// Parses every timestamp shape the backend actually emits. The old `.flexible`
/// required fractional seconds, but the server mostly sends SQLite
/// CURRENT_TIMESTAMP ("yyyy-MM-dd HH:mm:ss", UTC, no T/Z/millis) and plain
/// non-fractional ISO — so message times, feed ages, and decision expiry all
/// silently parsed to nil. Tries, in order:
///   1. fractional ISO   "2026-07-01T12:34:56.789Z"
///   2. plain ISO        "2026-07-01T12:34:56Z"
///   3. SQLite datetime  "2026-07-01 12:34:56" (UTC)
///   4. bare date        "2026-07-01" (midnight UTC)
/// `string(from:)` is unchanged (fractional ISO), so round-trips still work.
final class ServerDateFormatter: ISO8601DateFormatter, @unchecked Sendable {
    private let plainISO: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private let sqlite: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
    private let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    override init() {
        super.init()
        formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    override func date(from string: String) -> Date? {
        super.date(from: string)
            ?? plainISO.date(from: string)
            ?? sqlite.date(from: string)
            ?? dateOnly.date(from: string)
    }
}

extension ISO8601DateFormatter {
    static let flexible: ISO8601DateFormatter = ServerDateFormatter()
}

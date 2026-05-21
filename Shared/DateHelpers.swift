import Foundation

/// ISO date parsing helpers. The backend returns `rawDate` as
/// ISO 8601 with milliseconds (e.g. "2025-05-04T08:42:00.000Z"); the
/// `date` field is pre-formatted for display ("04 MAY 2025").
enum RideDate {
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterNoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// UTC-pinned formatter used for parsing the date-only fallback
    /// (where the backend already encoded the day in UTC).
    private static let utcDateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// Local-timezone formatter for `isoDay` grouping. Has to match the
    /// calendar grid that uses `Calendar.current.startOfDay`, otherwise
    /// the cell representing "today" gets a UTC-day key and today's
    /// activity (bucketed under its own UTC prefix) lands one cell
    /// later than expected.
    private static let localDateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    /// Parse a backend rawDate string into a Date (UTC).
    static func parse(_ raw: String) -> Date? {
        if let d = isoFormatter.date(from: raw) { return d }
        if let d = isoFormatterNoFractional.date(from: raw) { return d }
        // Fall back to date-only (UTC).
        return utcDateOnlyFormatter.date(from: String(raw.prefix(10)))
    }

    /// "yyyy-MM-dd" key for grouping by day, in the local timezone.
    /// Pair with `localIsoDay(parsing:)` so activities and the calendar
    /// grid agree on the same day boundaries.
    static func isoDay(_ date: Date) -> String {
        localDateOnlyFormatter.string(from: date)
    }

    /// Parse a backend rawDate string and return its local-timezone
    /// "yyyy-MM-dd" key. Use this when bucketing activities by day so
    /// the key system matches `isoDay(_:)` on the calendar grid.
    static func localIsoDay(parsing raw: String) -> String {
        if let d = parse(raw) {
            return localDateOnlyFormatter.string(from: d)
        }
        // Backend gave us garbage — fall back to the UTC prefix.
        return String(raw.prefix(10))
    }

    /// Whole calendar days from `to` to `from` (signed).
    static func daysBetween(from earlier: Date, to later: Date) -> Int {
        let comps = Calendar.current.dateComponents([.day], from: earlier, to: later)
        return comps.day ?? 0
    }
}

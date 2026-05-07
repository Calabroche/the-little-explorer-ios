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

    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// Parse a backend rawDate string into a Date (UTC).
    static func parse(_ raw: String) -> Date? {
        if let d = isoFormatter.date(from: raw) { return d }
        if let d = isoFormatterNoFractional.date(from: raw) { return d }
        // Fall back to date-only.
        return dateOnlyFormatter.date(from: String(raw.prefix(10)))
    }

    /// "yyyy-MM-dd" key for grouping by day.
    static func isoDay(_ date: Date) -> String {
        dateOnlyFormatter.string(from: date)
    }

    /// Whole calendar days from `to` to `from` (signed).
    static func daysBetween(from earlier: Date, to later: Date) -> Int {
        let comps = Calendar.current.dateComponents([.day], from: earlier, to: later)
        return comps.day ?? 0
    }
}

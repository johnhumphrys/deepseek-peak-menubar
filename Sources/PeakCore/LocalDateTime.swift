import Foundation

/// Locale-aware formatting of instants in the user's local time zone.
/// The schedule itself is always computed in UTC; these helpers exist only for
/// display, so they accept an explicit time zone instead of relying on globals.
///
/// Formats are fixed (rather than locale templates) so the UI and the CLI read
/// the same everywhere; the app is English-only.
public enum LocalDateTime {
    private static func formatter(_ format: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }

    /// "12:00 pm"
    public static func time(_ date: Date, timeZone: TimeZone) -> String {
        formatter("h:mm a", timeZone: timeZone).string(from: date).lowercased()
    }

    /// "Fri 24 Oct"
    public static func dayMonth(_ date: Date, timeZone: TimeZone) -> String {
        formatter("EEE d MMM", timeZone: timeZone).string(from: date)
    }

    /// "Fri 24 Oct 2026"
    public static func dayMonthYear(_ date: Date, timeZone: TimeZone) -> String {
        formatter("EEE d MMM yyyy", timeZone: timeZone).string(from: date)
    }

    /// "Friday"
    public static func weekday(_ date: Date, timeZone: TimeZone) -> String {
        formatter("EEEE", timeZone: timeZone).string(from: date)
    }

    /// "AEDT" / "GMT+11"
    public static func zoneAbbreviation(_ timeZone: TimeZone, at date: Date) -> String {
        timeZone.abbreviation(for: date) ?? timeZone.identifier
    }

    /// "Fri 24 Oct, 12:00 pm AEDT"
    public static func dayAndTime(_ date: Date, timeZone: TimeZone) -> String {
        "\(dayMonth(date, timeZone: timeZone)), \(time(date, timeZone: timeZone)) \(zoneAbbreviation(timeZone, at: date))"
    }

    /// "12:00 pm – 3:00 pm"
    public static func range(_ window: PeakWindow, timeZone: TimeZone) -> String {
        "\(time(window.start, timeZone: timeZone)) – \(time(window.end, timeZone: timeZone))"
    }
}

/// ISO-8601 parsing that tolerates a missing fractional-seconds component.
public enum ISOInstant {
    public static func parse(_ string: String) -> Date? {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = precise.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}

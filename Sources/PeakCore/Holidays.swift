import Foundation

/// A single Chinese public holiday date.
public struct Holiday: Hashable, Sendable, Codable {
    public let year: Int
    public let month: Int
    public let day: Int
    public let name: String

    public init(year: Int, month: Int, day: Int, name: String) {
        self.year = year
        self.month = month
        self.day = day
        self.name = name
    }

    public var key: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

/// The set of dates DeepSeek bills as off-peak because they are Chinese public
/// holidays. Weekends are handled separately by `PeakSchedule`.
public struct HolidayCalendar: Sendable {
    private let byKey: [String: String]

    public init(holidays: [Holiday]) {
        var map: [String: String] = [:]
        for holiday in holidays {
            map[holiday.key] = holiday.name
        }
        self.byKey = map
    }

    public func name(year: Int, month: Int, day: Int) -> String? {
        byKey[String(format: "%04d-%02d-%02d", year, month, day)]
    }

    public func holiday(containingUTCDate date: Date) -> Holiday? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              let name = name(year: year, month: month, day: day)
        else { return nil }
        return Holiday(year: year, month: month, day: day, name: name)
    }

    public var allDates: [String] { byKey.keys.sorted() }

    // MARK: - Loading

    /// Parses a holiday file. Each non-empty, non-comment line is
    /// `YYYY-MM-DD Name`; the name is optional and defaults to "Public holiday".
    public static func parse(_ text: String) -> [Holiday] {
        var result: [Holiday] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard let datePart = parts.first else { continue }
            let datePieces = datePart.split(separator: "-")
            guard datePieces.count == 3,
                  let year = Int(datePieces[0]),
                  let month = Int(datePieces[1]),
                  let day = Int(datePieces[2]),
                  (1...12).contains(month),
                  (1...31).contains(day)
            else { continue }

            let name = parts.count > 1 ? String(parts[1]) : "Public holiday"
            result.append(Holiday(year: year, month: month, day: day, name: name))
        }
        return result
    }

    /// Loads holidays from `~/.config/DeepSeekPeak/holidays.txt` merged over
    /// the built-in list, so the calendar can be extended without rebuilding.
    public static func loadWithOverrides(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> HolidayCalendar {
        var holidays = ChineseHolidays.builtIn
        var directory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/DeepSeekPeak", isDirectory: true)
        if let custom = environment["DEEPSEEK_PEAK_CONFIG_DIR"] {
            directory = URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        }
        let file = directory.appendingPathComponent("holidays.txt")
        if let data = try? Data(contentsOf: file),
           let text = String(data: data, encoding: .utf8) {
            let overrides = parse(text)
            var byKey = Dictionary(uniqueKeysWithValues: holidays.map { ($0.key, $0) })
            for holiday in overrides {
                byKey[holiday.key] = holiday
            }
            holidays = byKey.values.sorted { $0.key < $1.key }
        }
        return HolidayCalendar(holidays: holidays)
    }

    public static var builtIn: HolidayCalendar {
        HolidayCalendar(holidays: ChineseHolidays.builtIn)
    }
}

/// Chinese public holidays, official State Council notices.
///
/// 2026: 国办发明电〔2025〕7号 (published 2025-11-04)
/// https://www.gov.cn/zhengce/zhengceku/202511/content_7047091.htm
///
/// Only dates that fall on a weekday can affect pricing; weekends are always
/// off-peak. Note that "make-up workdays" (调休) do not turn a weekend into a
/// peak day — the pricing page says weekends are off-peak in full.
public enum ChineseHolidays {
    public static let builtIn: [Holiday] = holidays2026

    public static let holidays2026: [Holiday] = [
        // 元旦 New Year's Day — Jan 1 (Thu) to Jan 3 (Sat)
        Holiday(year: 2026, month: 1, day: 1, name: "New Year's Day"),
        Holiday(year: 2026, month: 1, day: 2, name: "New Year's Day"),
        Holiday(year: 2026, month: 1, day: 3, name: "New Year's Day"),

        // 春节 Spring Festival — Feb 15 (Sun) to Feb 23 (Mon)
        Holiday(year: 2026, month: 2, day: 15, name: "Spring Festival"),
        Holiday(year: 2026, month: 2, day: 16, name: "Spring Festival"),
        Holiday(year: 2026, month: 2, day: 17, name: "Spring Festival"),
        Holiday(year: 2026, month: 2, day: 18, name: "Spring Festival"),
        Holiday(year: 2026, month: 2, day: 19, name: "Spring Festival"),
        Holiday(year: 2026, month: 2, day: 20, name: "Spring Festival"),
        Holiday(year: 2026, month: 2, day: 21, name: "Spring Festival"),
        Holiday(year: 2026, month: 2, day: 22, name: "Spring Festival"),
        Holiday(year: 2026, month: 2, day: 23, name: "Spring Festival"),

        // 清明节 Qingming — Apr 4 (Sat) to Apr 6 (Mon)
        Holiday(year: 2026, month: 4, day: 4, name: "Qingming Festival"),
        Holiday(year: 2026, month: 4, day: 5, name: "Qingming Festival"),
        Holiday(year: 2026, month: 4, day: 6, name: "Qingming Festival"),

        // 劳动节 Labour Day — May 1 (Fri) to May 5 (Tue)
        Holiday(year: 2026, month: 5, day: 1, name: "Labour Day"),
        Holiday(year: 2026, month: 5, day: 2, name: "Labour Day"),
        Holiday(year: 2026, month: 5, day: 3, name: "Labour Day"),
        Holiday(year: 2026, month: 5, day: 4, name: "Labour Day"),
        Holiday(year: 2026, month: 5, day: 5, name: "Labour Day"),

        // 端午节 Dragon Boat Festival — Jun 19 (Fri) to Jun 21 (Sun)
        Holiday(year: 2026, month: 6, day: 19, name: "Dragon Boat Festival"),
        Holiday(year: 2026, month: 6, day: 20, name: "Dragon Boat Festival"),
        Holiday(year: 2026, month: 6, day: 21, name: "Dragon Boat Festival"),

        // 中秋节 Mid-Autumn Festival — Sep 25 (Fri) to Sep 27 (Sun)
        Holiday(year: 2026, month: 9, day: 25, name: "Mid-Autumn Festival"),
        Holiday(year: 2026, month: 9, day: 26, name: "Mid-Autumn Festival"),
        Holiday(year: 2026, month: 9, day: 27, name: "Mid-Autumn Festival"),

        // 国庆节 National Day — Oct 1 (Thu) to Oct 7 (Wed)
        Holiday(year: 2026, month: 10, day: 1, name: "National Day"),
        Holiday(year: 2026, month: 10, day: 2, name: "National Day"),
        Holiday(year: 2026, month: 10, day: 3, name: "National Day"),
        Holiday(year: 2026, month: 10, day: 4, name: "National Day"),
        Holiday(year: 2026, month: 10, day: 5, name: "National Day"),
        Holiday(year: 2026, month: 10, day: 6, name: "National Day"),
        Holiday(year: 2026, month: 10, day: 7, name: "National Day"),
    ]
}

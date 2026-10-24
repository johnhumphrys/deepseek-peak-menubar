import XCTest
@testable import PeakCore

final class PreferencesTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "DeepSeekPeakTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    func testDefaults() {
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.leadTimeMinutes, 30)
        XCTAssertEqual(preferences.leadTime, 1800)
        XCTAssertEqual(preferences.menuBarContent, .stateAndCountdown)
        XCTAssertTrue(Preferences.leadTimeChoices.contains(Preferences.defaultLeadTimeMinutes))
    }

    func testLeadTimeRoundTrip() {
        let preferences = Preferences(defaults: defaults)
        preferences.leadTimeMinutes = 60
        XCTAssertEqual(preferences.leadTimeMinutes, 60)
        XCTAssertEqual(preferences.leadTime, 3600)
        XCTAssertEqual(Preferences(defaults: defaults).leadTimeMinutes, 60)
    }

    func testLeadTimeIsClampedToOneMinute() {
        let preferences = Preferences(defaults: defaults)
        preferences.leadTimeMinutes = 0
        XCTAssertEqual(preferences.leadTimeMinutes, 1)
        preferences.leadTimeMinutes = -15
        XCTAssertEqual(preferences.leadTimeMinutes, 1)
    }

    func testMenuBarContentRoundTrip() {
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(MenuBarContent.allCases.count, 3)
        preferences.menuBarContent = .dotOnly
        XCTAssertEqual(Preferences(defaults: defaults).menuBarContent, .dotOnly)
        preferences.menuBarContent = .stateOnly
        XCTAssertEqual(Preferences(defaults: defaults).menuBarContent, .stateOnly)
    }

    func testInvalidStoredMenuBarContentFallsBackToDefault() {
        defaults.set("something-else", forKey: PreferencesKey.menuBarContent)
        XCTAssertEqual(Preferences(defaults: defaults).menuBarContent, .stateAndCountdown)
    }

    func testMenuBarContentTitlesAreDistinct() {
        let titles = MenuBarContent.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count)
    }
}

final class HolidayCalendarTests: XCTestCase {
    private let fileManager = FileManager.default

    private func temporaryConfigDirectory() throws -> URL {
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("DeepSeekPeakTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { [fileManager] in
            try? fileManager.removeItem(at: directory)
        }
        return directory
    }

    func testBuiltIn2026HolidaysCoverOfficialRanges() {
        let calendar = HolidayCalendar.builtIn
        // 元旦 Jan 1–3
        for day in 1...3 {
            XCTAssertNotNil(calendar.name(year: 2026, month: 1, day: day), "Jan \(day) missing")
        }
        // 春节 Feb 15–23
        for day in 15...23 {
            XCTAssertNotNil(calendar.name(year: 2026, month: 2, day: day), "Feb \(day) missing")
        }
        // 国庆 Oct 1–7
        for day in 1...7 {
            XCTAssertNotNil(calendar.name(year: 2026, month: 10, day: day), "Oct \(day) missing")
        }
        XCTAssertNil(calendar.name(year: 2026, month: 10, day: 8))
    }

    func testLoadWithOverridesAddsUserDates() throws {
        let directory = try temporaryConfigDirectory()
        let file = directory.appendingPathComponent("holidays.txt")
        try """
        # extra dates
        2027-01-01 New Year's Day
        2027-02-06 Spring Festival
        """.write(to: file, atomically: true, encoding: .utf8)

        let calendar = HolidayCalendar.loadWithOverrides(
            environment: ["DEEPSEEK_PEAK_CONFIG_DIR": directory.path]
        )
        XCTAssertEqual(calendar.name(year: 2027, month: 1, day: 1), "New Year's Day")
        XCTAssertEqual(calendar.name(year: 2027, month: 2, day: 6), "Spring Festival")
        // Built-ins survive the merge.
        XCTAssertEqual(calendar.name(year: 2026, month: 10, day: 1), "National Day")
    }

    func testOverrideReplacesBuiltInName() throws {
        let directory = try temporaryConfigDirectory()
        let file = directory.appendingPathComponent("holidays.txt")
        try "2026-10-01 Renamed Day".write(to: file, atomically: true, encoding: .utf8)

        let calendar = HolidayCalendar.loadWithOverrides(
            environment: ["DEEPSEEK_PEAK_CONFIG_DIR": directory.path]
        )
        XCTAssertEqual(calendar.name(year: 2026, month: 10, day: 1), "Renamed Day")
    }

    func testMissingOverrideFileKeepsBuiltIns() {
        let calendar = HolidayCalendar.loadWithOverrides(
            environment: ["DEEPSEEK_PEAK_CONFIG_DIR": "/definitely/not/here"]
        )
        XCTAssertEqual(calendar.name(year: 2026, month: 1, day: 1), "New Year's Day")
    }

    func testParseHandlesTabsAndExtraSpaces() throws {
        let holidays = HolidayCalendar.parse("2027-05-01\tLabour Day  \n  2027-05-02   Holiday  ")
        XCTAssertEqual(holidays.count, 2)
        XCTAssertEqual(holidays.first?.name, "Labour Day")
        XCTAssertEqual(holidays.last?.name, "Holiday")
        XCTAssertEqual(holidays.first?.key, "2027-05-01")
    }

    func testParseDefaultsNameAndSkipsInvalidDates() throws {
        let holidays = HolidayCalendar.parse("2027-01-31\n2027-02-30 Nope\n2027-00-01 Nope\n2027-13-01 Nope")
        XCTAssertEqual(holidays.count, 1)
        XCTAssertEqual(holidays.first?.name, "Public holiday")
        XCTAssertEqual(holidays.first?.key, "2027-01-31")
    }

    func testAllDatesAreSorted() {
        let dates = HolidayCalendar.builtIn.allDates
        XCTAssertEqual(dates, dates.sorted())
        XCTAssertTrue(dates.allSatisfy { $0.count == 10 })
    }
}

final class FormattingTests: XCTestCase {
    private let melbourne = TimeZone(identifier: "Australia/Melbourne")!

    private func instant(_ string: String) -> Date {
        ISOInstant.parse(string)!
    }

    func testISOInstantParsing() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let expected = calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 24, hour: 13, minute: 39
        ))!

        XCTAssertEqual(ISOInstant.parse("2026-10-24T13:39:00Z"), expected)
        XCTAssertEqual(ISOInstant.parse("2026-10-24T13:39:00.250Z"), expected.addingTimeInterval(0.25))
        XCTAssertNil(ISOInstant.parse("2026-10-24"))
        XCTAssertNil(ISOInstant.parse("yesterday"))
    }

    func testLongDateAndWeekday() {
        let date = instant("2026-10-23T01:00:00Z") // 12:00 AEDT Friday
        XCTAssertEqual(LocalDateTime.dayMonthYear(date, timeZone: melbourne), "Fri 23 Oct 2026")
        XCTAssertEqual(LocalDateTime.weekday(date, timeZone: melbourne), "Friday")
    }

    func testZoneAbbreviationFollowsDaylightSaving() {
        XCTAssertEqual(LocalDateTime.zoneAbbreviation(melbourne, at: instant("2026-10-23T01:00:00Z")), "AEDT")
        XCTAssertEqual(LocalDateTime.zoneAbbreviation(melbourne, at: instant("2026-04-23T01:00:00Z")), "AEST")
    }

    func testWindowRangeFormatting() {
        let window = PeakWindow(
            start: instant("2026-10-23T01:00:00Z"),
            end: instant("2026-10-23T04:00:00Z")
        )
        XCTAssertEqual(LocalDateTime.range(window, timeZone: melbourne), "12:00 pm – 3:00 pm")
        XCTAssertEqual(
            LocalDateTime.dayAndTime(window.start, timeZone: melbourne),
            "Fri 23 Oct, 12:00 pm AEDT"
        )
    }
}

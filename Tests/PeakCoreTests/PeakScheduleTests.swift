import XCTest
@testable import PeakCore

final class PeakScheduleTests: XCTestCase {
    private let melbourne = TimeZone(identifier: "Australia/Melbourne")!

    private func instant(_ string: String) -> Date {
        guard let date = ISOInstant.parse(string) else {
            fatalError("Bad test instant: \(string)")
        }
        return date
    }

    private var plainSchedule: PeakSchedule {
        // No holidays: isolates the weekday/weekend rules.
        PeakSchedule(leadTime: 30 * 60, holidays: HolidayCalendar(holidays: []))
    }

    // MARK: - Peak windows

    func testInsideFirstWindowIsPeak() {
        let now = instant("2026-10-23T02:00:00Z") // Friday
        let snapshot = plainSchedule.snapshot(at: now, timeZone: melbourne)
        XCTAssertEqual(snapshot.phase, .peak)
        XCTAssertEqual(snapshot.currentPeak?.start, instant("2026-10-23T01:00:00Z"))
        XCTAssertEqual(snapshot.currentPeak?.end, instant("2026-10-23T04:00:00Z"))
        XCTAssertEqual(snapshot.timeToChange, 2 * 3600, accuracy: 0.5)
    }

    func testExactStartCountsAsPeak() {
        let now = instant("2026-10-23T01:00:00Z")
        XCTAssertEqual(plainSchedule.snapshot(at: now).phase, .peak)
    }

    func testExactEndCountsAsOffPeak() {
        let now = instant("2026-10-23T04:00:00Z")
        let snapshot = plainSchedule.snapshot(at: now)
        XCTAssertEqual(snapshot.phase, .offPeak)
        XCTAssertEqual(snapshot.nextPeak?.start, instant("2026-10-23T06:00:00Z"))
    }

    func testMiddayGapIsOffPeakWithShortCountdown() {
        let now = instant("2026-10-23T04:30:00Z")
        let snapshot = plainSchedule.snapshot(at: now)
        XCTAssertEqual(snapshot.phase, .offPeak)
        XCTAssertEqual(snapshot.timeToChange, 1.5 * 3600, accuracy: 0.5)
        XCTAssertEqual(snapshot.nextChange, instant("2026-10-23T06:00:00Z"))
    }

    func testLastSecondOfPeak() {
        let snapshot = plainSchedule.snapshot(at: instant("2026-10-23T09:59:59Z"))
        XCTAssertEqual(snapshot.phase, .peak)
        XCTAssertEqual(snapshot.timeToChange, 1, accuracy: 0.01)
    }

    // MARK: - Weekend / next-peak search

    func testFridayMorningEndsTheWeek() {
        let now = instant("2026-10-23T10:00:00Z") // Friday, second peak just ended
        let snapshot = plainSchedule.snapshot(at: now)
        XCTAssertEqual(snapshot.phase, .offPeak)
        XCTAssertEqual(snapshot.nextPeak?.start, instant("2026-10-26T01:00:00Z")) // Monday
        XCTAssertEqual(snapshot.timeToChange, 63 * 3600, accuracy: 0.5)
    }

    func testSaturdayIsOffPeak() {
        let now = instant("2026-10-24T02:00:00Z") // Saturday, would be peak on a weekday
        let snapshot = plainSchedule.snapshot(at: now, timeZone: melbourne)
        XCTAssertEqual(snapshot.phase, .offPeak)
        XCTAssertEqual(snapshot.nextPeak?.start, instant("2026-10-26T01:00:00Z"))
        XCTAssertTrue(snapshot.offPeakNotes.contains { $0.contains("Weekend") })
    }

    func testSundayNightLooksAheadToMonday() {
        let now = instant("2026-10-25T23:30:00Z") // Sunday
        let snapshot = plainSchedule.snapshot(at: now)
        XCTAssertEqual(snapshot.phase, .offPeak) // 1.5h away, outside the 30m lead
        XCTAssertEqual(snapshot.timeToChange, 1.5 * 3600, accuracy: 0.5)
    }

    func testApproachingUsesInclusiveBoundary() {
        // Monday 01:00 UTC is the peak start; the lead time is 30 minutes.
        let exactlyThirty = plainSchedule.snapshot(at: instant("2026-10-26T00:30:00Z"))
        XCTAssertEqual(exactlyThirty.phase, .approaching)
        XCTAssertEqual(exactlyThirty.timeToChange, 1800, accuracy: 0.5)

        let justInside = plainSchedule.snapshot(at: instant("2026-10-26T00:31:00Z"))
        XCTAssertEqual(justInside.phase, .approaching)

        let justOutside = plainSchedule.snapshot(at: instant("2026-10-26T00:29:00Z"))
        XCTAssertEqual(justOutside.phase, .offPeak)

        let wellOutside = plainSchedule.snapshot(at: instant("2026-10-26T00:00:00Z"))
        XCTAssertEqual(wellOutside.phase, .offPeak)
    }

    func testCustomLeadTime() {
        let schedule = PeakSchedule(leadTime: 60 * 60, holidays: HolidayCalendar(holidays: []))
        let snapshot = schedule.snapshot(at: instant("2026-10-26T00:15:00Z"))
        XCTAssertEqual(snapshot.phase, .approaching)
        XCTAssertEqual(snapshot.leadTime, 3600)
    }

    func testPeakIsNeverApproaching() {
        let schedule = PeakSchedule(leadTime: 120 * 60, holidays: HolidayCalendar(holidays: []))
        XCTAssertEqual(schedule.snapshot(at: instant("2026-10-23T09:59:00Z")).phase, .peak)
    }

    // MARK: - Holidays

    func testNationalDayWeekIsOffPeak() {
        let schedule = PeakSchedule(leadTime: 1800, holidays: .builtIn)
        let now = instant("2026-10-01T02:00:00Z") // Thursday, but National Day
        let snapshot = schedule.snapshot(at: now, timeZone: melbourne)
        XCTAssertEqual(snapshot.phase, .offPeak)
        XCTAssertEqual(snapshot.nextPeak?.start, instant("2026-10-08T01:00:00Z"))
        XCTAssertTrue(snapshot.offPeakNotes.contains { $0.contains("National Day") })
    }

    func testMakeUpWorkdayOnSaturdayStaysOffPeak() {
        // Oct 10 2026 is a make-up workday in China, but the pricing page says
        // weekends are off-peak in full.
        let schedule = PeakSchedule(leadTime: 1800, holidays: .builtIn)
        XCTAssertEqual(schedule.snapshot(at: instant("2026-10-10T02:00:00Z")).phase, .offPeak)
    }

    func testUpcomingPeaksSkipHolidays() {
        let schedule = PeakSchedule(leadTime: 1800, holidays: .builtIn)
        let windows = schedule.upcomingPeaks(after: instant("2026-09-30T10:00:00Z"), count: 1)
        XCTAssertEqual(windows.first?.start, instant("2026-10-08T01:00:00Z"))
    }

    func testHolidayParserIgnoresCommentsAndJunk() {
        let text = """
        # Chinese public holidays
        2027-01-01 New Year's Day

        2027-02-06 Spring Festival
        not-a-date Something
        2027-13-01 Bad month
        """
        let holidays = HolidayCalendar.parse(text)
        XCTAssertEqual(holidays.count, 2)
        XCTAssertEqual(holidays.first?.key, "2027-01-01")
        XCTAssertEqual(holidays.last?.name, "Spring Festival")
    }

    func testHolidayCalendarLookup() {
        let calendar = HolidayCalendar(holidays: [
            Holiday(year: 2027, month: 1, day: 1, name: "New Year's Day"),
        ])
        XCTAssertEqual(calendar.name(year: 2027, month: 1, day: 1), "New Year's Day")
        XCTAssertNil(calendar.name(year: 2027, month: 1, day: 2))
    }

    // MARK: - Window generation

    func testWindowsNestWithoutOverlap() {
        let windows = plainSchedule.windows(around: instant("2026-10-23T12:00:00Z"), daysBack: 1, daysForward: 10)
        XCTAssertFalse(windows.isEmpty)
        for (previous, next) in zip(windows, windows.dropFirst()) {
            XCTAssertLessThanOrEqual(previous.end, next.start)
            let durations = [3 * 3600.0, 4 * 3600.0]
            XCTAssertTrue(
                durations.contains { abs(previous.duration - $0) < 0.5 },
                "Unexpected peak window duration: \(previous.duration)"
            )
        }
    }

    func testWindowsAreWeekdayOnly() {
        let windows = plainSchedule.windows(around: instant("2026-10-23T12:00:00Z"), daysBack: 0, daysForward: 10)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        for window in windows {
            let weekday = utc.component(.weekday, from: window.start)
            XCTAssertTrue((2...6).contains(weekday), "Peak window on a weekend: \(window.start)")
        }
    }

    // MARK: - Local timeline

    func testMelbourneTimelineHasTwoPeakBlocks() {
        let now = instant("2026-10-23T06:00:00Z") // 17:00 AEDT
        let timeline = plainSchedule.timeline(forLocalDayContaining: now, timeZone: melbourne)
        let peaks = timeline.segments.filter(\.isPeak)
        XCTAssertEqual(peaks.count, 2)

        XCTAssertEqual(LocalDateTime.time(peaks[0].start, timeZone: melbourne), "12:00 pm")
        XCTAssertEqual(LocalDateTime.time(peaks[0].end, timeZone: melbourne), "3:00 pm")
        XCTAssertEqual(LocalDateTime.time(peaks[1].start, timeZone: melbourne), "5:00 pm")
        XCTAssertEqual(LocalDateTime.time(peaks[1].end, timeZone: melbourne), "9:00 pm")

        XCTAssertEqual(timeline.segments.count, 5)
        XCTAssertGreaterThan(timeline.nowFraction, 0.6)
        XCTAssertLessThan(timeline.nowFraction, 0.8)
    }

    func testTimelineHandlesDSTTransitionDay() {
        // Melbourne switches to daylight saving on Sunday 4 October 2026.
        let now = instant("2026-10-04T02:00:00Z")
        let timeline = plainSchedule.timeline(forLocalDayContaining: now, timeZone: melbourne)
        XCTAssertEqual(timeline.dayEnd.timeIntervalSince(timeline.dayStart), 23 * 3600, accuracy: 0.5)
        XCTAssertEqual(timeline.segments.filter(\.isPeak).count, 0) // Sunday: no peak
    }

    func testWeekendTimelineIsAllOffPeak() {
        let now = instant("2026-10-24T02:00:00Z") // Saturday
        let timeline = plainSchedule.timeline(forLocalDayContaining: now, timeZone: melbourne)
        XCTAssertTrue(timeline.segments.allSatisfy { !$0.isPeak })
    }

    func testTimezoneDoesNotChangeTheSchedule() {
        let now = instant("2026-10-23T02:00:00Z")
        let melb = plainSchedule.snapshot(at: now, timeZone: melbourne)
        let utc = plainSchedule.snapshot(at: now, timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(melb.phase, utc.phase)
        XCTAssertEqual(melb.timeToChange, utc.timeToChange)
    }

    // MARK: - Formatting

    func testDurationFormatting() {
        XCTAssertEqual(DurationText.clock(2 * 3600 + 14 * 60 + 3), "2:14:03")
        XCTAssertEqual(DurationText.clock(14 * 60 + 3), "14:03")
        XCTAssertEqual(DurationText.clock(0), "0:00")
        XCTAssertEqual(DurationText.clock(-5), "0:00")

        XCTAssertEqual(DurationText.compact(2 * 3600 + 14 * 60), "2h 14m")
        XCTAssertEqual(DurationText.compact(9 * 60 + 5), "9m 05s")
        XCTAssertEqual(DurationText.compact(42), "42s")

        XCTAssertEqual(DurationText.short(2 * 3600 + 14 * 60), "2h 14m")
        XCTAssertEqual(DurationText.short(14 * 60 + 59), "14m")
        XCTAssertEqual(DurationText.short(59), "<1m")
        XCTAssertEqual(DurationText.short(0), "<1m")
    }

    func testLocalTimeFormatting() {
        let date = instant("2026-10-23T01:00:00Z") // 12:00 AEDT
        XCTAssertEqual(LocalDateTime.time(date, timeZone: melbourne), "12:00 pm")
        XCTAssertEqual(LocalDateTime.dayMonth(date, timeZone: melbourne), "Fri 23 Oct")
        XCTAssertEqual(LocalDateTime.zoneAbbreviation(melbourne, at: date), "AEDT")
    }
}

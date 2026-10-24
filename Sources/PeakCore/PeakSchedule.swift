import Foundation

/// The three states the menu bar can show.
public enum PeakPhase: String, Sendable, CaseIterable {
    /// Off-peak pricing. Plenty of time before the next peak window.
    case offPeak
    /// Off-peak, but the next peak window starts within the warning lead time.
    case approaching
    /// Peak pricing is active right now.
    case peak
}

/// A single peak-pricing window, in absolute time.
public struct PeakWindow: Hashable, Sendable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }

    public func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }
}

/// A snapshot of the billing state at one instant.
public struct PeakSnapshot: Sendable {
    public let now: Date
    public let phase: PeakPhase
    /// Seconds until the phase changes (until peak starts, or until peak ends).
    public let timeToChange: TimeInterval
    /// The instant at which the phase changes.
    public let nextChange: Date
    /// The peak window we are inside, when `phase == .peak`.
    public let currentPeak: PeakWindow?
    /// The next peak window that has not started yet.
    public let nextPeak: PeakWindow?
    /// Extra context for why the current day is fully off-peak, if it is.
    public let offPeakNotes: [String]
    public let leadTime: TimeInterval
}

/// DeepSeek API peak/off-peak schedule.
///
/// Official rules (https://api-docs.deepseek.com/quick_start/pricing):
/// "Peak hours are 01:00 - 04:00 and 06:00 - 10:00 UTC, Monday through Friday,
///  excluding Chinese public holidays. All other hours are off-peak, including
///  weekends and Chinese public holidays in full."
///
/// All schedule arithmetic happens in UTC, which makes it immune to DST.
/// Local time is only used for display.
public struct PeakSchedule: Sendable {
    /// Peak windows as UTC hour ranges: 01:00–04:00 and 06:00–10:00.
    public static let peakWindowsUTC: [(startHour: Int, endHour: Int)] = [(1, 4), (6, 10)]

    public let leadTime: TimeInterval
    public let holidays: HolidayCalendar
    private let utcCalendar: Calendar

    public init(
        leadTime: TimeInterval = 30 * 60,
        holidays: HolidayCalendar = .builtIn
    ) {
        self.leadTime = leadTime
        self.holidays = holidays
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        self.utcCalendar = calendar
    }

    // MARK: - Day classification

    /// True when the UTC day carries peak windows: a weekday (Mon–Fri) that is
    /// not a Chinese public holiday. Peak windows sit at 09:00–18:00 Beijing
    /// time, so the UTC date and the Beijing billing date are always the same.
    public func isPeakDay(utcDayStart: Date) -> Bool {
        let weekday = utcCalendar.component(.weekday, from: utcDayStart)
        guard weekday >= 2, weekday <= 6 else { return false }
        return holidayName(utcDayStart: utcDayStart) == nil
    }

    /// The Chinese public holiday name for the given UTC day, if any.
    public func holidayName(utcDayStart: Date) -> String? {
        let parts = utcCalendar.dateComponents([.year, .month, .day], from: utcDayStart)
        guard let year = parts.year, let month = parts.month, let day = parts.day else {
            return nil
        }
        return holidays.name(year: year, month: month, day: day)
    }

    // MARK: - Windows

    /// Generates all peak windows in a window of days around `now`.
    ///
    /// The forward range is deliberately generous: a long Spring Festival
    /// holiday plus adjacent weekends can create a gap of ten days or more.
    public func windows(
        around now: Date,
        daysBack: Int = 3,
        daysForward: Int = 21
    ) -> [PeakWindow] {
        var result: [PeakWindow] = []
        let today = utcCalendar.startOfDay(for: now)
        guard let firstDay = utcCalendar.date(byAdding: .day, value: -daysBack, to: today) else {
            return []
        }
        for offset in 0...(daysBack + daysForward) {
            guard let day = utcCalendar.date(byAdding: .day, value: offset, to: firstDay) else {
                continue
            }
            guard isPeakDay(utcDayStart: day) else { continue }
            for window in Self.peakWindowsUTC {
                guard
                    let start = utcCalendar.date(bySettingHour: window.startHour, minute: 0, second: 0, of: day),
                    let end = utcCalendar.date(bySettingHour: window.endHour, minute: 0, second: 0, of: day)
                else { continue }
                result.append(PeakWindow(start: start, end: end))
            }
        }
        return result.sorted { $0.start < $1.start }
    }

    /// The peak window containing `date`, if any.
    public func peakWindow(containing date: Date, around now: Date? = nil) -> PeakWindow? {
        windows(around: now ?? date).first { $0.contains(date) }
    }

    /// Peak windows that start strictly after `date`, in order.
    public func upcomingPeaks(after date: Date, count: Int = 3) -> [PeakWindow] {
        Array(windows(around: date).filter { $0.start > date }.prefix(count))
    }

    // MARK: - Snapshot

    public func snapshot(at now: Date, timeZone: TimeZone = .current) -> PeakSnapshot {
        let allWindows = windows(around: now)
        let current = allWindows.first { $0.contains(now) }
        let next = allWindows.first { $0.start > now }
        let notes = offPeakNotes(for: now, timeZone: timeZone, windows: allWindows)

        if let current {
            let following = allWindows.first { $0.start >= current.end }
            return PeakSnapshot(
                now: now,
                phase: .peak,
                timeToChange: current.end.timeIntervalSince(now),
                nextChange: current.end,
                currentPeak: current,
                nextPeak: following,
                offPeakNotes: notes,
                leadTime: leadTime
            )
        }

        // A peak day always provides a following window within the generated
        // range, so `next` is effectively guaranteed. Keep a sane fallback.
        guard let next else {
            return PeakSnapshot(
                now: now,
                phase: .offPeak,
                timeToChange: 0,
                nextChange: now,
                currentPeak: nil,
                nextPeak: nil,
                offPeakNotes: notes,
                leadTime: leadTime
            )
        }

        let remaining = next.start.timeIntervalSince(now)
        return PeakSnapshot(
            now: now,
            phase: remaining <= leadTime ? .approaching : .offPeak,
            timeToChange: remaining,
            nextChange: next.start,
            currentPeak: nil,
            nextPeak: next,
            offPeakNotes: notes,
            leadTime: leadTime
        )
    }

    // MARK: - Explanations

    /// Human-readable reasons why the *local* calendar day is entirely
    /// off-peak. Empty when the day contains at least one peak window.
    private func offPeakNotes(
        for now: Date,
        timeZone: TimeZone,
        windows: [PeakWindow]
    ) -> [String] {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        let dayStart = local.startOfDay(for: now)
        guard let dayEnd = local.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

        let hasPeak = windows.contains { $0.start < dayEnd && $0.end > dayStart }
        guard !hasPeak else { return [] }

        var notes: [String] = []
        let weekday = local.component(.weekday, from: now)
        if weekday == 1 || weekday == 7 {
            notes.append("Weekend")
        }
        let parts = local.dateComponents([.year, .month, .day], from: now)
        if let year = parts.year, let month = parts.month, let day = parts.day,
           let name = holidays.name(year: year, month: month, day: day) {
            notes.append("\(name) (Chinese public holiday)")
        }
        return notes
    }

    // MARK: - Local-day timeline

    public struct TimelineSegment: Sendable, Identifiable, Hashable {
        public let start: Date
        public let end: Date
        public let isPeak: Bool
        public var id: Date { start }
    }

    public struct DayTimeline: Sendable {
        public let dayStart: Date
        public let dayEnd: Date
        public let segments: [TimelineSegment]
        /// 0...1 position of "now" within the day.
        public let nowFraction: Double
    }

    /// Builds a coarse (5-minute resolution) timeline of the local calendar day
    /// containing `now`, so a popover can draw peak windows in local time.
    /// Scanning (rather than fixed offsets) keeps 23- and 25-hour DST days sane.
    public func timeline(
        forLocalDayContaining now: Date,
        timeZone: TimeZone
    ) -> DayTimeline {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone

        let dayStart = local.startOfDay(for: now)
        guard let dayEnd = local.date(byAdding: .day, value: 1, to: dayStart), dayEnd > dayStart else {
            return DayTimeline(dayStart: dayStart, dayEnd: dayStart, segments: [], nowFraction: 0)
        }

        let allWindows = windows(around: now)
        func isPeak(at date: Date) -> Bool {
            allWindows.contains { $0.contains(date) }
        }

        let step: TimeInterval = 5 * 60
        var segments: [TimelineSegment] = []
        var segmentStart = dayStart
        var segmentIsPeak = isPeak(at: dayStart.addingTimeInterval(step / 2))
        var cursor = dayStart

        while cursor < dayEnd {
            let next = min(cursor.addingTimeInterval(step), dayEnd)
            let midpoint = cursor.addingTimeInterval(next.timeIntervalSince(cursor) / 2)
            let peak = isPeak(at: midpoint)
            if peak != segmentIsPeak {
                segments.append(TimelineSegment(start: segmentStart, end: cursor, isPeak: segmentIsPeak))
                segmentStart = cursor
                segmentIsPeak = peak
            }
            cursor = next
        }
        segments.append(TimelineSegment(start: segmentStart, end: dayEnd, isPeak: segmentIsPeak))

        let total = dayEnd.timeIntervalSince(dayStart)
        let fraction = total > 0 ? now.timeIntervalSince(dayStart) / total : 0
        return DayTimeline(
            dayStart: dayStart,
            dayEnd: dayEnd,
            segments: segments,
            nowFraction: min(max(fraction, 0), 1)
        )
    }
}

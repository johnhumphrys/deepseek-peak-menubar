import Foundation
import PeakCore

/// `--dump` prints the schedule in local time so the rules can be checked
/// without looking at the menu bar (and without a GUI at all).
enum ScheduleDump {
    static let usage = """
    DeepSeek Peak — menu bar indicator for DeepSeek API peak/off-peak pricing.

    Usage:
      DeepSeekPeakBar                 Run the menu bar app
      DeepSeekPeakBar --dump [opts]   Print the upcoming schedule and exit
      DeepSeekPeakBar --help
      DeepSeekPeakBar --version

    Dump options:
      --days N        Number of days to print (default 14)
      --at ISO8601    Evaluate as if it were this instant
      --tz IDENT      Time zone for display (default: system, e.g. Australia/Melbourne)
      --lead MIN      Lead time before peak turns the indicator yellow (default 30)

    Environment (QA):
      DEEPSEEK_PEAK_FAKE_NOW        Pretend it is this instant
      DEEPSEEK_PEAK_SHOW_POPOVER=1  Open the popover on launch
    """

    static func run(arguments: [String]) -> Int32 {
        var days = 14
        var leadMinutes = Preferences.defaultLeadTimeMinutes
        var timeZone = TimeZone.current
        var reference = Date()
        var index = 1

        while index < arguments.count {
            let argument = arguments[index]
            func nextValue() -> String? {
                guard index + 1 < arguments.count else { return nil }
                index += 1
                return arguments[index]
            }
            switch argument {
            case "--days":
                if let value = nextValue(), let parsed = Int(value) {
                    days = min(max(parsed, 1), 400)
                }
            case "--lead":
                if let value = nextValue(), let parsed = Int(value) {
                    leadMinutes = max(parsed, 1)
                }
            case "--tz":
                if let value = nextValue(), let parsed = TimeZone(identifier: value) {
                    timeZone = parsed
                }
            case "--at":
                if let value = nextValue(), let parsed = ISOInstant.parse(value) {
                    reference = parsed
                }
            default:
                break
            }
            index += 1
        }

        let schedule = PeakSchedule(
            leadTime: TimeInterval(leadMinutes * 60),
            holidays: HolidayCalendar.loadWithOverrides()
        )
        let snapshot = schedule.snapshot(at: reference, timeZone: timeZone)

        let nowLine: String
        if snapshot.phase == .peak {
            nowLine = "peak · off-peak starts in \(DurationText.compact(snapshot.timeToChange))"
        } else {
            nowLine = "off-peak · peak starts in \(DurationText.compact(snapshot.timeToChange))"
        }

        let zone = LocalDateTime.zoneAbbreviation(timeZone, at: reference)
        print("DeepSeek API peak schedule")
        print("Time zone: \(timeZone.identifier) (\(zone))")
        print("Now: \(LocalDateTime.dayMonthYear(reference, timeZone: timeZone)), \(LocalDateTime.time(reference, timeZone: timeZone)) — \(nowLine)")
        print("       next change \(LocalDateTime.dayAndTime(snapshot.nextChange, timeZone: timeZone))")
        print("Lead time: \(leadMinutes)m (yellow when a peak starts within this)")
        print("Rules: peak 01:00–04:00 & 06:00–10:00 UTC, Mon–Fri; weekends and Chinese public holidays are off-peak.")
        print("")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let today = calendar.startOfDay(for: reference)
        print("Next \(days) days:")
        for offset in 0..<days {
            guard let dayStart = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let probe = dayStart.addingTimeInterval(3600)
            let timeline = schedule.timeline(forLocalDayContaining: probe, timeZone: timeZone)
            let windows = timeline.segments.filter(\.isPeak)

            let dayLabel = LocalDateTime.dayMonthYear(dayStart, timeZone: timeZone)
            let marker = offset == 0 ? "  ← today" : ""
            let windowText: String
            if windows.isEmpty {
                let notes = schedule.snapshot(at: probe, timeZone: timeZone).offPeakNotes
                windowText = notes.isEmpty
                    ? "off-peak all day"
                    : "off-peak all day — \(notes.joined(separator: " · "))"
            } else {
                windowText = windows
                    .map { LocalDateTime.range(PeakWindow(start: $0.start, end: $0.end), timeZone: timeZone) }
                    .joined(separator: ",  ")
            }
            let paddedLabel = dayLabel.padding(toLength: 17, withPad: " ", startingAt: 0)
            print("  \(paddedLabel) \(windowText)\(marker)")
        }

        return 0
    }
}

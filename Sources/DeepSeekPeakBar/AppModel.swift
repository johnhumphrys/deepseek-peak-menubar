import Foundation
import PeakCore
import ServiceManagement

/// Owns the clock, the schedule and the user's preferences, and republishes a
/// snapshot for both the menu bar item and the popover.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: PeakSnapshot
    @Published private(set) var timeline: PeakSchedule.DayTimeline
    @Published private(set) var now: Date
    @Published private(set) var launchAtLogin: Bool
    @Published var lastError: String?

    let timeZone: TimeZone

    private let preferences: Preferences
    private var schedule: PeakSchedule
    private var tickCount = 0
    /// Non-zero when `DEEPSEEK_PEAK_FAKE_NOW` is set, for screenshots/tests.
    private let clockOffset: TimeInterval

    init(preferences: Preferences = Preferences(), timeZone: TimeZone = .autoupdatingCurrent) {
        self.preferences = preferences
        self.timeZone = timeZone
        self.clockOffset = Self.previewClockOffset()

        let schedule = PeakSchedule(
            leadTime: preferences.leadTime,
            holidays: HolidayCalendar.loadWithOverrides()
        )
        self.schedule = schedule

        let wallClock = Date().addingTimeInterval(clockOffset)
        self.now = wallClock
        self.snapshot = schedule.snapshot(at: wallClock, timeZone: timeZone)
        self.timeline = schedule.timeline(forLocalDayContaining: wallClock, timeZone: timeZone)
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Clock

    func refresh() {
        let wallClock = Date().addingTimeInterval(clockOffset)
        now = wallClock
        snapshot = schedule.snapshot(at: wallClock, timeZone: timeZone)
        timeline = schedule.timeline(forLocalDayContaining: wallClock, timeZone: timeZone)

        // Querying the login-item status hits XPC; do it occasionally, not 1/s.
        tickCount += 1
        if tickCount % 15 == 1 {
            syncLaunchAtLoginStatus()
        }
    }

    func syncLaunchAtLoginStatus() {
        let enabled = SMAppService.mainApp.status == .enabled
        if enabled != launchAtLogin { launchAtLogin = enabled }
    }

    // MARK: - Preferences

    var menuBarContent: MenuBarContent { preferences.menuBarContent }
    var leadTimeMinutes: Int { preferences.leadTimeMinutes }

    func setMenuBarContent(_ content: MenuBarContent) {
        preferences.menuBarContent = content
        objectWillChange.send()
    }

    func setLeadTimeMinutes(_ minutes: Int) {
        preferences.leadTimeMinutes = minutes
        schedule = PeakSchedule(
            leadTime: preferences.leadTime,
            holidays: HolidayCalendar.loadWithOverrides()
        )
        refresh()
        objectWillChange.send()
    }

    // MARK: - Launch at login

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = error.localizedDescription
        }
        syncLaunchAtLoginStatus()
    }

    // MARK: - Display helpers

    var zoneName: String { LocalDateTime.zoneAbbreviation(timeZone, at: now) }

    var menuBarTitle: String {
        let phase = snapshot.phase
        switch menuBarContent {
        case .dotOnly:
            return ""
        case .stateOnly:
            return phase.menuBarLabel
        case .stateAndCountdown:
            return "\(phase.menuBarLabel) \(DurationText.short(snapshot.timeToChange))"
        }
    }

    var headline: String {
        snapshot.phase == .peak ? "Off-peak starts in" : "Peak starts in"
    }

    var countdownDetail: String {
        let change = LocalDateTime.time(snapshot.nextChange, timeZone: timeZone)
        let zone = LocalDateTime.zoneAbbreviation(timeZone, at: snapshot.nextChange)
        let day = LocalDateTime.dayMonth(snapshot.nextChange, timeZone: timeZone)
        return "at \(change) \(zone) · \(day)"
    }

    var upcomingPeaks: [PeakWindow] {
        schedule.upcomingPeaks(after: now, count: 2)
    }

    func windowDescription(_ window: PeakWindow) -> String {
        LocalDateTime.dayMonth(window.start, timeZone: timeZone)
    }

    // MARK: - Preview clock

    private static func previewClockOffset() -> TimeInterval {
        guard let raw = ProcessInfo.processInfo.environment["DEEPSEEK_PEAK_FAKE_NOW"],
              let target = ISOInstant.parse(raw)
        else { return 0 }
        return target.timeIntervalSinceNow
    }
}

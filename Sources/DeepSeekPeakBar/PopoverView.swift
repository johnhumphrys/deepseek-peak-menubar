import AppKit
import PeakCore
import SwiftUI

/// The popover shown when the menu bar item is clicked.
struct PopoverView: View {
    @ObservedObject var model: AppModel

    private var snapshot: PeakSnapshot { model.snapshot }
    private var accent: Color { snapshot.phase.accentColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            header
            countdownCard
            timelineCard
            if !model.upcomingPeaks.isEmpty {
                upcomingSection
            }
            footnote
            Divider().opacity(0.6)
            footer
        }
        .padding(15)
        .frame(width: 336)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(accent)
                .frame(width: 10, height: 10)
                .shadow(color: accent.opacity(0.55), radius: 4)

            Text("DeepSeek")
                .font(.system(size: 13, weight: .semibold))
            Text("API pricing")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Text(snapshot.phase.badge)
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.7)
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(Capsule().fill(accent.opacity(0.15)))
                .foregroundStyle(accent)
        }
    }

    // MARK: - Countdown

    private var countdownCard: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(model.headline)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Text(DurationText.clock(snapshot.timeToChange))
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)

            Text(model.countdownDetail)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(accent.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(accent.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Timeline

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text("Today")
                    .font(.system(size: 11, weight: .semibold))
                Text(model.zoneName)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                Spacer()
                if !snapshot.offPeakNotes.isEmpty {
                    Text(snapshot.offPeakNotes.joined(separator: " · "))
                        .font(.system(size: 9.5))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                }
            }

            TimelineBar(timeline: model.timeline, accent: accent)

            HStack(spacing: 0) {
                Text(LocalDateTime.time(model.timeline.dayStart, timeZone: model.timeZone))
                Spacer()
                Text(intermediateLabel(fraction: 1.0 / 3.0))
                Spacer()
                Text(intermediateLabel(fraction: 2.0 / 3.0))
                Spacer()
                Text(LocalDateTime.time(model.timeline.dayEnd, timeZone: model.timeZone))
            }
            .font(.system(size: 8.5))
            .foregroundStyle(.tertiary)
        }
    }

    private func intermediateLabel(fraction: Double) -> String {
        let total = model.timeline.dayEnd.timeIntervalSince(model.timeline.dayStart)
        let date = model.timeline.dayStart.addingTimeInterval(total * fraction)
        return LocalDateTime.time(date, timeZone: model.timeZone)
    }

    // MARK: - Upcoming peaks

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Next peak windows")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)

            ForEach(model.upcomingPeaks, id: \.start) { window in
                HStack(spacing: 8) {
                    Circle()
                        .fill(accent.opacity(0.8))
                        .frame(width: 5, height: 5)
                    Text(LocalDateTime.dayMonth(window.start, timeZone: model.timeZone))
                        .font(.system(size: 10.5))
                        .frame(width: 74, alignment: .leading)
                    Text(LocalDateTime.range(window, timeZone: model.timeZone))
                        .font(.system(size: 10.5))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text("in \(DurationText.short(window.start.timeIntervalSince(model.now)))")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Footnote

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Peak 01:00–04:00 and 06:00–10:00 UTC, Mon–Fri.")
            Text("Weekends and Chinese public holidays are off-peak. \(Pricing.offPeakDiscount).")
        }
        .font(.system(size: 9))
        .foregroundStyle(.tertiary)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                model.setLaunchAtLogin(!model.launchAtLogin)
            } label: {
                Label(
                    model.launchAtLogin ? "Starts at login" : "Start at login",
                    systemImage: model.launchAtLogin ? "checkmark.circle.fill" : "circle"
                )
                .font(.system(size: 10))
                .foregroundStyle(model.launchAtLogin ? accent : Color.secondary)
            }
            .buttonStyle(.plain)
            .help("Open DeepSeek Peak automatically when you log in")

            Spacer(minLength: 0)

            Button {
                NSWorkspace.shared.open(Pricing.url)
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open the DeepSeek pricing page")

            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Quit DeepSeek Peak")
        }
    }
}

private struct TimelineBar: View {
    let timeline: PeakSchedule.DayTimeline
    let accent: Color

    private let barHeight: CGFloat = 11

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let total = timeline.dayEnd.timeIntervalSince(timeline.dayStart)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(PeakPhase.offPeak.accentColor.opacity(0.28))

                ForEach(timeline.segments.filter(\.isPeak)) { segment in
                    let x = total > 0 ? segment.start.timeIntervalSince(timeline.dayStart) / total * width : 0
                    let w = total > 0 ? max(1.5, segment.end.timeIntervalSince(segment.start) / total * width) : 0
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(PeakPhase.peak.accentColor.opacity(0.9))
                        .frame(width: w)
                        .offset(x: x)
                }
            }
            .frame(height: barHeight)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(alignment: .leading) {
                // "now" marker
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Color(nsColor: .labelColor))
                    .frame(width: 2, height: barHeight + 4)
                    .offset(x: max(0, min(width - 2, timeline.nowFraction * width - 1)))
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0)
            }
            .frame(height: barHeight)
        }
        .frame(height: barHeight)
    }
}

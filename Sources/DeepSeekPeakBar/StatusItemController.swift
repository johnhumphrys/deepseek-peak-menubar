import AppKit
import PeakCore
import SwiftUI

/// Owns the `NSStatusItem`, its context menu and the popover.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let infoItem = NSMenuItem()
    private let scheduleItem = NSMenuItem()
    private let launchAtLoginItem = NSMenuItem()

    private lazy var menuBarContentItem: NSMenuItem = {
        let parent = NSMenuItem(title: "Menu Bar Shows", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for content in MenuBarContent.allCases {
            let item = NSMenuItem(title: content.title, action: #selector(selectMenuBarContent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = content.rawValue
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }()

    private lazy var leadTimeItem: NSMenuItem = {
        let parent = NSMenuItem(title: "Warn Before Peak", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for minutes in Preferences.leadTimeChoices {
            let item = NSMenuItem(title: "\(minutes) minutes", action: #selector(selectLeadTime(_:)), keyEquivalent: "")
            item.target = self
            item.tag = minutes
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }()

    private lazy var popover: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        return popover
    }()

    private var hostingController: NSHostingController<PopoverView>?
    private var timer: Timer?
    private var lastTitle: String?
    private var isShowingError = false

    init(model: AppModel? = nil) {
        self.model = model ?? AppModel()
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        buildMenu()
        configureButton()
    }

    func start() {
        updateStatusItem()
        startTimer()
    }

    // MARK: - Status item

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageLeading
        button.toolTip = "DeepSeek API peak / off-peak pricing"
    }

    private func startTimer() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        model.refresh()
        updateStatusItem()
        reportErrorIfNeeded()
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }

        let phase = model.snapshot.phase
        button.image = StatusIcon.dot(color: phase.accentNSColor)

        let title = model.menuBarTitle
        if title != lastTitle {
            lastTitle = title
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.labelColor,
            ]
            let display = title.isEmpty ? "" : " " + title
            button.attributedTitle = NSAttributedString(string: display, attributes: attributes)
            statusItem.length = title.isEmpty ? NSStatusItem.squareLength : NSStatusItem.variableLength
        }

        button.toolTip = "\(model.snapshot.phase.menuBarLabel) · \(model.headline.lowercased()) \(DurationText.short(model.snapshot.timeToChange))"
    }

    // MARK: - Click handling

    @objc private func statusItemClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        let isSecondaryClick = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if isSecondaryClick {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    /// Also used by the screenshot harness through `DEEPSEEK_PEAK_SHOW_POPOVER=1`.
    func showPopover() {
        guard let button = statusItem.button else { return }
        model.refresh()
        updateStatusItem()

        if hostingController == nil {
            let controller = NSHostingController(rootView: PopoverView(model: model))
            controller.sizingOptions = [.preferredContentSize]
            hostingController = controller
        }
        popover.contentViewController = hostingController
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        popover.contentViewController?.view.window?.makeKey()
    }

    // MARK: - Preview rendering

    /// Forces an appearance for screenshots; the menu bar normally drives it.
    func applyAppearance(_ appearance: NSAppearance?) {
        statusItem.button?.appearance = appearance
        popover.appearance = appearance
        popover.contentViewController?.view.appearance = appearance
    }

    /// Prints the context menu tree for QA (`--print-menu`).
    func printMenuTree() {
        updateMenu()
        func dump(_ menu: NSMenu, indent: String) {
            for item in menu.items {
                if item.isSeparatorItem {
                    print("\(indent)---")
                    continue
                }
                let action = item.action.map { NSStringFromSelector($0) } ?? "nil"
                let target = item.target == nil ? "nil" : "set"
                print("\(indent)\(item.title) [state=\(item.state.rawValue) enabled=\(item.isEnabled) action=\(action) target=\(target)]")
                if let submenu = item.submenu {
                    dump(submenu, indent: indent + "    ")
                }
            }
        }
        dump(menu, indent: "")
    }

    func debugAppearances() -> String {
        let app = NSApp.effectiveAppearance.name.rawValue
        let button = statusItem.button?.effectiveAppearance.name.rawValue ?? "nil"
        let popoverView = popover.contentViewController?.view.effectiveAppearance.name.rawValue ?? "nil"
        return "app=\(app) button=\(button) popover=\(popoverView)"
    }

    func renderPreviews(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let phase = model.snapshot.phase.rawValue
        if let button = statusItem.button {
            PreviewRenderer.write(button, to: directory.appendingPathComponent("statusitem-\(phase).png"))
        }
        if let view = popover.contentViewController?.view, popover.isShown {
            PreviewRenderer.write(view, to: directory.appendingPathComponent("popover-\(phase).png"))
        }
    }

    // MARK: - Menu

    private func buildMenu() {
        menu.autoenablesItems = false
        menu.delegate = self

        infoItem.isEnabled = false
        scheduleItem.isEnabled = false
        menu.addItem(infoItem)
        menu.addItem(scheduleItem)
        menu.addItem(.separator())
        menu.addItem(menuBarContentItem)
        menu.addItem(leadTimeItem)
        menu.addItem(.separator())

        launchAtLoginItem.title = "Launch at Login"
        launchAtLoginItem.target = self
        launchAtLoginItem.action = #selector(toggleLaunchAtLogin)
        menu.addItem(launchAtLoginItem)

        let pricingItem = NSMenuItem(title: "DeepSeek Pricing…", action: #selector(openPricing), keyEquivalent: "")
        pricingItem.target = self
        menu.addItem(pricingItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit DeepSeek Peak", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func showContextMenu() {
        if popover.isShown { popover.performClose(nil) }
        updateMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateMenu()
    }

    private func updateMenu() {
        let snapshot = model.snapshot
        let countdown = DurationText.compact(snapshot.timeToChange)
        infoItem.title = snapshot.phase == .peak
            ? "PEAK · off-peak in \(countdown)"
            : "OFF-PEAK · peak in \(countdown)"

        let todaysWindows = model.timeline.segments.filter(\.isPeak)
        if todaysWindows.isEmpty {
            let reason = snapshot.offPeakNotes.first.map { " — \($0)" } ?? ""
            scheduleItem.title = "Off-peak all day\(reason)"
        } else {
            let ranges = todaysWindows
                .map { LocalDateTime.range(PeakWindow(start: $0.start, end: $0.end), timeZone: model.timeZone) }
                .joined(separator: "  ·  ")
            scheduleItem.title = "Peak today: \(ranges)"
        }

        for item in menuBarContentItem.submenu?.items ?? [] {
            guard let raw = item.representedObject as? String else { continue }
            item.state = (raw == model.menuBarContent.rawValue) ? .on : .off
        }
        for item in leadTimeItem.submenu?.items ?? [] {
            item.state = (item.tag == model.leadTimeMinutes) ? .on : .off
        }
        launchAtLoginItem.state = model.launchAtLogin ? .on : .off
    }

    @objc private func selectMenuBarContent(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let content = MenuBarContent(rawValue: raw)
        else { return }
        model.setMenuBarContent(content)
        lastTitle = nil
        updateStatusItem()
    }

    @objc private func selectLeadTime(_ sender: NSMenuItem) {
        model.setLeadTimeMinutes(sender.tag)
        lastTitle = nil
        updateStatusItem()
        updateMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        model.setLaunchAtLogin(!model.launchAtLogin)
        updateMenu()
        reportErrorIfNeeded()
    }

    @objc private func openPricing() {
        NSWorkspace.shared.open(Pricing.url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Errors

    private func reportErrorIfNeeded() {
        guard let message = model.lastError, !isShowingError else { return }
        isShowingError = true
        model.lastError = nil
        let alert = NSAlert()
        alert.messageText = "Couldn't update Login Item"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        alert.runModal()
        isShowingError = false
    }
}

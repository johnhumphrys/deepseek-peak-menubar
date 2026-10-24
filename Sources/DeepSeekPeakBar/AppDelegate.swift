import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // QA hook: force an appearance for screenshots.
        let forcedAppearance: NSAppearance? = {
            switch ProcessInfo.processInfo.environment["DEEPSEEK_PEAK_APPEARANCE"] {
            case "light": return NSAppearance(named: .aqua)
            case "dark": return NSAppearance(named: .darkAqua)
            default: return nil
            }
        }()
        if let forcedAppearance {
            NSApp.appearance = forcedAppearance
        }

        let controller = StatusItemController()
        self.controller = controller
        controller.start()
        if let forcedAppearance {
            controller.applyAppearance(forcedAppearance)
            DispatchQueue.main.async { controller.applyAppearance(forcedAppearance) }
        }

        // Screenshot / QA harness: open the popover automatically.
        if ProcessInfo.processInfo.environment["DEEPSEEK_PEAK_SHOW_POPOVER"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                controller.showPopover()
            }
        }

        if CommandLine.arguments.contains("--print-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                controller.printMenuTree()
                NSApp.terminate(nil)
            }
        }

        // `--render <dir>` writes PNGs of the real views and exits.
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--render"), index + 1 < arguments.count {
            let directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                controller.showPopover()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                fputs("appearance: \(controller.debugAppearances())\n", stderr)
                controller.renderPreviews(to: directory)
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

import AppKit
import PeakCore
import SwiftUI

extension PeakPhase {
    var accentNSColor: NSColor {
        switch self {
        case .offPeak:
            return NSColor(srgbRed: 0.10, green: 0.66, blue: 0.38, alpha: 1)
        case .approaching:
            return NSColor(srgbRed: 0.95, green: 0.62, blue: 0.04, alpha: 1)
        case .peak:
            return NSColor(srgbRed: 0.90, green: 0.22, blue: 0.20, alpha: 1)
        }
    }

    var accentColor: Color { Color(nsColor: accentNSColor) }

    /// Menu bar text (kept short so the item does not get crowded out).
    var menuBarLabel: String {
        switch self {
        case .offPeak: return "Off-peak"
        case .approaching: return "Peak soon"
        case .peak: return "Peak"
        }
    }

    var badge: String {
        switch self {
        case .offPeak: return "OFF-PEAK"
        case .approaching: return "PEAK SOON"
        case .peak: return "PEAK"
        }
    }
}

enum Pricing {
    static let offPeakDiscount = "Off-peak rates are 50% of peak"
    static let url = URL(string: "https://api-docs.deepseek.com/quick_start/pricing")!
}

enum StatusIcon {
    /// A small filled circle that keeps its colour in the menu bar.
    static func dot(color: NSColor, diameter: CGFloat = 9) -> NSImage {
        let size = NSSize(width: diameter + 2, height: diameter + 2)
        let image = NSImage(size: size, flipped: false) { _ in
            let rect = NSRect(x: 1, y: 1, width: diameter, height: diameter)
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

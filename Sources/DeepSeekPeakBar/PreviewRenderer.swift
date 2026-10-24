import AppKit

/// Renders real views to PNG via `cacheDisplay`, which needs no Screen
/// Recording permission. Used by `--render` for docs and visual QA.
enum PreviewRenderer {
    static func write(_ view: NSView, to url: URL) {
        view.layoutSubtreeIfNeeded()
        guard view.bounds.width > 0, view.bounds.height > 0,
              let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return }
        // Dynamic colours (labelColor, windowBackgroundColor) resolve against
        // the current drawing appearance; without this they render as light.
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: view.bounds, to: representation)
        }
        guard let data = representation.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }

    static func write(_ button: NSStatusBarButton, to url: URL) {
        write(button as NSView, to: url)
    }
}

import AppKit
import Outlook2iCloudCalCore

/// Renders the menu bar icon for a badge.
enum StatusIcon {
    private static let symbolName = "calendar"
    private static let pointSize: CGFloat = 15

    /// A template image when there is no badge, so that the menu bar tints it
    /// for light and dark mode; otherwise a colored image with the mark drawn
    /// at the bottom-right.
    static func image(for badge: IconBadge) -> NSImage {
        let base = symbol(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular))
        let mark: (String, NSColor)
        switch badge {
        case .none:
            base.isTemplate = true
            return base
        case .alert:
            mark = ("!", .systemRed)
        case .paused:
            mark = ("⏸", .systemOrange)
        }
        let size = base.size
        let image = NSImage(size: size, flipped: false) { rect in
            // The handler runs at draw time, so `labelColor` follows the
            // current appearance.
            let tinted = symbol(
                NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [.labelColor])))
            tinted.draw(in: rect)
            let text = NSAttributedString(
                string: mark.0,
                attributes: [
                    .font: NSFont.systemFont(ofSize: rect.height * 0.6, weight: .heavy),
                    .foregroundColor: mark.1,
                ])
            let textSize = text.size()
            text.draw(
                at: NSPoint(x: rect.maxX - textSize.width, y: rect.minY - textSize.height * 0.15))
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func symbol(_ configuration: NSImage.SymbolConfiguration) -> NSImage {
        let image =
            NSImage(systemSymbolName: symbolName, accessibilityDescription: "Outlook2iCloudCal")
            ?? NSImage()
        return image.withSymbolConfiguration(configuration) ?? image
    }
}

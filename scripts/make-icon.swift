// Writes the app icon as an Icon Composer document (.icon bundle) for actool.
// Usage: swift scripts/make-icon.swift <output AppIcon.icon dir>
//
// The document has two groups. The bottom group is a full-bleed diagonal
// gradient image with glass effects off; the document-level fill only draws
// vertical gradients, so the diagonal is baked into a layer image. The top
// group holds a white cloud and a calendar glyph in the gradient's start
// color. The system applies the icon shape, so no artwork is masked here.
import AppKit

let canvas = 1024
let outlookBlue = NSColor(srgbRed: 0x0F / 255, green: 0x6C / 255, blue: 0xBD / 255, alpha: 1)
let icloudBlue = NSColor(srgbRed: 0x3F / 255, green: 0xA9 / 255, blue: 0xF5 / 255, alpha: 1)

/// Renders a transparent square canvas with the given drawing block and returns PNG data.
func renderPNG(_ draw: (CGFloat) -> Void) -> Data {
    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: rep)
    else { fatalError("cannot create bitmap context") }
    let size = CGFloat(canvas)
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    draw(size)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
    return png
}

/// Returns an SF Symbol tinted with a single color at the given point size.
func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        .applying(.init(paletteColors: [color]))
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(config)
    else { fatalError("SF Symbol '\(name)' unavailable") }
    return image
}

/// Draws an image scaled to the given width, centered on the given point.
func draw(_ image: NSImage, width: CGFloat, center: CGPoint) {
    let height = width * image.size.height / image.size.width
    image.draw(in: NSRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height))
}

let background = renderPNG { size in
    let gradient = NSGradient(starting: outlookBlue, ending: icloudBlue)!
    // Top-left to bottom-right (AppKit's origin is bottom-left).
    gradient.draw(from: CGPoint(x: 0, y: size), to: CGPoint(x: size, y: 0), options: [])
}

// SF Symbol images carry side padding, so the cloud is drawn wider than its
// visible 70% of the canvas. The cloud's body sits below the symbol's center,
// so the calendar is shifted down to land inside it.
let cloudWidth = CGFloat(canvas) * 0.79
let cloud = renderPNG { size in
    draw(
        symbol("cloud.fill", pointSize: cloudWidth, weight: .regular, color: .white),
        width: cloudWidth, center: CGPoint(x: size / 2, y: size / 2))
}
let calendar = renderPNG { size in
    draw(
        symbol("calendar", pointSize: cloudWidth, weight: .semibold, color: outlookBlue),
        width: cloudWidth * 0.46, center: CGPoint(x: size / 2, y: size / 2 - cloudWidth * 0.07))
}

let iconJSON = """
    {
      "fill" : {
        "solid" : "srgb:0.05882,0.42353,0.74118,1.00000"
      },
      "groups" : [
        {
          "layers" : [
            { "image-name" : "calendar.png", "name" : "calendar" },
            { "image-name" : "cloud.png", "name" : "cloud" }
          ],
          "name" : "foreground"
        },
        {
          "layers" : [
            { "glass" : false, "image-name" : "background.png", "name" : "background" }
          ],
          "name" : "background",
          "shadow" : { "kind" : "none", "opacity" : 0 },
          "specular" : false,
          "translucency" : { "enabled" : false, "value" : 0 }
        }
      ],
      "supported-platforms" : {
        "squares" : [ "macOS" ]
      }
    }

    """

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output AppIcon.icon dir>\n".utf8))
    exit(2)
}
let iconDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let assetsDir = iconDir.appendingPathComponent("Assets", isDirectory: true)
try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
try background.write(to: assetsDir.appendingPathComponent("background.png"))
try cloud.write(to: assetsDir.appendingPathComponent("cloud.png"))
try calendar.write(to: assetsDir.appendingPathComponent("calendar.png"))
try Data(iconJSON.utf8).write(to: iconDir.appendingPathComponent("icon.json"))

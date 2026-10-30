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

let background = renderPNG { size in
    let gradient = NSGradient(starting: outlookBlue, ending: icloudBlue)!
    // Top-left to bottom-right (AppKit's origin is bottom-left).
    gradient.draw(from: CGPoint(x: 0, y: size), to: CGPoint(x: size, y: 0), options: [])
}

// The shapes are drawn by hand, so the icon contains no SF Symbols. Geometry
// is in canvas units (1024 x 1024, origin bottom-left).

/// Returns a cloud silhouette about 70% of the canvas wide: a flat-bottomed
/// pill with three circular bumps, the largest center-left, unioned into one path.
func cloudPath() -> CGPath {
    var path = CGPath(
        roundedRect: CGRect(x: 153, y: 280, width: 718, height: 240),
        cornerWidth: 120, cornerHeight: 120, transform: nil)
    // Each bump is a circle given by its bounding square.
    let bumps = [
        CGRect(x: 300 - 130, y: 470 - 130, width: 260, height: 260),
        CGRect(x: 468 - 185, y: 555 - 185, width: 370, height: 370),
        CGRect(x: 680 - 150, y: 505 - 150, width: 300, height: 300),
    ]
    for bump in bumps {
        path = path.union(CGPath(ellipseIn: bump, transform: nil))
    }
    return path
}

/// Draws a calendar inside the cloud body: a rounded outline with a solid
/// header band and a 3 x 4 grid of rounded day cells.
func drawCalendar(in context: CGContext) {
    let frame = CGRect(x: 362, y: 325, width: 300, height: 270)
    let radius: CGFloat = 40
    let stroke: CGFloat = 26
    let outline = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.setFillColor(outlookBlue.cgColor)

    // Outline ring: the outer rounded rectangle minus the inset one.
    let inner = CGPath(
        roundedRect: frame.insetBy(dx: stroke, dy: stroke),
        cornerWidth: radius - stroke, cornerHeight: radius - stroke, transform: nil)
    context.addPath(outline.subtracting(inner))
    context.fillPath()

    // Header band, clipped to the outline so its top corners stay rounded.
    let headerHeight: CGFloat = 78
    context.saveGState()
    context.addPath(outline)
    context.clip()
    context.fill(CGRect(x: frame.minX, y: frame.maxY - headerHeight, width: frame.width, height: headerHeight))
    context.restoreGState()

    // Day cells in 3 rows and 4 columns below the header.
    let cell: CGFloat = 36
    let columns = 4
    let rows = 3
    let gridLeft = frame.minX + stroke
    let gridWidth = frame.width - 2 * stroke
    let gridBottom = frame.minY + stroke
    let gridHeight = frame.height - stroke - headerHeight
    let gapX = (gridWidth - CGFloat(columns) * cell) / CGFloat(columns + 1)
    let gapY = (gridHeight - CGFloat(rows) * cell) / CGFloat(rows + 1)
    for row in 0..<rows {
        for column in 0..<columns {
            let rect = CGRect(
                x: gridLeft + gapX + CGFloat(column) * (cell + gapX),
                y: gridBottom + gapY + CGFloat(row) * (cell + gapY),
                width: cell, height: cell)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil))
        }
    }
    context.fillPath()
}

let cloud = renderPNG { _ in
    let context = NSGraphicsContext.current!.cgContext
    context.setFillColor(NSColor.white.cgColor)
    context.addPath(cloudPath())
    context.fillPath()
}
let calendar = renderPNG { _ in drawCalendar(in: NSGraphicsContext.current!.cgContext) }

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

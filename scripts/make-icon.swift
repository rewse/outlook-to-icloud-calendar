// Renders the app icon into an .iconset directory.
// Usage: swift scripts/make-icon.swift <output.iconset dir>
import AppKit

let outlookBlue = NSColor(srgbRed: 0x0F / 255, green: 0x6C / 255, blue: 0xBD / 255, alpha: 1)
let icloudBlue = NSColor(srgbRed: 0x3F / 255, green: 0xA9 / 255, blue: 0xF5 / 255, alpha: 1)

/// Returns a continuous-corner rounded rectangle (superellipse corners).
func squirclePath(in rect: CGRect, radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    // Control-point factors approximating Apple's continuous corner curve.
    let k: CGFloat = 1.4
    let r = min(radius * k, min(rect.width, rect.height) / 2)
    let minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
    let c = r * 0.45  // handle length for the bezier corner
    path.move(to: CGPoint(x: minX + r, y: minY))
    path.addLine(to: CGPoint(x: maxX - r, y: minY))
    path.addCurve(
        to: CGPoint(x: maxX, y: minY + r),
        control1: CGPoint(x: maxX - c, y: minY),
        control2: CGPoint(x: maxX, y: minY + c))
    path.addLine(to: CGPoint(x: maxX, y: maxY - r))
    path.addCurve(
        to: CGPoint(x: maxX - r, y: maxY),
        control1: CGPoint(x: maxX, y: maxY - c),
        control2: CGPoint(x: maxX - c, y: maxY))
    path.addLine(to: CGPoint(x: minX + r, y: maxY))
    path.addCurve(
        to: CGPoint(x: minX, y: maxY - r),
        control1: CGPoint(x: minX + c, y: maxY),
        control2: CGPoint(x: minX, y: maxY - c))
    path.addLine(to: CGPoint(x: minX, y: minY + r))
    path.addCurve(
        to: CGPoint(x: minX + r, y: minY),
        control1: CGPoint(x: minX, y: minY + c),
        control2: CGPoint(x: minX + c, y: minY))
    path.closeSubpath()
    return path
}

/// Draws the icon into a square pixel canvas of the given size.
func renderIcon(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: rep)
    else { fatalError("cannot create bitmap context") }
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let cg = context.cgContext

    let inset = size * 0.10
    let body = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    cg.saveGState()
    cg.addPath(squirclePath(in: body, radius: body.width * 0.2237))
    cg.clip()
    let gradient = NSGradient(starting: outlookBlue, ending: icloudBlue)!
    // Top-left to bottom-right (AppKit's origin is bottom-left).
    gradient.draw(from: CGPoint(x: body.minX, y: body.maxY), to: CGPoint(x: body.maxX, y: body.minY), options: [])
    cg.restoreGState()

    let symbolWidth = body.width * 0.55
    let config = NSImage.SymbolConfiguration(pointSize: symbolWidth, weight: .regular)
        .applying(.init(paletteColors: [.white]))
    guard let symbol = NSImage(systemSymbolName: "calendar", accessibilityDescription: nil)?
        .withSymbolConfiguration(config)
    else { fatalError("SF Symbol 'calendar' unavailable") }
    let aspect = symbol.size.height / symbol.size.width
    let drawSize = NSSize(width: symbolWidth, height: symbolWidth * aspect)
    let target = NSRect(
        x: body.midX - drawSize.width / 2, y: body.midY - drawSize.height / 2,
        width: drawSize.width, height: drawSize.height)
    symbol.draw(in: target)

    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
    return png
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.iconset dir>\n".utf8))
    exit(2)
}
let outputDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try renderIcon(pixels: base * scale).write(to: outputDir.appendingPathComponent(name))
    }
}

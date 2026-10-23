// Renders Resources/AppIcon.icns: a white remote glyph on a blue squircle.
// Run with: swift scripts/make-icon.swift (scripts/build-app.sh does this when the icon is missing).
import AppKit

let canvas: CGFloat = 1024
// Apple's macOS icon grid: an 824 pt body centred on a 1024 pt canvas.

func render(size size_px: Int) -> Data {
    let size = size_px
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // Draw at real pixel size: scaling the context would rasterise the symbol at low resolution.
    let k = CGFloat(size) / canvas
    let body = NSRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
    let radius = 185 * k

    let shape = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -12 * k)
    shadow.shadowBlurRadius = 28 * k
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(calibratedRed: 0.10, green: 0.32, blue: 0.95, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [NSColor(calibratedRed: 0.33, green: 0.62, blue: 1.0, alpha: 1),
                        NSColor(calibratedRed: 0.10, green: 0.30, blue: 0.92, alpha: 1),
                        NSColor(calibratedRed: 0.20, green: 0.13, blue: 0.62, alpha: 1)])!
        .draw(in: body, angle: -90)
    // Soft glass sheen across the top half.
    NSGradient(starting: NSColor.white.withAlphaComponent(0.28), ending: NSColor.white.withAlphaComponent(0))!
        .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.35).setStroke()
    let rim = NSBezierPath(roundedRect: body.insetBy(dx: 2 * k, dy: 2 * k), xRadius: radius - 2 * k, yRadius: radius - 2 * k)
    rim.lineWidth = 4 * k
    rim.stroke()

    let config = NSImage.SymbolConfiguration(pointSize: 470 * k, weight: .regular)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let glyph = NSImage(systemSymbolName: "appletvremote.gen4.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let glyphSize = glyph.size
        let side = CGFloat(size_px)
        let rect = NSRect(x: (side - glyphSize.width) / 2, y: (side - glyphSize.height) / 2, width: glyphSize.width, height: glyphSize.height)
        let glow = NSShadow()
        glow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        glow.shadowOffset = NSSize(width: 0, height: -10 * k)
        glow.shadowBlurRadius = 24 * k
        glow.set()
        glyph.draw(in: rect)
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try! render(size: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try! render(size: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
let resources = root.appendingPathComponent("Resources")
try! FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
try! render(size: 512).write(to: resources.appendingPathComponent("AppIcon-preview.png"))
print("Wrote Resources/AppIcon.icns")

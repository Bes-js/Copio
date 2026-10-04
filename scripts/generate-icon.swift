import AppKit
import Foundation

// A layered macOS app icon based on the two-sheet menu-bar mark.
let size = 1024
let output = CommandLine.arguments.dropFirst().first
    ?? "Sources/Copio/Resources/Copio-icon-preview.png"

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Could not create icon canvas")
}

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high

let tile = NSBezierPath(roundedRect: NSRect(x: 28, y: 28, width: 968, height: 968), xRadius: 222, yRadius: 222)
NSGradient(starting: color(91, 177, 249), ending: color(31, 80, 189))!
    .draw(in: tile, angle: 135)

func sheet(_ rect: NSRect, upper: NSColor, lower: NSColor, border: NSColor, shadowAlpha: CGFloat) {
    let path = NSBezierPath(roundedRect: rect, xRadius: 58, yRadius: 58)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(8, 35, 93, shadowAlpha)
    shadow.shadowBlurRadius = 32
    shadow.shadowOffset = NSSize(width: 0, height: -22)
    shadow.set()
    color(255, 255, 255).setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: upper, ending: lower)!.draw(in: path, angle: 95)
    path.lineWidth = 18
    border.setStroke()
    path.stroke()
}

sheet(
    NSRect(x: 247, y: 407, width: 402, height: 402),
    upper: color(218, 240, 255),
    lower: color(153, 206, 251),
    border: color(244, 250, 255, 0.88),
    shadowAlpha: 0.24
)
sheet(
    NSRect(x: 375, y: 265, width: 402, height: 402),
    upper: color(255, 255, 255),
    lower: color(216, 237, 255),
    border: color(255, 255, 255, 0.96),
    shadowAlpha: 0.36
)

NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode icon PNG")
}
try png.write(to: URL(fileURLWithPath: output))

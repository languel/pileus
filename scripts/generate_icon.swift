import AppKit

let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

// Background rounded rectangle (macOS squircle)
let rect = CGRect(x: 80, y: 80, width: 864, height: 864)
let path = CGPath(roundedRect: rect, cornerWidth: 200, cornerHeight: 200, transform: nil)

ctx.addPath(path)
ctx.clip()

// Gradient background: deep blue to modern cyan
let colors = [
    NSColor(calibratedRed: 0.10, green: 0.20, blue: 0.45, alpha: 1.0).cgColor,
    NSColor(calibratedRed: 0.15, green: 0.55, blue: 0.85, alpha: 1.0).cgColor
] as CFArray
let colorSpace = CGColorSpaceCreateDeviceRGB()
if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 944), end: CGPoint(x: 512, y: 80), options: [])
}

// Inner subtle glow
ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.25).cgColor)
ctx.setLineWidth(16)
ctx.addPath(path)
ctx.strokePath()

// SF Symbol drawing: "icloud.and.arrow.down" or "sparkles"
let config = NSImage.SymbolConfiguration(pointSize: 420, weight: .semibold)
if let symbol = NSImage(systemSymbolName: "icloud.and.arrow.down", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
    let tintColor = NSColor.white
    let tinted = NSImage(size: symbol.size)
    tinted.lockFocus()
    tintColor.set()
    let imageRect = NSRect(origin: .zero, size: symbol.size)
    symbol.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    tintColor.set()
    imageRect.fill(using: .sourceAtop)
    tinted.unlockFocus()

    let destRect = NSRect(
        x: (1024 - symbol.size.width) / 2,
        y: (1024 - symbol.size.height) / 2 - 10,
        width: symbol.size.width,
        height: symbol.size.height
    )
    tinted.draw(in: destRect)
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    exit(1)
}

let iconsetDir = "CloudPurge.iconset"
try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for (s, filename) in sizes {
    let resized = NSImage(size: NSSize(width: s, height: s))
    resized.lockFocus()
    image.draw(in: NSRect(x: 0, y: 0, width: s, height: s))
    resized.unlockFocus()
    if let rTiff = resized.tiffRepresentation,
       let rRep = NSBitmapImageRep(data: rTiff),
       let rPng = rRep.representation(using: .png, properties: [:]) {
        try? rPng.write(to: URL(fileURLWithPath: "\(iconsetDir)/\(filename)"))
    }
}

print("Iconset generated successfully!")

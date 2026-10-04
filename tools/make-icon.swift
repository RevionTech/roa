import AppKit

guard CommandLine.arguments.count == 3 else { fatalError("make-icon.swift <symbol.pdf> <dist>") }
let symbolURL = URL(fileURLWithPath: CommandLine.arguments[1])
let directory = URL(fileURLWithPath: CommandLine.arguments[2])
let iconset = directory.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
guard let symbol = NSImage(contentsOf: symbolURL) else { fatalError("Missing symbol") }
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Image allocation failed") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let extent = CGFloat(pixels)
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: extent * 0.06, y: extent * 0.06,
            width: extent * 0.88, height: extent * 0.88), xRadius: extent * 0.19, yRadius: extent * 0.19).fill()
        symbol.draw(in: NSRect(x: extent * 0.20, y: extent * 0.315,
                               width: extent * 0.60, height: extent * 0.37))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
        let suffix = scale == 2 ? "@2x" : ""
        try png.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", directory.appendingPathComponent("ROA.app/Contents/Resources/AppIcon.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
try FileManager.default.removeItem(at: iconset)

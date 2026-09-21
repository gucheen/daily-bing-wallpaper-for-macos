import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = NSAffineTransform()
        transform.scale(by: CGFloat(pixels) / 1024)
        transform.concat()
        let background = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896),
                                      xRadius: 200, yRadius: 200)
        NSGradient(starting: NSColor(srgbRed: 0.14, green: 0.23, blue: 0.48, alpha: 1),
                   ending: NSColor(srgbRed: 0.29, green: 0.57, blue: 0.67, alpha: 1))!
            .draw(in: background, angle: 65)
        NSColor(srgbRed: 1, green: 0.85, blue: 0.54, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 610, y: 605, width: 140, height: 140)).fill()
        let mountain = NSBezierPath()
        mountain.move(to: NSPoint(x: 180, y: 280))
        mountain.line(to: NSPoint(x: 430, y: 640))
        mountain.line(to: NSPoint(x: 590, y: 420))
        mountain.line(to: NSPoint(x: 700, y: 530))
        mountain.line(to: NSPoint(x: 850, y: 280))
        mountain.close()
        NSColor(srgbRed: 0.82, green: 0.94, blue: 0.92, alpha: 1).setFill()
        mountain.fill()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let url = directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}

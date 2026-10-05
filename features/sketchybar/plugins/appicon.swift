// Usage: swift appicon.swift <outdir> <bundle id>...
// Writes app.<bundle id>.png, the app's icon at 36px.
import AppKit

let outDir = CommandLine.arguments[1]
let px = 36

for id in CommandLine.arguments.dropFirst(2) {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
          let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0) else { continue }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSWorkspace.shared.icon(forFile: url.path)
        .draw(in: NSRect(x: 0, y: 0, width: px, height: px), from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    try? rep.representation(using: .png, properties: [:])?
        .write(to: URL(fileURLWithPath: "\(outDir)/app.\(id).png"))
}

// Usage: swift sfsymbol.swift <outdir> <symbol>...
// Writes white <symbol>.<alpha%>.png files; SketchyBar can't tint images, so dimmed variants are baked in.
import AppKit

let outDir = CommandLine.arguments[1]
let variants: [(String, CGFloat)] = [("100", 1.0), ("70", 0.7), ("30", 0.3)]
let px = 36

for name in CommandLine.arguments.dropFirst(2) {
    let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
    guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else { continue }

    let scale = min(CGFloat(px) * 0.9 / symbol.size.width, CGFloat(px) * 0.9 / symbol.size.height)
    let w = symbol.size.width * scale
    let h = symbol.size.height * scale
    let target = NSRect(x: (CGFloat(px) - w) / 2, y: (CGFloat(px) - h) / 2, width: w, height: h)

    for (suffix, alpha) in variants {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0) else { continue }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        symbol.draw(in: target)
        NSColor.white.withAlphaComponent(alpha).setFill()
        NSRect(x: 0, y: 0, width: px, height: px).fill(using: .sourceIn)
        NSGraphicsContext.restoreGraphicsState()

        try? rep.representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: "\(outDir)/\(name).\(suffix).png"))
    }
}

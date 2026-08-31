#!/usr/bin/env swift
// Renders Wisp.icns from code — the icon is the app's own level meter,
// so there is no binary asset to keep in sync with the UI.
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./Wisp.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

/// Relative bar heights — the middle bar is tallest, as in the recording capsule.
let weights: [CGFloat] = [0.34, 0.60, 1.0, 0.60, 0.34]

func render(_ px: Int) -> Data? {
    let s = CGFloat(px)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    guard let ctx = NSGraphicsContext.current?.cgContext else { return nil }

    // macOS icons sit inset inside their canvas rather than filling it.
    let inset = s * 0.094
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.2237

    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    ctx.saveGState()
    squircle.addClip()

    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.16, green: 0.18, blue: 0.20, alpha: 1),
        NSColor(srgbRed: 0.06, green: 0.07, blue: 0.08, alpha: 1),
    ])
    gradient?.draw(in: rect, angle: -90)

    // A soft highlight across the top keeps it from reading as a flat rectangle.
    let sheen = NSGradient(colors: [
        NSColor(white: 1, alpha: 0.14), NSColor(white: 1, alpha: 0),
    ])
    sheen?.draw(in: CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: -90)
    ctx.restoreGState()

    // The meter.
    let barW = rect.width * 0.088
    let gap = rect.width * 0.062
    let total = barW * 5 + gap * 4
    var x = rect.midX - total / 2
    let maxH = rect.height * 0.52

    for w in weights {
        let h = max(barW, maxH * w)
        let bar = CGRect(x: x, y: rect.midY - h / 2, width: barW, height: h)
        NSColor(srgbRed: 0.98, green: 0.98, blue: 0.97, alpha: 1).setFill()
        NSBezierPath(roundedRect: bar, xRadius: barW / 2, yRadius: barW / 2).fill()
        x += barW + gap
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

// iconset expects both @1x and @2x names for each logical size.
let names: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]

for (px, name) in names {
    guard let data = render(px) else { print("failed \(name)"); exit(1) }
    try! data.write(to: URL(fileURLWithPath: "\(out)/\(name)"))
}
print("rendered \(names.count) images into \(out)")
_ = sizes

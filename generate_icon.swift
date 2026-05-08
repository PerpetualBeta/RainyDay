#!/usr/bin/env swift

import AppKit
import CoreGraphics

// Brand-consistent slate-and-amber palette, drawn as a single fat raindrop
// with a streak trailing up behind it. Echoes Reverie's "ink on paper"
// instinct but in raindrop dialect: drop body, soft halo, tiny specular
// highlight; backdrop is the slate gradient + amber streetlight glow that
// the saver itself paints.

let slateTop    = NSColor(srgbRed: 0x1F/255, green: 0x27/255, blue: 0x33/255, alpha: 1.0)
let slateBottom = NSColor(srgbRed: 0x0E/255, green: 0x12/255, blue: 0x18/255, alpha: 1.0)
let amber       = NSColor(srgbRed: 0xE8/255, green: 0xA4/255, blue: 0x5A/255, alpha: 1.0)
let dropColor   = NSColor(srgbRed: 0xE8/255, green: 0xDB/255, blue: 0xC6/255, alpha: 1.0)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let s = size

    // Rounded slate background.
    let bgRect = NSRect(x: s * 0.04, y: s * 0.04, width: s * 0.92, height: s * 0.92)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: s * 0.18, yRadius: s * 0.18)
    let space = CGColorSpaceCreateDeviceRGB()

    ctx.saveGState()
    ctx.addPath(bgPath.cgPath)
    ctx.clip()

    if let bgGradient = CGGradient(
        colorsSpace: space,
        colors: [slateTop.cgColor, slateBottom.cgColor] as CFArray,
        locations: [0.0, 1.0]
    ) {
        ctx.drawLinearGradient(
            bgGradient,
            start: CGPoint(x: s / 2, y: s),
            end:   CGPoint(x: s / 2, y: 0),
            options: []
        )
    }

    // Faint amber accent low-right (streetlight glow), echoes the saver.
    if let amberGlow = CGGradient(
        colorsSpace: space,
        colors: [
            amber.withAlphaComponent(0.40).cgColor,
            amber.withAlphaComponent(0.0).cgColor,
        ] as CFArray,
        locations: [0.0, 1.0]
    ) {
        ctx.drawRadialGradient(
            amberGlow,
            startCenter: CGPoint(x: s * 0.66, y: s * 0.30),
            startRadius: 0,
            endCenter: CGPoint(x: s * 0.66, y: s * 0.30),
            endRadius: s * 0.45,
            options: []
        )
    }

    // Streak trail rising up from the drop. Drawn as a tapered path with
    // alpha falloff so the trail looks like water that's still draining.
    let dropCx = s * 0.50
    let dropCy = s * 0.40            // a touch below centre
    let dropR  = s * 0.13
    let trailLen = s * 0.42
    let trailSegments = 18

    for i in 0..<trailSegments {
        let p = CGFloat(i) / CGFloat(trailSegments)
        let alpha = 0.05 + p * 0.30
        let width = (0.4 + p * 1.0) * dropR * 0.55
        let yStart = dropCy + trailLen * (1.0 - p) - trailLen * 0.05
        let yEnd   = dropCy + trailLen * (1.0 - p)
        ctx.setStrokeColor(dropColor.withAlphaComponent(alpha).cgColor)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: dropCx, y: yStart))
        ctx.addLine(to: CGPoint(x: dropCx, y: yEnd))
        ctx.strokePath()
    }

    // Drop halo (broader, very faint) — gives the drop a wet sheen.
    let halo = dropR * 1.6
    ctx.setFillColor(dropColor.withAlphaComponent(0.20).cgColor)
    ctx.fillEllipse(in: CGRect(
        x: dropCx - halo, y: dropCy - halo,
        width: halo * 2,  height: halo * 2
    ))

    // Drop body.
    ctx.setFillColor(dropColor.withAlphaComponent(0.92).cgColor)
    ctx.fillEllipse(in: CGRect(
        x: dropCx - dropR, y: dropCy - dropR,
        width: dropR * 2,  height: dropR * 2
    ))

    // Specular highlight, top-left of drop.
    let specR = dropR * 0.32
    let specOffset = dropR * 0.42
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.60).cgColor)
    ctx.fillEllipse(in: CGRect(
        x: dropCx - specOffset - specR,
        y: dropCy + specOffset - specR,
        width: specR * 2,
        height: specR * 2
    ))

    ctx.restoreGState()

    image.unlockFocus()
    return image
}

extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        let points = UnsafeMutablePointer<NSPoint>.allocate(capacity: 3)
        defer { points.deallocate() }
        for i in 0..<elementCount {
            let element = self.element(at: i, associatedPoints: points)
            switch element {
            case .moveTo:           path.move(to: points[0])
            case .lineTo:           path.addLine(to: points[0])
            case .curveTo:          path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .cubicCurveTo:     path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo: path.addQuadCurve(to: points[1], control: points[0])
            case .closePath:        path.closeSubpath()
            @unknown default: break
            }
        }
        return path
    }
}

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]

let scriptDir = CommandLine.arguments[0].components(separatedBy: "/").dropLast().joined(separator: "/")
let iconsetDir = (scriptDir.isEmpty ? "." : scriptDir) + "/Resources/RainyDay.iconset"
let fm = FileManager.default
try? fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

for (size, name) in sizes {
    let image = drawIcon(size: CGFloat(size))
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
    else { continue }
    try! png.write(to: URL(fileURLWithPath: iconsetDir + "/" + name))
    print("  \(name) (\(size)x\(size))")
}

let icnsPath = (scriptDir.isEmpty ? "." : scriptDir) + "/Resources/AppIcon.icns"
let result = Process()
result.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
result.arguments = ["-c", "icns", iconsetDir, "-o", icnsPath]
try! result.run()
result.waitUntilExit()
print("  AppIcon.icns")
print("Done.")

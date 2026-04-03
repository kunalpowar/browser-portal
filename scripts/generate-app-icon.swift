import AppKit
import Foundation

let fileManager = FileManager.default
let rootURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let resourcesURL = rootURL.appending(path: "Resources", directoryHint: .isDirectory)
let iconsetURL = resourcesURL.appending(path: "AppIcon.iconset", directoryHint: .isDirectory)
let previewURL = resourcesURL.appending(path: "AppIcon-preview.png", directoryHint: .notDirectory)
let icnsURL = resourcesURL.appending(path: "AppIcon.icns", directoryHint: .notDirectory)

let iconSpecs: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for spec in iconSpecs {
    let image = makeIcon(size: CGFloat(spec.size))
    try writePNG(image: image, to: iconsetURL.appending(path: spec.name, directoryHint: .notDirectory))
}

try writePNG(image: makeIcon(size: 1024), to: previewURL)

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
    "-c",
    "icns",
    iconsetURL.path(percentEncoded: false),
    "-o",
    icnsURL.path(percentEncoded: false),
]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw NSError(domain: "GenerateIcon", code: Int(process.terminationStatus))
}

try? fileManager.removeItem(at: iconsetURL)

print("Generated \(icnsURL.path(percentEncoded: false))")
print("Generated \(previewURL.path(percentEncoded: false))")

func makeIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let context = NSGraphicsContext.current?.cgContext else {
        fatalError("Could not create graphics context")
    }

    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let bounds = CGRect(origin: .zero, size: CGSize(width: size, height: size))
    drawAtmosphere(in: bounds, context: context)

    let ringRect = CGRect(
        x: size * 0.16,
        y: size * 0.18,
        width: size * 0.62,
        height: size * 0.62
    )

    drawPortalRing(in: ringRect, lineWidth: size * 0.075, context: context)
    drawLinkGlyph(at: CGPoint(x: size * 0.55, y: size * 0.84), size: size * 0.18)
    drawRoutingGlyph(at: CGPoint(x: ringRect.midX, y: ringRect.midY), size: size * 0.23)

    image.unlockFocus()
    return image
}

func drawAtmosphere(in bounds: CGRect, context: CGContext) {
    let size = bounds.width

    let backdrop = NSBezierPath(roundedRect: bounds, xRadius: size * 0.24, yRadius: size * 0.24)
    let backgroundGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.02, green: 0.05, blue: 0.14, alpha: 1),
        NSColor(calibratedRed: 0.03, green: 0.09, blue: 0.22, alpha: 1),
        NSColor(calibratedRed: 0.06, green: 0.18, blue: 0.30, alpha: 1),
    ])!
    backgroundGradient.draw(in: backdrop, angle: -34)

    let sideGlowPath = NSBezierPath(ovalIn: CGRect(
        x: size * 0.62,
        y: size * 0.44,
        width: size * 0.42,
        height: size * 0.50
    ))
    let sideGlowGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.30, green: 0.93, blue: 0.95, alpha: 0.20),
        .clear,
    ])!
    sideGlowGradient.draw(in: sideGlowPath, relativeCenterPosition: NSPoint(x: 0, y: 0))

    let portalGlowPath = NSBezierPath(ovalIn: CGRect(
        x: size * 0.10,
        y: size * 0.16,
        width: size * 0.74,
        height: size * 0.70
    ))
    let portalGlowGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.23, green: 0.70, blue: 1.0, alpha: 0.16),
        NSColor(calibratedRed: 1.0, green: 0.60, blue: 0.20, alpha: 0.08),
        .clear,
    ])!
    portalGlowGradient.draw(in: portalGlowPath, relativeCenterPosition: NSPoint(x: 0, y: 0))

    let sparkPoints: [(CGFloat, CGFloat, CGFloat, NSColor)] = [
        (0.22, 0.58, 0.010, NSColor(calibratedRed: 0.44, green: 0.90, blue: 1.0, alpha: 0.95)),
        (0.30, 0.68, 0.007, NSColor(calibratedRed: 0.71, green: 0.97, blue: 1.0, alpha: 0.72)),
        (0.83, 0.61, 0.011, NSColor(calibratedRed: 1.0, green: 0.76, blue: 0.44, alpha: 0.9)),
        (0.78, 0.47, 0.007, NSColor(calibratedRed: 1.0, green: 0.64, blue: 0.33, alpha: 0.62)),
        (0.74, 0.26, 0.009, NSColor(calibratedRed: 0.47, green: 0.92, blue: 1.0, alpha: 0.76)),
    ]

    for point in sparkPoints {
        let diameter = size * point.2
        let sparkRect = CGRect(
            x: size * point.0 - diameter / 2,
            y: size * point.1 - diameter / 2,
            width: diameter,
            height: diameter
        )
        let sparkPath = NSBezierPath(ovalIn: sparkRect)
        point.3.setFill()
        sparkPath.fill()
    }

    context.saveGState()
    context.setBlendMode(.screen)
    let floorPath = NSBezierPath()
    floorPath.move(to: CGPoint(x: size * 0.18, y: size * 0.24))
    floorPath.curve(
        to: CGPoint(x: size * 0.82, y: size * 0.20),
        controlPoint1: CGPoint(x: size * 0.34, y: size * 0.30),
        controlPoint2: CGPoint(x: size * 0.61, y: size * 0.13)
    )
    floorPath.line(to: CGPoint(x: size * 0.82, y: size * 0.12))
    floorPath.line(to: CGPoint(x: size * 0.18, y: size * 0.12))
    floorPath.close()
    NSColor(calibratedWhite: 1.0, alpha: 0.05).setFill()
    floorPath.fill()
    context.restoreGState()
}

func drawPortalRing(in rect: CGRect, lineWidth: CGFloat, context: CGContext) {
    let arcs: [(NSColor, CGFloat, CGFloat, CGFloat)] = [
        (NSColor(calibratedRed: 0.39, green: 0.95, blue: 1.0, alpha: 1), 128, 356, 0.48),
        (NSColor(calibratedRed: 0.34, green: 0.64, blue: 1.0, alpha: 1), 154, 20, 0.34),
        (NSColor(calibratedRed: 1.0, green: 0.63, blue: 0.22, alpha: 0.98), 206, 74, 0.40),
    ]

    for (color, start, end, glowOpacity) in arcs {
        let path = NSBezierPath()
        path.appendArc(
            withCenter: CGPoint(x: rect.midX, y: rect.midY),
            radius: rect.width / 2,
            startAngle: start,
            endAngle: end,
            clockwise: false
        )
        path.lineWidth = lineWidth

        context.saveGState()
        context.setShadow(offset: .zero, blur: rect.width * 0.07, color: color.withAlphaComponent(glowOpacity).cgColor)
        color.setStroke()
        path.stroke()
        context.restoreGState()
    }
}

func drawRoutingGlyph(at center: CGPoint, size: CGFloat) {
    let arrowFill = NSColor(calibratedWhite: 1.0, alpha: 0.98)
    let outline = NSColor(calibratedRed: 0.08, green: 0.15, blue: 0.33, alpha: 0.35)
    let head = size * 0.32
    let stemThickness = size * 0.12
    let stemLength = size * 0.44

    for angle in [0.0, 90.0, 180.0, 270.0] {
        var transform = AffineTransform(translationByX: center.x, byY: center.y)
        transform.rotate(byDegrees: angle)
        let path = NSBezierPath()
        path.move(to: transform.transform(CGPoint(x: -stemThickness * 0.5, y: stemThickness * 0.55)))
        path.line(to: transform.transform(CGPoint(x: -stemThickness * 0.5, y: stemLength)))
        path.line(to: transform.transform(CGPoint(x: -head * 0.70, y: stemLength)))
        path.line(to: transform.transform(CGPoint(x: 0, y: stemLength + head)))
        path.line(to: transform.transform(CGPoint(x: head * 0.70, y: stemLength)))
        path.line(to: transform.transform(CGPoint(x: stemThickness * 0.5, y: stemLength)))
        path.line(to: transform.transform(CGPoint(x: stemThickness * 0.5, y: stemThickness * 0.55)))
        path.close()
        arrowFill.setFill()
        path.fill()
        outline.setStroke()
        path.lineWidth = max(1.2, size * 0.018)
        path.stroke()
    }

    let hubRect = CGRect(
        x: center.x - size * 0.15,
        y: center.y - size * 0.15,
        width: size * 0.30,
        height: size * 0.30
    )
    let hub = NSBezierPath(ovalIn: hubRect)
    let hubGradient = NSGradient(colors: [
        NSColor(calibratedWhite: 1.0, alpha: 1),
        NSColor(calibratedRed: 0.88, green: 0.94, blue: 1.0, alpha: 1),
    ])!
    hubGradient.draw(in: hub, angle: 90)
    outline.setStroke()
    hub.lineWidth = max(1.4, size * 0.022)
    hub.stroke()
}

func drawLinkGlyph(at center: CGPoint, size: CGFloat) {
    let strokeColor = NSColor(calibratedWhite: 1.0, alpha: 0.96)
    let secondaryStroke = NSColor(calibratedWhite: 1.0, alpha: 0.72)
    let lineWidth = max(1.8, size * 0.14)

    func rotatedLoop(center: CGPoint, width: CGFloat, height: CGFloat, angle: CGFloat) -> NSBezierPath {
        let rect = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        let path = NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2)
        var transform = AffineTransform()
        transform.translate(x: center.x, y: center.y)
        transform.rotate(byDegrees: angle)
        transform.translate(x: -center.x, y: -center.y)
        path.transform(using: transform)
        return path
    }

    let leftCenter = CGPoint(x: center.x - size * 0.10, y: center.y + size * 0.02)
    let rightCenter = CGPoint(x: center.x + size * 0.12, y: center.y - size * 0.02)

    let leftLoop = rotatedLoop(center: leftCenter, width: size * 0.38, height: size * 0.20, angle: 40)
    let rightLoop = rotatedLoop(center: rightCenter, width: size * 0.38, height: size * 0.20, angle: 40)

    strokeColor.setStroke()
    leftLoop.lineWidth = lineWidth
    rightLoop.lineWidth = lineWidth
    leftLoop.stroke()
    rightLoop.stroke()

    let globeCenter = CGPoint(x: center.x - size * 0.33, y: center.y + size * 0.11)
    let globeRadius = size * 0.13
    let globe = NSBezierPath(ovalIn: CGRect(
        x: globeCenter.x - globeRadius,
        y: globeCenter.y - globeRadius,
        width: globeRadius * 2,
        height: globeRadius * 2
    ))
    secondaryStroke.setStroke()
    globe.lineWidth = max(1.2, size * 0.07)
    globe.stroke()

    for offset in [-0.48, 0.0, 0.48] {
        let meridian = NSBezierPath()
        meridian.move(to: CGPoint(x: globeCenter.x + globeRadius * offset, y: globeCenter.y - globeRadius))
        meridian.curve(
            to: CGPoint(x: globeCenter.x + globeRadius * offset, y: globeCenter.y + globeRadius),
            controlPoint1: CGPoint(x: globeCenter.x + globeRadius * (offset + 0.18), y: globeCenter.y - globeRadius * 0.42),
            controlPoint2: CGPoint(x: globeCenter.x + globeRadius * (offset - 0.18), y: globeCenter.y + globeRadius * 0.42)
        )
        meridian.lineWidth = max(1.0, size * 0.05)
        meridian.stroke()
    }
}

func writePNG(image: NSImage, to url: URL) throws {
    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "GenerateIcon", code: 2)
    }

    try pngData.write(to: url, options: .atomic)
}

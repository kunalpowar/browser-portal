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

    let bounds = CGRect(origin: .zero, size: CGSize(width: size, height: size))
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let cornerRadius = size * 0.23
    let backgroundPath = NSBezierPath(roundedRect: bounds.insetBy(dx: size * 0.035, dy: size * 0.035), xRadius: cornerRadius, yRadius: cornerRadius)
    context.saveGState()
    backgroundPath.addClip()

    let backgroundGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.08, green: 0.24, blue: 0.62, alpha: 1.0),
        NSColor(calibratedRed: 0.18, green: 0.62, blue: 0.88, alpha: 1.0),
        NSColor(calibratedRed: 0.96, green: 0.78, blue: 0.28, alpha: 1.0),
    ])!
    backgroundGradient.draw(in: backgroundPath, angle: -48)

    let glowRect = CGRect(x: size * 0.14, y: size * 0.56, width: size * 0.82, height: size * 0.5)
    let glowPath = NSBezierPath(ovalIn: glowRect)
    NSColor(calibratedWhite: 1.0, alpha: 0.16).setFill()
    glowPath.fill()

    let wavePath = NSBezierPath()
    wavePath.move(to: CGPoint(x: size * 0.08, y: size * 0.28))
    wavePath.curve(
        to: CGPoint(x: size * 0.93, y: size * 0.18),
        controlPoint1: CGPoint(x: size * 0.34, y: size * 0.38),
        controlPoint2: CGPoint(x: size * 0.62, y: size * 0.02)
    )
    wavePath.line(to: CGPoint(x: size * 0.93, y: size * 0.04))
    wavePath.line(to: CGPoint(x: size * 0.08, y: size * 0.04))
    wavePath.close()
    NSColor(calibratedWhite: 1.0, alpha: 0.10).setFill()
    wavePath.fill()
    context.restoreGState()

    let cardRect = CGRect(x: size * 0.17, y: size * 0.22, width: size * 0.66, height: size * 0.5)
    let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: size * 0.08, yRadius: size * 0.08)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -size * 0.03), blur: size * 0.05, color: NSColor(calibratedWhite: 0, alpha: 0.22).cgColor)
    NSColor(calibratedWhite: 0.98, alpha: 0.96).setFill()
    cardPath.fill()
    context.restoreGState()

    let topBarRect = CGRect(x: cardRect.minX, y: cardRect.maxY - size * 0.12, width: cardRect.width, height: size * 0.12)
    let topBarPath = NSBezierPath(roundedRect: topBarRect, xRadius: size * 0.08, yRadius: size * 0.08)
    NSColor(calibratedRed: 0.93, green: 0.95, blue: 0.98, alpha: 1.0).setFill()
    topBarPath.fill()

    for index in 0..<3 {
        let dotSize = size * 0.028
        let dotRect = CGRect(
            x: cardRect.minX + size * 0.05 + CGFloat(index) * size * 0.045,
            y: topBarRect.midY - dotSize / 2,
            width: dotSize,
            height: dotSize
        )
        let dotPath = NSBezierPath(ovalIn: dotRect)
        [
            NSColor(calibratedRed: 0.98, green: 0.41, blue: 0.39, alpha: 1),
            NSColor(calibratedRed: 0.98, green: 0.76, blue: 0.26, alpha: 1),
            NSColor(calibratedRed: 0.27, green: 0.84, blue: 0.47, alpha: 1),
        ][index].setFill()
        dotPath.fill()
    }

    let laneX = cardRect.minX + size * 0.11
    let laneWidth = size * 0.18
    let laneHeight = size * 0.22
    let laneY = cardRect.minY + size * 0.09
    for row in 0..<3 {
        let y = laneY + CGFloat(row) * size * 0.075
        let bar = NSBezierPath(roundedRect: CGRect(x: laneX, y: y, width: laneWidth, height: laneHeight * 0.16), xRadius: size * 0.02, yRadius: size * 0.02)
        NSColor(calibratedRed: 0.82, green: 0.88, blue: 0.95, alpha: 1).setFill()
        bar.fill()
    }

    let profileCenter = CGPoint(x: cardRect.maxX - size * 0.19, y: cardRect.minY + size * 0.20)
    let profileRadius = size * 0.11
    let profileCircle = NSBezierPath(ovalIn: CGRect(x: profileCenter.x - profileRadius, y: profileCenter.y - profileRadius, width: profileRadius * 2, height: profileRadius * 2))
    let profileGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.19, green: 0.76, blue: 0.65, alpha: 1),
        NSColor(calibratedRed: 0.11, green: 0.45, blue: 0.85, alpha: 1),
    ])!
    profileGradient.draw(in: profileCircle, angle: -45)

    let head = NSBezierPath(ovalIn: CGRect(
        x: profileCenter.x - size * 0.042,
        y: profileCenter.y + size * 0.01,
        width: size * 0.084,
        height: size * 0.084
    ))
    NSColor(calibratedWhite: 1.0, alpha: 0.92).setFill()
    head.fill()

    let body = NSBezierPath(roundedRect: CGRect(
        x: profileCenter.x - size * 0.073,
        y: profileCenter.y - size * 0.075,
        width: size * 0.146,
        height: size * 0.10
    ), xRadius: size * 0.05, yRadius: size * 0.05)
    NSColor(calibratedWhite: 1.0, alpha: 0.92).setFill()
    body.fill()

    let accentRing = NSBezierPath(ovalIn: CGRect(x: size * 0.61, y: size * 0.54, width: size * 0.20, height: size * 0.20))
    NSColor(calibratedWhite: 1.0, alpha: 0.20).setStroke()
    accentRing.lineWidth = size * 0.018
    accentRing.stroke()

    image.unlockFocus()
    return image
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

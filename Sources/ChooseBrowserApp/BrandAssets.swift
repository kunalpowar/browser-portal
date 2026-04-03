import AppKit
import SwiftUI

enum BrandAssets {
    static func headerMarkImage(size: CGFloat) -> NSImage {
        drawImage(size: size, style: .fullColor)
    }

    static func statusBarImage(size: CGFloat = 18) -> NSImage {
        let image = drawImage(size: size, style: .template)
        image.isTemplate = true
        return image
    }

    private enum Style {
        case fullColor
        case template
    }

    private static func drawImage(size: CGFloat, style: Style) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            fatalError("Could not create graphics context")
        }

        let bounds = CGRect(origin: .zero, size: CGSize(width: size, height: size))
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        switch style {
        case .fullColor:
            drawFullColorMark(in: bounds, context: context)
        case .template:
            drawTemplateMark(in: bounds)
        }

        image.unlockFocus()
        return image
    }

    private static func drawFullColorMark(in bounds: CGRect, context: CGContext) {
        let size = bounds.width
        let ringRect = CGRect(
            x: size * 0.16,
            y: size * 0.18,
            width: size * 0.62,
            height: size * 0.62
        )

        let glowPath = NSBezierPath(ovalIn: CGRect(
            x: ringRect.minX - size * 0.04,
            y: ringRect.minY - size * 0.03,
            width: ringRect.width + size * 0.10,
            height: ringRect.height + size * 0.08
        ))
        let glowGradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.15, green: 0.56, blue: 1.0, alpha: 0.16),
            NSColor(calibratedRed: 0.99, green: 0.56, blue: 0.17, alpha: 0.08),
            .clear,
        ])!
        glowGradient.draw(in: glowPath, relativeCenterPosition: NSPoint(x: 0, y: 0))

        drawPortalRing(in: ringRect, lineWidth: size * 0.075, context: context, fullColor: true)
        drawLinkGlyph(at: CGPoint(x: size * 0.55, y: size * 0.84), size: size * 0.18, fullColor: true)
        drawRoutingGlyph(at: CGPoint(x: ringRect.midX, y: ringRect.midY), size: size * 0.23, fullColor: true)
    }

    private static func drawTemplateMark(in bounds: CGRect) {
        let size = bounds.width
        let color = NSColor.labelColor

        let ringRect = CGRect(
            x: size * 0.12,
            y: size * 0.14,
            width: size * 0.64,
            height: size * 0.64
        )
        drawPortalRingTemplate(in: ringRect, lineWidth: max(1.5, size * 0.11), color: color)
        drawRoutingGlyphTemplate(at: CGPoint(x: ringRect.midX, y: ringRect.midY), size: size * 0.25, color: color)
        drawLinkGlyphTemplate(at: CGPoint(x: size * 0.56, y: size * 0.82), size: size * 0.18, color: color)
    }

    private static func drawPortalRing(in rect: CGRect, lineWidth: CGFloat, context: CGContext, fullColor: Bool) {
        let arcs: [(NSColor, CGFloat, CGFloat)] = [
            (NSColor(calibratedRed: 0.37, green: 0.94, blue: 1.0, alpha: 1), 126, 358),
            (NSColor(calibratedRed: 0.31, green: 0.60, blue: 1.0, alpha: 0.95), 154, 26),
            (NSColor(calibratedRed: 1.0, green: 0.67, blue: 0.29, alpha: 0.92), 212, 72),
        ]

        for (color, start, end) in arcs {
            let path = NSBezierPath()
            path.appendArc(
                withCenter: CGPoint(x: rect.midX, y: rect.midY),
                radius: rect.width / 2,
                startAngle: start,
                endAngle: end,
                clockwise: false
            )
            path.lineWidth = lineWidth
            if fullColor {
                context.saveGState()
                context.setShadow(
                    offset: .zero,
                    blur: rect.width * 0.06,
                    color: color.withAlphaComponent(0.45).cgColor
                )
                color.setStroke()
                path.stroke()
                context.restoreGState()
            } else {
                color.setStroke()
                path.stroke()
            }
        }
    }

    private static func drawPortalRingTemplate(in rect: CGRect, lineWidth: CGFloat, color: NSColor) {
        let path = NSBezierPath()
        path.appendArc(
            withCenter: CGPoint(x: rect.midX, y: rect.midY),
            radius: rect.width / 2,
            startAngle: 124,
            endAngle: 392,
            clockwise: false
        )
        path.lineWidth = lineWidth
        color.setStroke()
        path.stroke()
    }

    private static func drawRoutingGlyph(at center: CGPoint, size: CGFloat, fullColor: Bool) {
        let arrowColor = NSColor(calibratedWhite: 1.0, alpha: fullColor ? 0.98 : 1.0)
        let arrowStroke = size * 0.12
        let head = size * 0.28
        let stem = size * 0.44

        for angle in [0.0, 90.0, 180.0, 270.0] {
            var transform = AffineTransform(translationByX: center.x, byY: center.y)
            transform.rotate(byDegrees: angle)
            let path = NSBezierPath()
            path.move(to: transform.transform(CGPoint(x: -arrowStroke * 0.5, y: stem * 0.10)))
            path.line(to: transform.transform(CGPoint(x: -arrowStroke * 0.5, y: stem)))
            path.line(to: transform.transform(CGPoint(x: -head * 0.70, y: stem)))
            path.line(to: transform.transform(CGPoint(x: 0, y: stem + head)))
            path.line(to: transform.transform(CGPoint(x: head * 0.70, y: stem)))
            path.line(to: transform.transform(CGPoint(x: arrowStroke * 0.5, y: stem)))
            path.line(to: transform.transform(CGPoint(x: arrowStroke * 0.5, y: stem * 0.10)))
            path.close()
            arrowColor.setFill()
            path.fill()
        }

        let hub = NSBezierPath(ovalIn: CGRect(
            x: center.x - size * 0.14,
            y: center.y - size * 0.14,
            width: size * 0.28,
            height: size * 0.28
        ))
        if fullColor {
            let hubGradient = NSGradient(colors: [
                NSColor(calibratedWhite: 1.0, alpha: 1),
                NSColor(calibratedRed: 0.88, green: 0.94, blue: 1.0, alpha: 1),
            ])!
            hubGradient.draw(in: hub, angle: 90)
        } else {
            arrowColor.setFill()
            hub.fill()
        }
    }

    private static func drawRoutingGlyphTemplate(at center: CGPoint, size: CGFloat, color: NSColor) {
        drawRoutingGlyph(at: center, size: size, fullColor: false)
    }

    private static func drawLinkGlyph(at center: CGPoint, size: CGFloat, fullColor: Bool) {
        let strokeColor = fullColor
            ? NSColor(calibratedWhite: 1.0, alpha: 0.96)
            : NSColor.labelColor
        let lineWidth = max(1.4, size * 0.14)

        let firstLoop = NSBezierPath(roundedRect: CGRect(
            x: center.x - size * 0.34,
            y: center.y - size * 0.12,
            width: size * 0.40,
            height: size * 0.22
        ), xRadius: size * 0.16, yRadius: size * 0.16)
        let secondLoop = NSBezierPath(roundedRect: CGRect(
            x: center.x - size * 0.02,
            y: center.y - size * 0.02,
            width: size * 0.40,
            height: size * 0.22
        ), xRadius: size * 0.16, yRadius: size * 0.16)

        let transformOne = AffineTransform(translationByX: center.x, byY: center.y)
        var rotationOne = AffineTransform()
        rotationOne.rotate(byDegrees: 36)
        firstLoop.transform(using: rotationOne)
        secondLoop.transform(using: rotationOne)
        firstLoop.transform(using: transformOne)
        secondLoop.transform(using: transformOne)

        strokeColor.setStroke()
        firstLoop.lineWidth = lineWidth
        secondLoop.lineWidth = lineWidth
        firstLoop.stroke()
        secondLoop.stroke()

        if fullColor {
            let globePath = NSBezierPath()
            let globeCenter = CGPoint(x: center.x - size * 0.43, y: center.y + size * 0.16)
            let globeRadius = size * 0.13
            globePath.appendArc(withCenter: globeCenter, radius: globeRadius, startAngle: 0, endAngle: 360)
            globePath.lineWidth = max(1.2, size * 0.08)
            strokeColor.withAlphaComponent(0.92).setStroke()
            globePath.stroke()

            for scale in [0.55, 0.0, -0.55] {
                let meridian = NSBezierPath()
                meridian.move(to: CGPoint(x: globeCenter.x + globeRadius * CGFloat(scale), y: globeCenter.y - globeRadius))
                meridian.curve(
                    to: CGPoint(x: globeCenter.x + globeRadius * CGFloat(scale), y: globeCenter.y + globeRadius),
                    controlPoint1: CGPoint(x: globeCenter.x + globeRadius * CGFloat(scale + 0.20), y: globeCenter.y - globeRadius * 0.46),
                    controlPoint2: CGPoint(x: globeCenter.x + globeRadius * CGFloat(scale - 0.20), y: globeCenter.y + globeRadius * 0.46)
                )
                meridian.lineWidth = max(1.0, size * 0.05)
                strokeColor.withAlphaComponent(0.7).setStroke()
                meridian.stroke()
            }
        }
    }

    private static func drawLinkGlyphTemplate(at center: CGPoint, size: CGFloat, color: NSColor) {
        let lineWidth = max(1.2, size * 0.14)
        let path = NSBezierPath()
        path.move(to: CGPoint(x: center.x - size * 0.14, y: center.y + size * 0.01))
        path.curve(
            to: CGPoint(x: center.x + size * 0.16, y: center.y + size * 0.01),
            controlPoint1: CGPoint(x: center.x - size * 0.05, y: center.y + size * 0.18),
            controlPoint2: CGPoint(x: center.x + size * 0.08, y: center.y - size * 0.12)
        )
        path.move(to: CGPoint(x: center.x - size * 0.04, y: center.y - size * 0.07))
        path.curve(
            to: CGPoint(x: center.x + size * 0.26, y: center.y - size * 0.07),
            controlPoint1: CGPoint(x: center.x + size * 0.05, y: center.y + size * 0.10),
            controlPoint2: CGPoint(x: center.x + size * 0.18, y: center.y - size * 0.20)
        )
        path.lineWidth = lineWidth
        color.setStroke()
        path.stroke()
    }
}

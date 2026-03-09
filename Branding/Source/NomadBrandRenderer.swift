import AppKit
import Foundation

enum RenderError: Error {
    case usage
    case bitmapCreationFailed
    case pngEncodingFailed
}

struct Palette {
    static let sand = NSColor(hex: 0xF0C987)
    static let sandDeep = NSColor(hex: 0xA56E17)
    static let teal = NSColor(hex: 0x0E8C92)
    static let tealBright = NSColor(hex: 0x5FC3C8)
    static let coral = NSColor(hex: 0xC85C34)
    static let coralBright = NSColor(hex: 0xF68B63)
    static let cream = NSColor(hex: 0xF6EEDD)
    static let seafoam = NSColor(hex: 0xE7F4F2)
    static let shell = NSColor(hex: 0xFCEBDD)
    static let midnight = NSColor(hex: 0x101A24)
    static let deepSea = NSColor(hex: 0x17303A)
    static let slate = NSColor(hex: 0x425663)
    static let whiteStroke = NSColor.white.withAlphaComponent(0.76)
}

struct BrandRenderer {
    let outputDirectory: URL

    func renderAll() throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        try renderPNG(
            size: CGSize(width: 1024, height: 1024),
            scale: 1,
            to: outputDirectory.appendingPathComponent("NomadDashboard-icon-1024.png"),
            draw: drawAppIcon
        )

        try renderPNG(
            size: CGSize(width: 1024, height: 1024),
            scale: 1,
            to: outputDirectory.appendingPathComponent("NomadDashboard-symbol-mark.png"),
            draw: drawStandaloneMark
        )

        try renderPDF(
            size: CGSize(width: 1024, height: 1024),
            to: outputDirectory.appendingPathComponent("NomadDashboard-symbol-mark.pdf"),
            draw: drawStandaloneMark
        )

        try renderPNG(
            size: CGSize(width: 1600, height: 560),
            scale: 1,
            to: outputDirectory.appendingPathComponent("NomadDashboard-logo-lockup.png"),
            draw: drawLogoLockup
        )

        try renderPDF(
            size: CGSize(width: 1600, height: 560),
            to: outputDirectory.appendingPathComponent("NomadDashboard-logo-lockup.pdf"),
            draw: drawLogoLockup
        )

        try renderPNG(
            size: CGSize(width: 660, height: 420),
            scale: 1,
            to: outputDirectory.appendingPathComponent("NomadDashboard-dmg-background.png"),
            draw: drawDMGBackground
        )

        try renderPNG(
            size: CGSize(width: 660, height: 420),
            scale: 2,
            to: outputDirectory.appendingPathComponent("NomadDashboard-dmg-background@2x.png"),
            draw: drawDMGBackground
        )
    }

    private func renderPNG(
        size: CGSize,
        scale: CGFloat,
        to url: URL,
        draw: @escaping (CGRect) -> Void
    ) throws {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw RenderError.bitmapCreationFailed
        }

        bitmap.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        draw(CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw RenderError.pngEncodingFailed
        }

        try data.write(to: url)
    }

    private func renderPDF(
        size: CGSize,
        to url: URL,
        draw: @escaping (CGRect) -> Void
    ) throws {
        let view = RenderView(frame: CGRect(origin: .zero, size: size), drawHandler: draw)
        let data = view.dataWithPDF(inside: view.bounds)
        try data.write(to: url)
    }

    private func drawAppIcon(in rect: CGRect) {
        NSColor.clear.setFill()
        rect.fill()

        let tileRect = rect.insetBy(dx: 44, dy: 44)
        let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: 225, yRadius: 225)

        let shadow = NSShadow()
        shadow.shadowColor = Palette.midnight.withAlphaComponent(0.32)
        shadow.shadowBlurRadius = 38
        shadow.shadowOffset = CGSize(width: 0, height: -18)

        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        Palette.midnight.withAlphaComponent(0.82).setFill()
        tilePath.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        tilePath.addClip()
        NSGradient(colors: [
            Palette.midnight,
            Palette.deepSea,
            Palette.teal.withAlphaComponent(0.72)
        ])?.draw(in: tileRect, angle: 52)

        NSGradient(colors: [
            Palette.coralBright.withAlphaComponent(0.38),
            Palette.coral.withAlphaComponent(0.03)
        ])?.draw(
            fromCenter: CGPoint(x: tileRect.minX + tileRect.width * 0.24, y: tileRect.maxY - tileRect.height * 0.21),
            radius: 30,
            toCenter: CGPoint(x: tileRect.minX + tileRect.width * 0.24, y: tileRect.maxY - tileRect.height * 0.21),
            radius: tileRect.width * 0.55,
            options: []
        )

        NSGradient(colors: [
            Palette.tealBright.withAlphaComponent(0.32),
            Palette.teal.withAlphaComponent(0.02)
        ])?.draw(
            fromCenter: CGPoint(x: tileRect.maxX - tileRect.width * 0.18, y: tileRect.minY + tileRect.height * 0.24),
            radius: 24,
            toCenter: CGPoint(x: tileRect.maxX - tileRect.width * 0.18, y: tileRect.minY + tileRect.height * 0.24),
            radius: tileRect.width * 0.5,
            options: []
        )

        let sheenRect = CGRect(
            x: tileRect.minX + tileRect.width * 0.08,
            y: tileRect.minY + tileRect.height * 0.56,
            width: tileRect.width * 0.84,
            height: tileRect.height * 0.28
        )
        let sheenPath = NSBezierPath(roundedRect: sheenRect, xRadius: sheenRect.height / 2, yRadius: sheenRect.height / 2)
        NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.16),
            NSColor.white.withAlphaComponent(0.0)
        ])?.draw(in: sheenPath, angle: -90)

        NSGraphicsContext.restoreGraphicsState()

        Palette.whiteStroke.setStroke()
        tilePath.lineWidth = 6
        tilePath.stroke()

        drawInstrumentGlyph(in: tileRect.insetBy(dx: 148, dy: 148), style: .darkTile)
    }

    private func drawStandaloneMark(in rect: CGRect) {
        NSColor.clear.setFill()
        rect.fill()

        let discRect = rect.insetBy(dx: rect.width * 0.12, dy: rect.height * 0.12)
        let discPath = NSBezierPath(ovalIn: discRect)

        let shadow = NSShadow()
        shadow.shadowColor = Palette.midnight.withAlphaComponent(0.18)
        shadow.shadowBlurRadius = 30
        shadow.shadowOffset = CGSize(width: 0, height: -10)

        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        Palette.cream.setFill()
        discPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        Palette.deepSea.withAlphaComponent(0.14).setStroke()
        discPath.lineWidth = 10
        discPath.stroke()

        let haloRect = discRect.insetBy(dx: discRect.width * 0.08, dy: discRect.height * 0.08)
        let haloPath = NSBezierPath(ovalIn: haloRect)
        Palette.teal.withAlphaComponent(0.08).setFill()
        haloPath.fill()

        drawInstrumentGlyph(in: discRect.insetBy(dx: discRect.width * 0.18, dy: discRect.height * 0.18), style: .lightMark)
    }

    private func drawLogoLockup(in rect: CGRect) {
        NSColor.clear.setFill()
        rect.fill()

        let symbolRect = CGRect(x: 24, y: 76, width: 408, height: 408)
        drawStandaloneMark(in: symbolRect)

        let titleY = rect.midY + 36
        let title = NSMutableAttributedString()
        title.append(
            NSAttributedString(
                string: "Nomad ",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 112, weight: .bold),
                    .foregroundColor: Palette.deepSea
                ]
            )
        )
        title.append(
            NSAttributedString(
                string: "Dashboard",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 112, weight: .semibold),
                    .foregroundColor: Palette.slate
                ]
            )
        )
        title.draw(at: CGPoint(x: 474, y: titleY))

        let subtitle = NSAttributedString(
            string: "Travel-ready system telemetry",
            attributes: [
                .font: NSFont.systemFont(ofSize: 38, weight: .medium),
                .foregroundColor: Palette.sandDeep
            ]
        )
        subtitle.draw(at: CGPoint(x: 482, y: rect.midY - 32))

        let rule = NSBezierPath()
        rule.move(to: CGPoint(x: 484, y: rect.midY - 54))
        rule.line(to: CGPoint(x: 1110, y: rect.midY - 54))
        rule.lineWidth = 6
        rule.lineCapStyle = .round
        Palette.teal.withAlphaComponent(0.32).setStroke()
        rule.stroke()
    }

    private func drawDMGBackground(in rect: CGRect) {
        let backgroundGradient = NSGradient(colors: [
            Palette.cream,
            Palette.seafoam,
            Palette.shell
        ])
        backgroundGradient?.draw(in: rect, angle: 0)

        let topGlow = NSBezierPath(ovalIn: CGRect(x: rect.minX - 90, y: rect.maxY - 210, width: 320, height: 220))
        Palette.sand.withAlphaComponent(0.15).setFill()
        topGlow.fill()

        let rightGlow = NSBezierPath(ovalIn: CGRect(x: rect.maxX - 240, y: rect.minY + 36, width: 240, height: 240))
        Palette.tealBright.withAlphaComponent(0.1).setFill()
        rightGlow.fill()

        let insetRect = rect.insetBy(dx: 18, dy: 18)
        let framePath = NSBezierPath(roundedRect: insetRect, xRadius: 26, yRadius: 26)
        Palette.whiteStroke.setFill()
        framePath.fill()
        Palette.deepSea.withAlphaComponent(0.08).setStroke()
        framePath.lineWidth = 2
        framePath.stroke()

        let bannerRect = CGRect(x: 36, y: rect.maxY - 106, width: rect.width - 72, height: 62)
        let bannerPath = NSBezierPath(roundedRect: bannerRect, xRadius: 18, yRadius: 18)
        NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.76),
            NSColor.white.withAlphaComponent(0.42)
        ])?.draw(in: bannerPath, angle: -90)

        drawCompactLockup(at: CGPoint(x: 52, y: rect.maxY - 98))

        let headline = NSAttributedString(
            string: "Drag to install",
            attributes: [
                .font: NSFont.systemFont(ofSize: 27, weight: .semibold),
                .foregroundColor: Palette.deepSea.withAlphaComponent(0.9)
            ]
        )
        headline.draw(at: CGPoint(x: 374, y: rect.maxY - 86))

        let note = NSAttributedString(
            string: "Drop Nomad Dashboard into Applications",
            attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .medium),
                .foregroundColor: Palette.slate.withAlphaComponent(0.8)
            ]
        )
        note.draw(at: CGPoint(x: 316, y: rect.maxY - 115))

        let appSpotlight = NSBezierPath(ovalIn: CGRect(x: 76, y: 118, width: 164, height: 164))
        Palette.whiteStroke.setFill()
        appSpotlight.fill()
        Palette.deepSea.withAlphaComponent(0.08).setStroke()
        appSpotlight.lineWidth = 2
        appSpotlight.stroke()

        let applicationsSpotlight = NSBezierPath(ovalIn: CGRect(x: 420, y: 118, width: 164, height: 164))
        Palette.whiteStroke.setFill()
        applicationsSpotlight.fill()
        Palette.deepSea.withAlphaComponent(0.08).setStroke()
        applicationsSpotlight.lineWidth = 2
        applicationsSpotlight.stroke()

        let arrowUnderlay = NSBezierPath()
        arrowUnderlay.move(to: CGPoint(x: 216, y: 200))
        arrowUnderlay.curve(
            to: CGPoint(x: 442, y: 202),
            controlPoint1: CGPoint(x: 272, y: 230),
            controlPoint2: CGPoint(x: 372, y: 228)
        )
        arrowUnderlay.lineWidth = 28
        arrowUnderlay.lineCapStyle = .round
        arrowUnderlay.lineJoinStyle = .round
        NSColor.white.withAlphaComponent(0.85).setStroke()
        arrowUnderlay.stroke()

        let arrow = NSBezierPath()
        arrow.move(to: CGPoint(x: 220, y: 200))
        arrow.curve(
            to: CGPoint(x: 448, y: 202),
            controlPoint1: CGPoint(x: 272, y: 230),
            controlPoint2: CGPoint(x: 374, y: 228)
        )
        arrow.lineWidth = 14
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        Palette.coral.setStroke()
        arrow.stroke()

        let arrowHead = NSBezierPath()
        arrowHead.move(to: CGPoint(x: 444, y: 224))
        arrowHead.line(to: CGPoint(x: 490, y: 202))
        arrowHead.line(to: CGPoint(x: 444, y: 178))
        arrowHead.lineJoinStyle = .round
        arrowHead.lineCapStyle = .round
        arrowHead.lineWidth = 14
        Palette.coral.setStroke()
        arrowHead.stroke()

        let caption = NSAttributedString(
            string: "Drop here",
            attributes: [
                .font: NSFont.systemFont(ofSize: 17, weight: .semibold),
                .foregroundColor: Palette.sandDeep
            ]
        )
        caption.draw(at: CGPoint(x: 434, y: 146))

        let dashedPath = NSBezierPath()
        dashedPath.move(to: CGPoint(x: 150, y: 284))
        dashedPath.line(to: CGPoint(x: 510, y: 284))
        dashedPath.lineWidth = 3
        dashedPath.setLineDash([7, 8], count: 2, phase: 0)
        dashedPath.lineCapStyle = .round
        Palette.teal.withAlphaComponent(0.18).setStroke()
        dashedPath.stroke()
    }

    private func drawCompactLockup(at origin: CGPoint) {
        let markRect = CGRect(x: origin.x, y: origin.y + 4, width: 34, height: 34)
        drawStandaloneMark(in: markRect)

        let name = NSAttributedString(
            string: "Nomad Dashboard",
            attributes: [
                .font: NSFont.systemFont(ofSize: 22, weight: .bold),
                .foregroundColor: Palette.deepSea
            ]
        )
        name.draw(at: CGPoint(x: origin.x + 48, y: origin.y + 9))
    }

    private func drawInstrumentGlyph(in rect: CGRect, style: GlyphStyle) {
        let cgContext = NSGraphicsContext.current?.cgContext
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.5
        let outerRingWidth = radius * 0.14
        let secondaryRingWidth = radius * 0.04

        let ringColor: NSColor
        let crosshairColor: NSColor
        let haloColor: NSColor
        let detailColor: NSColor

        switch style {
        case .darkTile:
            ringColor = Palette.tealBright
            crosshairColor = NSColor.white.withAlphaComponent(0.82)
            haloColor = Palette.sand.withAlphaComponent(0.16)
            detailColor = NSColor.white.withAlphaComponent(0.22)
        case .lightMark:
            ringColor = Palette.teal
            crosshairColor = Palette.deepSea.withAlphaComponent(0.9)
            haloColor = Palette.sand.withAlphaComponent(0.22)
            detailColor = Palette.deepSea.withAlphaComponent(0.14)
        }

        let haloPath = NSBezierPath(ovalIn: rect.insetBy(dx: radius * 0.02, dy: radius * 0.02))
        haloColor.setFill()
        haloPath.fill()

        let outerRing = NSBezierPath(ovalIn: rect.insetBy(dx: outerRingWidth / 2, dy: outerRingWidth / 2))
        outerRing.lineWidth = outerRingWidth
        ringColor.setStroke()
        outerRing.stroke()

        let secondaryRect = rect.insetBy(dx: radius * 0.16, dy: radius * 0.16)
        let secondaryRing = NSBezierPath(ovalIn: secondaryRect)
        secondaryRing.lineWidth = secondaryRingWidth
        detailColor.setStroke()
        secondaryRing.stroke()

        let innerRect = rect.insetBy(dx: radius * 0.3, dy: radius * 0.3)
        let innerRing = NSBezierPath(ovalIn: innerRect)
        innerRing.lineWidth = secondaryRingWidth
        detailColor.setStroke()
        innerRing.stroke()

        let vertical = NSBezierPath()
        vertical.move(to: CGPoint(x: center.x, y: rect.minY + radius * 0.12))
        vertical.line(to: CGPoint(x: center.x, y: rect.maxY - radius * 0.12))
        vertical.lineWidth = radius * 0.05
        vertical.lineCapStyle = .round
        crosshairColor.withAlphaComponent(0.7).setStroke()
        vertical.stroke()

        let horizontal = NSBezierPath()
        horizontal.move(to: CGPoint(x: rect.minX + radius * 0.12, y: center.y))
        horizontal.line(to: CGPoint(x: rect.maxX - radius * 0.12, y: center.y))
        horizontal.lineWidth = radius * 0.05
        horizontal.lineCapStyle = .round
        crosshairColor.withAlphaComponent(0.7).setStroke()
        horizontal.stroke()

        let orbitalArc = NSBezierPath()
        orbitalArc.appendArc(
            withCenter: center,
            radius: radius * 0.92,
            startAngle: 200,
            endAngle: 320,
            clockwise: false
        )
        orbitalArc.lineWidth = radius * 0.08
        orbitalArc.lineCapStyle = .round
        Palette.sand.withAlphaComponent(style == .darkTile ? 0.82 : 0.72).setStroke()
        orbitalArc.stroke()

        let orbitalDotCenter = point(onCircleCenteredAt: center, radius: radius * 0.92, angleDegrees: 320)
        let orbitalDot = NSBezierPath(ovalIn: CGRect(x: orbitalDotCenter.x - radius * 0.09, y: orbitalDotCenter.y - radius * 0.09, width: radius * 0.18, height: radius * 0.18))
        Palette.coralBright.setFill()
        orbitalDot.fill()

        cgContext?.saveGState()
        cgContext?.translateBy(x: center.x, y: center.y)
        cgContext?.rotate(by: 35 * (.pi / 180))

        let topNeedle = NSBezierPath()
        topNeedle.move(to: CGPoint(x: 0, y: radius * 0.98))
        topNeedle.line(to: CGPoint(x: radius * 0.16, y: 0))
        topNeedle.line(to: CGPoint(x: -radius * 0.16, y: 0))
        topNeedle.close()
        Palette.sand.setFill()
        topNeedle.fill()

        let bottomNeedle = NSBezierPath()
        bottomNeedle.move(to: CGPoint(x: 0, y: -radius * 0.68))
        bottomNeedle.line(to: CGPoint(x: radius * 0.18, y: 0))
        bottomNeedle.line(to: CGPoint(x: -radius * 0.18, y: 0))
        bottomNeedle.close()
        Palette.coral.setFill()
        bottomNeedle.fill()

        let needleStroke = NSBezierPath()
        needleStroke.move(to: CGPoint(x: 0, y: radius * 0.98))
        needleStroke.line(to: CGPoint(x: radius * 0.18, y: 0))
        needleStroke.line(to: CGPoint(x: 0, y: -radius * 0.68))
        needleStroke.line(to: CGPoint(x: -radius * 0.18, y: 0))
        needleStroke.close()
        Palette.deepSea.withAlphaComponent(style == .darkTile ? 0.32 : 0.14).setStroke()
        needleStroke.lineWidth = radius * 0.03
        needleStroke.stroke()
        cgContext?.restoreGState()

        let centerDot = NSBezierPath(ovalIn: CGRect(x: center.x - radius * 0.12, y: center.y - radius * 0.12, width: radius * 0.24, height: radius * 0.24))
        Palette.cream.setFill()
        centerDot.fill()
        Palette.deepSea.withAlphaComponent(0.14).setStroke()
        centerDot.lineWidth = radius * 0.03
        centerDot.stroke()
    }

    private func point(onCircleCenteredAt center: CGPoint, radius: CGFloat, angleDegrees: CGFloat) -> CGPoint {
        let radians = angleDegrees * (.pi / 180)
        return CGPoint(
            x: center.x + cos(radians) * radius,
            y: center.y + sin(radians) * radius
        )
    }
}

enum GlyphStyle {
    case darkTile
    case lightMark
}

final class RenderView: NSView {
    private let drawHandler: (CGRect) -> Void

    init(frame: CGRect, drawHandler: @escaping (CGRect) -> Void) {
        self.drawHandler = drawHandler
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        drawHandler(bounds)
    }
}

private extension NSColor {
    convenience init(hex: UInt64, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

}

private extension CGRect {
    func fill() {
        NSBezierPath(rect: self).fill()
    }
}

func parseOutputDirectory() throws -> URL {
    let arguments = CommandLine.arguments
    guard let outputIndex = arguments.firstIndex(of: "--output-dir"),
          arguments.indices.contains(outputIndex + 1) else {
        throw RenderError.usage
    }

    return URL(fileURLWithPath: arguments[outputIndex + 1], isDirectory: true)
}

do {
    let outputDirectory = try parseOutputDirectory()
    try BrandRenderer(outputDirectory: outputDirectory).renderAll()
} catch RenderError.usage {
    fputs("Usage: swift Branding/Source/NomadBrandRenderer.swift --output-dir <directory>\n", stderr)
    exit(1)
} catch {
    fputs("Brand rendering failed: \(error)\n", stderr)
    exit(1)
}

import AppKit

/// Draws a document. Used by the on-screen canvas and by the exporter, so both always match.
@MainActor
enum AnnotationRenderer {
    /// Draws into `ctx`, which must use image points with a top-left origin.
    static func draw(_ document: AnnotationDocument, in ctx: CGContext, hiding hiddenID: UUID? = nil) {
        let bounds: CGRect = CGRect(origin: .zero, size: document.pointSize)
        drawImage(document.baseImage, in: bounds, ctx: ctx)

        for annotation in document.annotations where annotation.id != hiddenID {
            draw(annotation, document: document, bounds: bounds, ctx: ctx)
        }
    }

    /// Renders the document at full pixel resolution.
    static func flatten(_ document: AnnotationDocument) -> CGImage? {
        let width: Int = document.baseImage.width
        let height: Int = document.baseImage.height
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: document.scale, y: -document.scale)
        ctx.interpolationQuality = .high
        draw(document, in: ctx)
        return ctx.makeImage()
    }

    static func draw(_ annotation: Annotation, document: AnnotationDocument, bounds: CGRect, ctx: CGContext) {
        let color: CGColor = annotation.color.cgColor
        let width: CGFloat = annotation.width
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)
        ctx.setLineWidth(width)

        switch annotation.kind {
        case .arrow(let start, let end):
            drawArrow(from: start, to: end, width: width, ctx: ctx)

        case .rectangle(let rect):
            ctx.stroke(rect.insetBy(dx: width / 2, dy: width / 2).standardized)

        case .ellipse(let rect):
            ctx.strokeEllipse(in: rect.insetBy(dx: width / 2, dy: width / 2).standardized)

        case .line(let start, let end):
            ctx.move(to: start)
            ctx.addLine(to: end)
            ctx.strokePath()

        case .pen(let points):
            ctx.addPath(smoothPath(points))
            ctx.strokePath()

        case .highlighter(let points):
            ctx.setBlendMode(.multiply)
            ctx.setStrokeColor(annotation.color.withAlphaComponent(0.45).cgColor)
            ctx.setLineWidth(width * 3 + 10)
            ctx.setLineCap(.square)
            ctx.addPath(smoothPath(points))
            ctx.strokePath()

        case .blur(let rect):
            guard let pixelated = document.pixelatedImage else { return }
            ctx.clip(to: rect.standardized)
            drawImage(pixelated, in: bounds, ctx: ctx)

        case .text(let string, let origin, let fontSize):
            drawText(string, at: origin, fontSize: fontSize, color: annotation.color, ctx: ctx)

        case .number(let value, let center):
            let radius: CGFloat = Annotation.badgeRadius(for: width)
            let circle: CGRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: NSColor.black.withAlphaComponent(0.35).cgColor)
            ctx.fillEllipse(in: circle)
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            let label: NSAttributedString = NSAttributedString(string: "\(value)", attributes: [
                .font: NSFont.systemFont(ofSize: radius * 1.1, weight: .bold),
                .foregroundColor: contrastingTextColor(for: annotation.color),
            ])
            let size: CGSize = label.size()
            drawAttributed(label, at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), ctx: ctx)
        }
    }

    /// Size of a text annotation's box, used for hit testing and editing.
    static func textSize(_ string: String, fontSize: CGFloat) -> CGSize {
        let attributed: NSAttributedString = NSAttributedString(string: string.isEmpty ? " " : string,
                                                                attributes: [.font: Annotation.textFont(size: fontSize)])
        return attributed.size()
    }

    // MARK: - Helpers

    private static func drawImage(_ image: CGImage, in rect: CGRect, ctx: CGContext) {
        // The context is flipped (top-left origin); CGImages draw bottom-up, so flip locally.
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    private static func drawArrow(from start: CGPoint, to end: CGPoint, width: CGFloat, ctx: CGContext) {
        let dx: CGFloat = end.x - start.x
        let dy: CGFloat = end.y - start.y
        let length: CGFloat = hypot(dx, dy)
        guard length > 1 else { return }
        let headLength: CGFloat = min(max(14, width * 4.5), length)
        let headWidth: CGFloat = headLength * 0.85
        let ux: CGFloat = dx / length
        let uy: CGFloat = dy / length
        let base: CGPoint = CGPoint(x: end.x - ux * headLength, y: end.y - uy * headLength)

        ctx.move(to: start)
        ctx.addLine(to: CGPoint(x: end.x - ux * headLength * 0.6, y: end.y - uy * headLength * 0.6))
        ctx.strokePath()

        let left: CGPoint = CGPoint(x: base.x - uy * headWidth / 2, y: base.y + ux * headWidth / 2)
        let right: CGPoint = CGPoint(x: base.x + uy * headWidth / 2, y: base.y - ux * headWidth / 2)
        ctx.move(to: end)
        ctx.addLine(to: left)
        ctx.addLine(to: right)
        ctx.closePath()
        ctx.fillPath()
    }

    private static func smoothPath(_ points: [CGPoint]) -> CGPath {
        let path: CGMutablePath = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        if points.count == 1 {
            path.addLine(to: first)
            return path
        }
        for i in 1..<points.count {
            let previous: CGPoint = points[i - 1]
            let current: CGPoint = points[i]
            let mid: CGPoint = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            path.addQuadCurve(to: mid, control: previous)
        }
        path.addLine(to: points[points.count - 1])
        return path
    }

    private static func drawText(_ string: String, at origin: CGPoint, fontSize: CGFloat, color: NSColor, ctx: CGContext) {
        let shadow: NSShadow = NSShadow()
        shadow.shadowColor = contrastingTextColor(for: color).withAlphaComponent(0.6)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = .zero
        let attributed: NSAttributedString = NSAttributedString(string: string, attributes: [
            .font: Annotation.textFont(size: fontSize),
            .foregroundColor: color,
            .shadow: shadow,
        ])
        drawAttributed(attributed, at: origin, ctx: ctx)
    }

    private static func drawAttributed(_ string: NSAttributedString, at point: CGPoint, ctx: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        string.draw(at: point)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func contrastingTextColor(for color: NSColor) -> NSColor {
        guard let rgb = color.usingColorSpace(.sRGB) else { return .white }
        let luminance: CGFloat = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return luminance > 0.65 ? .black : .white
    }
}

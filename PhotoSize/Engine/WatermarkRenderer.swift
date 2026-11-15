import CoreGraphics
import CoreText
import Foundation

/// Where and how big the watermark is, in output-pixel coordinates
/// with the origin at the top-left (the Xojo app's convention).
nonisolated struct WatermarkLayout: Equatable, Sendable {
    /// Center of the text block or logo (and of the background box).
    var center: CGPoint
    /// Size before rotation: for text, widest line × total line height; for a logo, its drawn size.
    var contentSize: CGSize
    /// Size of the background box before rotation (text only; equals `contentSize` for a logo).
    var boxSize: CGSize
    /// Height used for vertical snap insets: the font ascent for text (as in the original app),
    /// the full height for a logo.
    var ascent: Double
}

/// Draws the watermark. Used for both the on-screen preview and exported files,
/// so the preview always matches the output.
nonisolated enum WatermarkRenderer {

    // MARK: Text setup

    static func font(for s: WatermarkSettings, size: Double) -> CTFont {
        let descriptor = CTFontDescriptorCreateWithAttributes(
            [kCTFontFamilyNameAttribute: s.fontFamily] as CFDictionary)
        let base = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        var traits: CTFontSymbolicTraits = []
        if s.bold { traits.insert(.traitBold) }
        if s.italic { traits.insert(.traitItalic) }
        guard !traits.isEmpty,
              let styled = CTFontCreateCopyWithSymbolicTraits(base, size, nil, traits, traits)
        else { return base }
        return styled
    }

    private struct TypesetText {
        let font: CTFont
        let lines: [(line: CTLine, width: Double)]
        let lineHeight: Double
        let ascent: Double
        var size: CGSize {
            CGSize(width: lines.map(\.width).max() ?? 0, height: lineHeight * Double(lines.count))
        }
    }

    private static func typeset(_ s: WatermarkSettings, fontSize: Double) -> TypesetText {
        let font = font(for: s, size: fontSize)
        let ascent = CTFontGetAscent(font)
        let lineHeight = ascent + CTFontGetDescent(font) + CTFontGetLeading(font)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: s.color.cgColor,
        ]
        let rawLines = s.text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        let lines = rawLines.map { text -> (CTLine, Double) in
            let attributed = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)!
            let line = CTLineCreateWithAttributedString(attributed)
            return (line, CTLineGetTypographicBounds(line, nil, nil, nil))
        }
        return TypesetText(font: font, lines: lines, lineHeight: lineHeight, ascent: ascent)
    }

    // MARK: Logo setup

    /// The logo's drawn size on an image of the given width, keeping the logo's proportions.
    static func logoSize(for s: WatermarkSettings, logoPixelSize: CGSize, imageWidth: Double) -> CGSize {
        guard logoPixelSize.width > 0 else { return .zero }
        let width = max(s.logoWidthPercent, 0) / 100 * imageWidth
        return CGSize(width: width, height: width * logoPixelSize.height / logoPixelSize.width)
    }

    // MARK: Layout

    /// The watermark's layout, or nil when a logo is chosen but its file can't be read.
    static func layout(for s: WatermarkSettings, imageSize: CGSize) -> WatermarkLayout? {
        switch s.kind {
        case .text:
            let metrics = s.metrics(forImageWidth: imageSize.width)
            return textLayout(for: s, text: typeset(s, fontSize: metrics.fontSize), imageSize: imageSize)
        case .logo:
            guard let url = s.logoURL, let info = try? ImageLoader.info(for: url) else { return nil }
            return logoLayout(for: s, logoPixelSize: info.pixelSize, imageSize: imageSize)
        }
    }

    private static func textLayout(for s: WatermarkSettings, text: TypesetText, imageSize: CGSize) -> WatermarkLayout {
        let size = text.size
        let metrics = s.metrics(forImageWidth: imageSize.width)
        let center = center(for: s.position, contentWidth: size.width, verticalExtent: text.ascent,
                            padding: metrics.edgePadding, imageSize: imageSize)
        let boxPad = metrics.boxPadding
        return WatermarkLayout(
            center: center,
            contentSize: size,
            boxSize: CGSize(width: size.width + boxPad * 4, height: size.height + boxPad * 2),
            ascent: text.ascent)
    }

    static func logoLayout(for s: WatermarkSettings, logoPixelSize: CGSize, imageSize: CGSize) -> WatermarkLayout {
        let size = logoSize(for: s, logoPixelSize: logoPixelSize, imageWidth: imageSize.width)
        let center = center(for: s.position, contentWidth: size.width, verticalExtent: size.height,
                            padding: WatermarkSettings.logoEdgePadding * imageSize.width, imageSize: imageSize)
        return WatermarkLayout(center: center, contentSize: size, boxSize: size, ascent: size.height)
    }

    /// Center point for a position. Snapped positions keep the content `padding` from the edges;
    /// vertically the inset uses `verticalExtent` (the original app used the font ascent for text).
    private static func center(for position: WatermarkPosition, contentWidth: Double, verticalExtent: Double,
                               padding pad: Double, imageSize: CGSize) -> CGPoint {
        let w = imageSize.width, h = imageSize.height
        let left = contentWidth / 2 + pad
        let right = w - contentWidth / 2 - pad
        let top = verticalExtent / 2 + pad
        let bottom = h - pad - verticalExtent / 2

        switch position {
        case .snap(.topLeft):      return CGPoint(x: left, y: top)
        case .snap(.topCenter):    return CGPoint(x: w / 2, y: top)
        case .snap(.topRight):     return CGPoint(x: right, y: top)
        case .snap(.centerLeft):   return CGPoint(x: left, y: h / 2)
        case .snap(.center):       return CGPoint(x: w / 2, y: h / 2)
        case .snap(.centerRight):  return CGPoint(x: right, y: h / 2)
        case .snap(.bottomLeft):   return CGPoint(x: left, y: bottom)
        case .snap(.bottomCenter): return CGPoint(x: w / 2, y: bottom)
        case .snap(.bottomRight):  return CGPoint(x: right, y: bottom)
        case .free(let x, let y):  return CGPoint(x: x * w, y: y * h)
        }
    }

    // MARK: Drawing

    /// Draws the watermark into `context`, whose user space covers `imageSize`
    /// with the usual Core Graphics bottom-left origin.
    static func draw(_ s: WatermarkSettings, in context: CGContext, imageSize: CGSize) {
        guard s.isVisible else { return }
        switch s.kind {
        case .text:
            drawText(s, in: context, imageSize: imageSize)
        case .logo:
            // A logo that can no longer be read is skipped rather than failing the export.
            guard let url = s.logoURL, let logo = try? ImageLoader.image(at: url) else { return }
            drawLogo(s, logo: logo, in: context, imageSize: imageSize)
        }
    }

    /// Moves to the watermark center (flipping y), rotates clockwise and applies the opacity.
    private static func prepare(_ context: CGContext, for s: WatermarkSettings, layout: WatermarkLayout, imageSize: CGSize) {
        context.translateBy(x: layout.center.x, y: imageSize.height - layout.center.y)
        context.rotate(by: -s.angle * .pi / 180)
        context.setAlpha(min(max(s.opacity, 0), 100) / 100)
    }

    private static func drawLogo(_ s: WatermarkSettings, logo: CGImage, in context: CGContext, imageSize: CGSize) {
        let layout = logoLayout(for: s, logoPixelSize: CGSize(width: logo.width, height: logo.height), imageSize: imageSize)
        context.saveGState()
        defer { context.restoreGState() }
        prepare(context, for: s, layout: layout, imageSize: imageSize)
        context.interpolationQuality = .high
        let size = layout.contentSize
        context.draw(logo, in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
    }

    private static func drawText(_ s: WatermarkSettings, in context: CGContext, imageSize: CGSize) {
        let text = typeset(s, fontSize: s.metrics(forImageWidth: imageSize.width).fontSize)
        let layout = textLayout(for: s, text: text, imageSize: imageSize)

        context.saveGState()
        defer { context.restoreGState() }
        prepare(context, for: s, layout: layout, imageSize: imageSize)

        if s.backgroundEnabled {
            context.setFillColor(s.backgroundColor.cgColor)
            context.fill(CGRect(x: -layout.boxSize.width / 2, y: -layout.boxSize.height / 2,
                                width: layout.boxSize.width, height: layout.boxSize.height))
        }

        // Lines are centered horizontally; the block is centered vertically.
        context.textMatrix = .identity
        let underlinePosition = CTFontGetUnderlinePosition(text.font)
        let underlineThickness = max(CTFontGetUnderlineThickness(text.font), 1)
        let blockTop = layout.contentSize.height / 2
        for (index, entry) in text.lines.enumerated() {
            let x = -entry.width / 2
            let baseline = blockTop - Double(index) * text.lineHeight - text.ascent
            context.textPosition = CGPoint(x: x, y: baseline)
            CTLineDraw(entry.line, context)
            if s.underline, entry.width > 0 {
                context.setFillColor(s.color.cgColor)
                context.fill(CGRect(x: x, y: baseline + underlinePosition - underlineThickness / 2,
                                    width: entry.width, height: underlineThickness))
            }
        }
    }
}

nonisolated enum RenderError: LocalizedError {
    case contextCreationFailed

    var errorDescription: String? { "The image could not be rendered." }
}

/// Produces a finished image: the source resized to the output size with the watermark on top.
nonisolated enum ImageRenderer {

    /// - Parameters:
    ///   - image: An oriented source image of any size (it is stretched to `outputSize`).
    ///   - outputSize: The final pixel size of the exported file.
    ///   - scale: Renders a proportionally smaller copy (for previews). 1 for export.
    ///   - opaqueBackground: Flattens transparency onto white (needed for JPEG).
    static func render(_ image: CGImage,
                       outputSize: CGSize,
                       watermark: WatermarkSettings,
                       scale: Double = 1,
                       opaqueBackground: Bool) throws -> CGImage {
        let width = max(1, Int((outputSize.width * scale).rounded()))
        let height = max(1, Int((outputSize.height * scale).rounded()))

        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let preferred = image.colorSpace.flatMap { $0.model == .rgb && $0.supportsOutput ? $0 : nil } ?? srgb
        let alphaInfo: CGImageAlphaInfo = opaqueBackground ? .noneSkipLast : .premultipliedLast

        func makeContext(_ space: CGColorSpace) -> CGContext? {
            CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                      space: space, bitmapInfo: alphaInfo.rawValue)
        }
        guard let context = makeContext(preferred) ?? makeContext(srgb) else {
            throw RenderError.contextCreationFailed
        }

        context.interpolationQuality = .high
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        if opaqueBackground {
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(bounds)
        }
        context.draw(image, in: bounds)

        // Draw the watermark in output-pixel units.
        context.scaleBy(x: Double(width) / outputSize.width, y: Double(height) / outputSize.height)
        WatermarkRenderer.draw(watermark, in: context, imageSize: outputSize)

        guard let result = context.makeImage() else { throw RenderError.contextCreationFailed }
        return result
    }
}

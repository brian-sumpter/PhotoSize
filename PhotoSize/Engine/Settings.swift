import CoreGraphics
import ImageIO
import Foundation

// MARK: - Color

/// A Codable RGBA color (components 0...1, sRGB).
nonisolated struct RGBAColor: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    static let white = RGBAColor(red: 1, green: 1, blue: 1)
    static let black = RGBAColor(red: 0, green: 0, blue: 0)

    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

// MARK: - Resize

nonisolated enum ResizeMode: String, Codable, CaseIterable, Sendable {
    case width, height, scale
}

nonisolated struct ResizeSettings: Codable, Hashable, Sendable {
    var isEnabled = false
    var mode: ResizeMode = .width
    /// Target width in pixels for `.width` mode.
    var width = 1024
    /// Target height in pixels for `.height` mode.
    var height = 768
    /// Percentage of the original size for `.scale` mode.
    var scalePercent = 50

    /// The output pixel size for an image of `original` size.
    /// Mirrors the Xojo `resizeToFit` behavior: aspect fit, upscaling allowed.
    func targetSize(for original: CGSize) -> CGSize {
        guard isEnabled, original.width > 0, original.height > 0 else { return original }
        let ratio: Double
        switch mode {
        case .width:  ratio = Double(max(width, 1)) / original.width
        case .height: ratio = Double(max(height, 1)) / original.height
        case .scale:  ratio = Double(max(scalePercent, 1)) / 100
        }
        return CGSize(width: max(1, (original.width * ratio).rounded()),
                      height: max(1, (original.height * ratio).rounded()))
    }

    /// True when these settings would make an image of `original` size larger
    /// (the original app showed a quality warning in this case).
    func enlarges(_ original: CGSize) -> Bool {
        let t = targetSize(for: original)
        return t.width > original.width || t.height > original.height
    }
}

nonisolated struct ResizePreset: Hashable, Identifiable, Sendable {
    let mode: ResizeMode
    let value: Int
    var id: String { "\(mode.rawValue)-\(value)" }

    var title: String {
        switch mode {
        case .width:  "Fit Width To \(value)"
        case .height: "Fit Height To \(value)"
        case .scale:  "Scale To \(value)% Original"
        }
    }

    /// The preset list from the original app, grouped by mode.
    static let groups: [[ResizePreset]] = [
        [320, 640, 800, 1024, 1280, 2560].map { ResizePreset(mode: .width, value: $0) },
        [240, 480, 600, 768, 1024, 1280].map { ResizePreset(mode: .height, value: $0) },
        [12, 25, 50, 75, 100].map { ResizePreset(mode: .scale, value: $0) },
    ]

    func apply(to settings: inout ResizeSettings) {
        settings.isEnabled = true
        settings.mode = mode
        switch mode {
        case .width:  settings.width = value
        case .height: settings.height = value
        case .scale:  settings.scalePercent = value
        }
    }
}

// MARK: - Watermark

/// The 3×3 snap grid positions.
nonisolated enum SnapAnchor: String, Codable, CaseIterable, Sendable {
    case topLeft, topCenter, topRight
    case centerLeft, center, centerRight
    case bottomLeft, bottomCenter, bottomRight
}

nonisolated enum WatermarkPosition: Codable, Hashable, Sendable {
    /// Snapped to a grid position, inset by `WatermarkSettings.edgePadding`.
    case snap(SnapAnchor)
    /// Centered on a point given as fractions (0...1) of the image width and height,
    /// measured from the top-left corner.
    case free(x: Double, y: Double)
}

nonisolated enum WatermarkSizeMode: String, Codable, CaseIterable, Sendable {
    /// `fontSize` is in output pixels, as in the original app.
    case pixels
    /// `relativeSize` is a percentage of each output image's width, so the
    /// watermark looks the same on small and large photos.
    case relative
}

nonisolated enum WatermarkKind: String, Codable, CaseIterable, Sendable {
    case text, logo
}

nonisolated struct WatermarkSettings: Codable, Hashable, Sendable {
    var isEnabled = false
    var kind: WatermarkKind = .text
    var text = ""
    var fontFamily = "Helvetica"
    var sizeMode: WatermarkSizeMode = .relative
    /// Font size in output pixels (`.pixels` mode).
    var fontSize: Double = 50
    /// Font size as a percentage of the image width (`.relative` mode).
    var relativeSize: Double = 4
    var color: RGBAColor = .white
    var bold = false
    var italic = false
    var underline = false
    /// 0...100
    var opacity: Double = 100
    /// Degrees, clockwise.
    var angle: Double = 0
    var backgroundEnabled = false
    var backgroundColor: RGBAColor = .black
    var position: WatermarkPosition = .snap(.center)
    /// The logo image, kept in the app's own storage (see `LogoStore`).
    var logoURL: URL?
    /// Logo width as a percentage of each output image's width.
    var logoWidthPercent: Double = 20

    /// Distance from the image edge for snapped positions (Xojo `paddingString`), in pixel mode.
    static let edgePadding: Double = 20
    /// Padding unit around the text for the background box (Xojo `paddingFill`), in pixel mode.
    static let boxPadding: Double = 10
    /// The original's default font size; in relative mode the paddings keep the
    /// same proportion to the font size as they had at this size.
    static let referenceFontSize: Double = 50

    /// Logo distance from the image edge for snapped positions, as a fraction of the image width.
    static let logoEdgePadding: Double = 0.02

    /// Whether anything would actually be drawn (a missing logo file is only found when drawing).
    var isVisible: Bool {
        guard isEnabled, opacity > 0 else { return false }
        switch kind {
        case .text:
            let size = sizeMode == .pixels ? fontSize : relativeSize
            return !text.isEmpty && size > 0
        case .logo:
            return logoURL != nil && logoWidthPercent > 0
        }
    }

    /// Font size and paddings in output pixels for an image of the given width.
    func metrics(forImageWidth width: Double) -> (fontSize: Double, edgePadding: Double, boxPadding: Double) {
        switch sizeMode {
        case .pixels:
            return (fontSize, Self.edgePadding, Self.boxPadding)
        case .relative:
            let size = max(relativeSize, 0) / 100 * width
            let scale = size / Self.referenceFontSize
            return (size, Self.edgePadding * scale, Self.boxPadding * scale)
        }
    }
}

nonisolated extension WatermarkSettings {
    /// Settings saved by an earlier version may lack newer fields;
    /// those take their defaults instead of discarding everything.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WatermarkSettings()
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? d.isEnabled
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? d.text
        fontFamily = try c.decodeIfPresent(String.self, forKey: .fontFamily) ?? d.fontFamily
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? d.fontSize
        color = try c.decodeIfPresent(RGBAColor.self, forKey: .color) ?? d.color
        bold = try c.decodeIfPresent(Bool.self, forKey: .bold) ?? d.bold
        italic = try c.decodeIfPresent(Bool.self, forKey: .italic) ?? d.italic
        underline = try c.decodeIfPresent(Bool.self, forKey: .underline) ?? d.underline
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? d.opacity
        angle = try c.decodeIfPresent(Double.self, forKey: .angle) ?? d.angle
        backgroundEnabled = try c.decodeIfPresent(Bool.self, forKey: .backgroundEnabled) ?? d.backgroundEnabled
        backgroundColor = try c.decodeIfPresent(RGBAColor.self, forKey: .backgroundColor) ?? d.backgroundColor
        position = try c.decodeIfPresent(WatermarkPosition.self, forKey: .position) ?? d.position
        // Saved before relative sizing existed: keep the pixel size the user chose.
        sizeMode = try c.decodeIfPresent(WatermarkSizeMode.self, forKey: .sizeMode) ?? .pixels
        relativeSize = try c.decodeIfPresent(Double.self, forKey: .relativeSize) ?? d.relativeSize
        kind = try c.decodeIfPresent(WatermarkKind.self, forKey: .kind) ?? d.kind
        logoURL = try c.decodeIfPresent(URL.self, forKey: .logoURL) ?? d.logoURL
        logoWidthPercent = try c.decodeIfPresent(Double.self, forKey: .logoWidthPercent) ?? d.logoWidthPercent
    }
}

// MARK: - Export

nonisolated enum ExportFormat: String, Codable, CaseIterable, Sendable {
    case jpeg, png, heic

    var title: String {
        switch self {
        case .jpeg: "JPEG"
        case .png:  "PNG"
        case .heic: "HEIC"
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: "JPG"
        case .png:  "PNG"
        case .heic: "HEIC"
        }
    }

    var typeIdentifier: String {
        switch self {
        case .jpeg: "public.jpeg"
        case .png:  "public.png"
        case .heic: "public.heic"
        }
    }

    /// Lossy formats use the quality setting.
    var usesQuality: Bool { self != .png }

    /// JPEG can't store transparency, so transparent areas are filled with white.
    var needsOpaqueBackground: Bool { self == .jpeg }

    /// Formats this Mac can write. HEIC needs a hardware HEVC encoder, which some older Intel Macs lack.
    static var available: [ExportFormat] {
        let writable = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
        return allCases.filter { writable.contains($0.typeIdentifier) }
    }
}

nonisolated enum ConflictPolicy: String, Codable, Sendable {
    /// Add " 2", " 3", … to the name until it is free.
    case keepBoth
    /// Overwrite files that already exist in the destination.
    case replace
}

nonisolated struct ExportSettings: Codable, Hashable, Sendable {
    var format: ExportFormat = .jpeg
    /// 10...100, JPEG only.
    var quality = 80
    var appendSuffix = false
    var suffix = "Copy"
    var numberFiles = false
    var numberStart = 1
    var revealInFinder = true
    /// Copy EXIF/IPTC/color metadata from the source.
    var keepMetadata = true
    /// Remove GPS location even when keeping other metadata.
    var removeLocation = false
    var conflictPolicy: ConflictPolicy = .keepBoth
}

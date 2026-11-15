import CoreGraphics
import Foundation
import ImageIO

nonisolated enum ImageLoaderError: LocalizedError {
    case unreadable(URL)

    var errorDescription: String? {
        switch self {
        case .unreadable(let url): "“\(url.lastPathComponent)” could not be read as an image."
        }
    }
}

/// Reads images with ImageIO, always applying the EXIF orientation.
nonisolated enum ImageLoader {
    static let supportedTypeIdentifiers = ["public.jpeg", "public.png", "public.tiff", "com.compuserve.gif", "public.heic"]

    /// `@unchecked` because `properties` comes from ImageIO and holds only
    /// immutable property-list values.
    struct Info: @unchecked Sendable {
        /// Pixel size after orientation is applied.
        let pixelSize: CGSize
        let hasAlpha: Bool
        /// The source's metadata dictionary (EXIF, IPTC, …).
        let properties: [String: Any]
    }

    static func source(for url: URL) throws -> CGImageSource {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(src) > 0 else {
            throw ImageLoaderError.unreadable(url)
        }
        return src
    }

    static func info(for source: CGImageSource, url: URL) throws -> Info {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let w = props[kCGImagePropertyPixelWidth as String] as? Double,
              let h = props[kCGImagePropertyPixelHeight as String] as? Double else {
            throw ImageLoaderError.unreadable(url)
        }
        let orientation = props[kCGImagePropertyOrientation as String] as? UInt32 ?? 1
        let swaps = (5...8).contains(orientation)
        let hasAlpha = props[kCGImagePropertyHasAlpha as String] as? Bool ?? false
        return Info(pixelSize: swaps ? CGSize(width: h, height: w) : CGSize(width: w, height: h),
                    hasAlpha: hasAlpha,
                    properties: props)
    }

    static func info(for url: URL) throws -> Info {
        try info(for: source(for: url), url: url)
    }

    /// An oriented image whose longest side is at most `maxPixelSize`
    /// (never upscaled). Pass `nil` for the full-size image.
    static func image(from source: CGImageSource, url: URL, maxPixelSize: Int? = nil) throws -> CGImage {
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        let full = try info(for: source, url: url).pixelSize
        options[kCGImageSourceThumbnailMaxPixelSize] = maxPixelSize ?? Int(max(full.width, full.height))
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageLoaderError.unreadable(url)
        }
        return image
    }

    static func image(at url: URL, maxPixelSize: Int? = nil) throws -> CGImage {
        try image(from: source(for: url), url: url, maxPixelSize: maxPixelSize)
    }

    /// Sidebar thumbnail.
    static func thumbnail(at url: URL, maxPixelSize: Int = 400) throws -> CGImage {
        try image(at: url, maxPixelSize: maxPixelSize)
    }
}

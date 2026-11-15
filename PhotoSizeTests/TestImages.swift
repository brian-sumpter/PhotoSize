import CoreGraphics
import Foundation
import ImageIO
@testable import PhotoSize

/// Helpers for making and inspecting small test images.
enum TestImages {
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    static func tempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "PhotoSizeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A solid-color image, optionally with a differently colored left half
    /// (so orientation changes are visible).
    static func solid(width: Int, height: Int, color: RGBAColor, leftHalf: RGBAColor? = nil, opaque: Bool = true) -> CGImage {
        let info = opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: srgb, bitmapInfo: info.rawValue)!
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if let leftHalf {
            ctx.setFillColor(leftHalf.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        }
        return ctx.makeImage()!
    }

    @discardableResult
    static func write(_ image: CGImage, to url: URL, type: String = "public.png", properties: [String: Any] = [:]) -> URL {
        let dest = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, properties as CFDictionary)
        precondition(CGImageDestinationFinalize(dest))
        return url
    }

    /// RGBA8 sRGB pixel reader, origin top-left.
    struct Pixels {
        let width: Int, height: Int
        private let bytes: [UInt8]

        init(_ image: CGImage) {
            width = image.width; height = image.height
            var buffer = [UInt8](repeating: 0, count: width * height * 4)
            buffer.withUnsafeMutableBytes { raw in
                let ctx = CGContext(data: raw.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4, space: TestImages.srgb,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            bytes = buffer
        }

        /// (r, g, b, a) in 0...255 at (x, y) from the top-left.
        subscript(x: Int, y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
            let i = (y * width + x) * 4
            return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]), Int(bytes[i + 3]))
        }

        func count(where predicate: ((r: Int, g: Int, b: Int, a: Int)) -> Bool) -> Int {
            var n = 0
            for y in 0..<height { for x in 0..<width where predicate(self[x, y]) { n += 1 } }
            return n
        }
    }
}

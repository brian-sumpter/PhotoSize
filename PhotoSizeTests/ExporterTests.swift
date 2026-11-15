import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import PhotoSize

struct ExporterTests {

    func properties(_ url: URL) -> [String: Any] {
        let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
        return CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as! [String: Any]
    }

    func image(_ url: URL) -> CGImage {
        let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
        return CGImageSourceCreateImageAtIndex(src, 0, nil)!
    }

    func export(_ sources: [URL], to folder: URL,
                resize: ResizeSettings = ResizeSettings(),
                watermark: WatermarkSettings = WatermarkSettings(),
                settings: ExportSettings = ExportSettings()) async throws -> ExportResult {
        let jobs = ExportNaming.plan(sources: sources, folder: folder, settings: settings)
        return try await Exporter.export(jobs, resize: resize, watermark: watermark, settings: settings)
    }

    @Test func appliesExifOrientation() async throws {
        let folder = try TestImages.tempFolder()
        // Stored 40×20 with a red left half; orientation 6 means "rotate 90° clockwise to display".
        let stored = TestImages.solid(width: 40, height: 20, color: .black, leftHalf: RGBAColor(red: 1, green: 0, blue: 0))
        let src = TestImages.write(stored, to: folder.appending(path: "rotated.png"),
                                   properties: [kCGImagePropertyOrientation as String: 6])

        var settings = ExportSettings(); settings.format = .png; settings.appendSuffix = true
        let result = try await export([src], to: folder, settings: settings)
        #expect(result.failures.isEmpty)
        let out = try #require(result.written.first)
        let img = image(out)
        #expect(img.width == 20 && img.height == 40)
        #expect(properties(out)[kCGImagePropertyOrientation as String] as? Int ?? 1 == 1)
        // After a clockwise turn, the stored left half ends up on top.
        let p = TestImages.Pixels(img)
        #expect(p[10, 5].r > 200)
        #expect(p[10, 35].r < 50)
    }

    @Test func resizesAndWritesJPEG() async throws {
        let folder = try TestImages.tempFolder()
        let src = TestImages.write(TestImages.solid(width: 800, height: 600, color: .white),
                                   to: folder.appending(path: "big.png"))
        var resize = ResizeSettings(); resize.isEnabled = true; resize.mode = .width; resize.width = 200
        var settings = ExportSettings(); settings.quality = 50

        let result = try await export([src], to: folder, resize: resize, settings: settings)
        let out = try #require(result.written.first)
        #expect(out.lastPathComponent == "big.JPG")
        let props = properties(out)
        #expect(props[kCGImagePropertyPixelWidth as String] as? Int == 200)
        #expect(props[kCGImagePropertyPixelHeight as String] as? Int == 150)
        let type = CGImageSourceGetType(CGImageSourceCreateWithURL(out as CFURL, nil)!) as String?
        #expect(type == "public.jpeg")
    }

    @Test func upscales() async throws {
        let folder = try TestImages.tempFolder()
        let src = TestImages.write(TestImages.solid(width: 100, height: 50, color: .white),
                                   to: folder.appending(path: "small.png"))
        var resize = ResizeSettings(); resize.isEnabled = true; resize.mode = .scale; resize.scalePercent = 300
        var settings = ExportSettings(); settings.format = .png; settings.appendSuffix = true
        let out = try #require(try await export([src], to: folder, resize: resize, settings: settings).written.first)
        #expect(image(out).width == 300 && image(out).height == 150)
    }

    @Test func jpegFlattensTransparencyOntoWhite() async throws {
        let folder = try TestImages.tempFolder()
        let clear = TestImages.solid(width: 20, height: 20, color: RGBAColor(red: 0, green: 0, blue: 0, alpha: 0), opaque: false)
        let src = TestImages.write(clear, to: folder.appending(path: "clear.png"))
        let out = try #require(try await export([src], to: folder).written.first)
        let p = TestImages.Pixels(image(out))[10, 10]
        #expect(p.r > 240 && p.g > 240 && p.b > 240)
    }

    @Test func pngKeepsTransparency() async throws {
        let folder = try TestImages.tempFolder()
        let clear = TestImages.solid(width: 20, height: 20, color: RGBAColor(red: 0, green: 0, blue: 0, alpha: 0), opaque: false)
        let src = TestImages.write(clear, to: folder.appending(path: "clear.png"))
        var settings = ExportSettings(); settings.format = .png; settings.appendSuffix = true
        let out = try #require(try await export([src], to: folder, settings: settings).written.first)
        #expect(TestImages.Pixels(image(out))[10, 10].a == 0)
    }

    @Test func metadataKeptAndLocationRemovable() async throws {
        let folder = try TestImages.tempFolder()
        let props: [String: Any] = [
            kCGImagePropertyExifDictionary as String: [kCGImagePropertyExifDateTimeOriginal as String: "2015:04:27 10:00:00"],
            kCGImagePropertyGPSDictionary as String: [kCGImagePropertyGPSLatitude as String: 45.5,
                                                      kCGImagePropertyGPSLatitudeRef as String: "N"],
        ]
        let src = TestImages.write(TestImages.solid(width: 40, height: 30, color: .white),
                                   to: folder.appending(path: "meta.jpg"), type: "public.jpeg", properties: props)

        var keep = ExportSettings(); keep.appendSuffix = true; keep.suffix = "keep"
        let kept = properties(try #require(try await export([src], to: folder, settings: keep).written.first))
        let exif = kept[kCGImagePropertyExifDictionary as String] as? [String: Any]
        #expect(exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String == "2015:04:27 10:00:00")
        #expect(kept[kCGImagePropertyGPSDictionary as String] != nil)

        var noGPS = keep; noGPS.suffix = "nogps"; noGPS.removeLocation = true
        let stripped = properties(try #require(try await export([src], to: folder, settings: noGPS).written.first))
        #expect(stripped[kCGImagePropertyGPSDictionary as String] == nil)
        #expect(stripped[kCGImagePropertyExifDictionary as String] != nil)
    }

    @Test func batchCollectsFailuresAndKeepsOrder() async throws {
        let folder = try TestImages.tempFolder()
        var sources: [URL] = []
        for i in 0..<6 {
            sources.append(TestImages.write(TestImages.solid(width: 30, height: 30, color: .white),
                                            to: folder.appending(path: "p\(i).png")))
        }
        let bogus = folder.appending(path: "not-an-image.png")
        try Data("hello".utf8).write(to: bogus)
        sources.insert(bogus, at: 3)

        let out = folder.appending(path: "out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var settings = ExportSettings(); settings.numberFiles = true

        final class Counter: @unchecked Sendable { var calls = 0; let lock = NSLock() }
        let counter = Counter()
        let jobs = ExportNaming.plan(sources: sources, folder: out, settings: settings)
        let result = try await Exporter.export(jobs, resize: ResizeSettings(), watermark: WatermarkSettings(),
                                               settings: settings, maxConcurrent: 3) { _, _ in
            counter.lock.withLock { counter.calls += 1 }
        }

        #expect(counter.calls == 7)
        #expect(result.failures.map(\.source) == [bogus])
        #expect(result.written.map(\.lastPathComponent) == ["p0 1.JPG", "p1 2.JPG", "p2 3.JPG", "p3 5.JPG", "p4 6.JPG", "p5 7.JPG"])
    }

    @Test func cancellationStopsTheBatch() async throws {
        let folder = try TestImages.tempFolder()
        let src = TestImages.write(TestImages.solid(width: 30, height: 30, color: .white), to: folder.appending(path: "c.png"))
        let jobs = ExportNaming.plan(sources: Array(repeating: src, count: 20), folder: folder, settings: ExportSettings())
        let task = Task {
            try await Exporter.export(jobs, resize: ResizeSettings(), watermark: WatermarkSettings(), settings: ExportSettings())
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

struct HEICExportTests {
    static var canWriteHEIC: Bool { ExportFormat.available.contains(.heic) }

    @Test func formatsKnowTheirTraits() {
        #expect(ExportFormat.jpeg.usesQuality && ExportFormat.heic.usesQuality && !ExportFormat.png.usesQuality)
        #expect(ExportFormat.jpeg.needsOpaqueBackground && !ExportFormat.heic.needsOpaqueBackground)
        #expect(ExportFormat.available.contains(.jpeg) && ExportFormat.available.contains(.png))
    }

    @Test(.enabled(if: canWriteHEIC)) func writesHEICWithQualityAndMetadata() async throws {
        let folder = try TestImages.tempFolder()
        // A noisy image, so compression quality makes a visible difference in size.
        let ctx = CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
                            space: TestImages.srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        var rng = SystemRandomNumberGenerator()
        for y in stride(from: 0, to: 300, by: 4) {
            for x in stride(from: 0, to: 400, by: 4) {
                ctx.setFillColor(CGColor(srgbRed: .random(in: 0...1, using: &rng), green: .random(in: 0...1, using: &rng),
                                         blue: .random(in: 0...1, using: &rng), alpha: 1))
                ctx.fill(CGRect(x: x, y: y, width: 4, height: 4))
            }
        }
        let props: [String: Any] = [kCGImagePropertyExifDictionary as String:
                                        [kCGImagePropertyExifDateTimeOriginal as String: "2026:01:02 03:04:05"]]
        let src = TestImages.write(ctx.makeImage()!, to: folder.appending(path: "noise.jpg"), type: "public.jpeg", properties: props)

        func export(quality: Int, suffix: String) async throws -> URL {
            var settings = ExportSettings()
            settings.format = .heic; settings.quality = quality
            settings.appendSuffix = true; settings.suffix = suffix
            let jobs = ExportNaming.plan(sources: [src], folder: folder, settings: settings)
            let result = try await Exporter.export(jobs, resize: ResizeSettings(), watermark: WatermarkSettings(), settings: settings)
            #expect(result.failures.isEmpty)
            return try #require(result.written.first)
        }
        let low = try await export(quality: 20, suffix: "low")
        let high = try await export(quality: 100, suffix: "high")

        #expect(low.lastPathComponent == "noise low.HEIC")
        let source = try #require(CGImageSourceCreateWithURL(low as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == "public.heic")
        let size = { (url: URL) in (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        #expect(size(low) < size(high))

        let lowProps = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        #expect(lowProps[kCGImagePropertyPixelWidth as String] as? Int == 400)
        let exif = lowProps[kCGImagePropertyExifDictionary as String] as? [String: Any]
        #expect(exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String == "2026:01:02 03:04:05")
    }
}

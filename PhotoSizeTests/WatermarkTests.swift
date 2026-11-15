import Foundation
import CoreGraphics
import Testing
@testable import PhotoSize

func approx(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }

struct WatermarkLayoutTests {
    let image = CGSize(width: 1000, height: 500)

    func settings(_ position: WatermarkPosition) -> WatermarkSettings {
        var s = WatermarkSettings()
        s.isEnabled = true; s.text = "Sample"; s.sizeMode = .pixels; s.fontSize = 40; s.position = position
        return s
    }

    @Test func centerSnap() {
        let l = WatermarkRenderer.layout(for: settings(.snap(.center)), imageSize: image)!
        #expect(l.center == CGPoint(x: 500, y: 250))
    }

    @Test func cornerSnapsUseOriginalPadding() {
        let pad = WatermarkSettings.edgePadding
        let tl = WatermarkRenderer.layout(for: settings(.snap(.topLeft)), imageSize: image)!
        #expect(approx(tl.center.x, tl.contentSize.width / 2 + pad))
        #expect(approx(tl.center.y, tl.ascent / 2 + pad))

        let br = WatermarkRenderer.layout(for: settings(.snap(.bottomRight)), imageSize: image)!
        #expect(approx(br.center.x, image.width - br.contentSize.width / 2 - pad))
        #expect(approx(br.center.y, image.height - pad - br.ascent / 2))
    }

    @Test func freePositionIsFractionOfImage() {
        let l = WatermarkRenderer.layout(for: settings(.free(x: 0.25, y: 0.8)), imageSize: image)!
        #expect(l.center == CGPoint(x: 250, y: 400))
    }

    @Test func boxPadding() {
        let l = WatermarkRenderer.layout(for: settings(.snap(.center)), imageSize: image)!
        #expect(l.boxSize.width == l.contentSize.width + 40)
        #expect(l.boxSize.height == l.contentSize.height + 20)
    }

    @Test func multilineTextIsTallerAndAsWideAsLongestLine() {
        var one = settings(.snap(.center)); one.text = "Wide line here"
        var two = one; two.text = "Wide line here\nshort"
        let a = WatermarkRenderer.layout(for: one, imageSize: image)!
        let b = WatermarkRenderer.layout(for: two, imageSize: image)!
        #expect(b.contentSize.width == a.contentSize.width)
        #expect(abs(b.contentSize.height - 2 * a.contentSize.height) < 0.001)
    }

    @Test func boldIsWiderThanRegular() {
        var regular = settings(.snap(.center)); regular.text = "Watermark"
        var bold = regular; bold.bold = true
        #expect(WatermarkRenderer.layout(for: bold, imageSize: image)!.contentSize.width
                > WatermarkRenderer.layout(for: regular, imageSize: image)!.contentSize.width)
    }

    @Test func unknownFontFallsBack() {
        var s = settings(.snap(.center)); s.fontFamily = "No Such Font 123"
        #expect(WatermarkRenderer.layout(for: s, imageSize: image)!.contentSize.width > 0)
    }
}

struct RenderTests {
    let black = TestImages.solid(width: 400, height: 200, color: .black)

    func watermark() -> WatermarkSettings {
        var s = WatermarkSettings()
        s.isEnabled = true; s.text = "████"; s.sizeMode = .pixels; s.fontSize = 60; s.color = .white
        return s
    }

    func brightPixels(_ image: CGImage) -> Int {
        TestImages.Pixels(image).count { $0.r > 200 && $0.g > 200 && $0.b > 200 }
    }

    @Test func drawsWatermark() throws {
        let out = try ImageRenderer.render(black, outputSize: CGSize(width: 400, height: 200),
                                           watermark: watermark(), opaqueBackground: true)
        #expect(out.width == 400 && out.height == 200)
        #expect(brightPixels(out) > 1000)
        // The center snap means the middle of the image is covered.
        let p = TestImages.Pixels(out)[200, 100]
        #expect(p.r > 200)
    }

    @Test func disabledOrInvisibleWatermarkDrawsNothing() throws {
        var off = watermark(); off.isEnabled = false
        var clear = watermark(); clear.opacity = 0
        var empty = watermark(); empty.text = ""
        for s in [off, clear, empty] {
            let out = try ImageRenderer.render(black, outputSize: CGSize(width: 400, height: 200),
                                               watermark: s, opaqueBackground: true)
            #expect(brightPixels(out) == 0)
        }
    }

    @Test func opacityBlends() throws {
        // A single glyph, so the sampled pixel isn't where two glyphs overlap.
        var half = watermark(); half.text = "█"; half.fontSize = 120; half.opacity = 50
        let out = try ImageRenderer.render(black, outputSize: CGSize(width: 400, height: 200),
                                           watermark: half, opaqueBackground: true)
        let p = TestImages.Pixels(out)[200, 100]
        #expect((110...145).contains(p.r))
    }

    @Test func backgroundBox() throws {
        var s = watermark()
        s.text = "...."
        s.backgroundEnabled = true
        s.backgroundColor = RGBAColor(red: 1, green: 0, blue: 0)
        let size = CGSize(width: 400, height: 200)
        let out = try ImageRenderer.render(black, outputSize: size, watermark: s, opaqueBackground: true)
        let layout = WatermarkRenderer.layout(for: s, imageSize: size)!
        let pixels = TestImages.Pixels(out)
        // Just inside the box's left edge is red; just outside is still black.
        let inside = pixels[Int(layout.center.x - layout.boxSize.width / 2) + 2, Int(layout.center.y)]
        let outside = pixels[Int(layout.center.x - layout.boxSize.width / 2) - 3, Int(layout.center.y)]
        #expect(inside.r > 200 && inside.g < 50)
        #expect(outside.r < 30)
    }

    @Test func rotationTurnsWideTextTall() throws {
        var s = watermark(); s.text = "██████████"; s.fontSize = 20
        let size = CGSize(width: 300, height: 300)
        let square = TestImages.solid(width: 300, height: 300, color: .black)

        func extent(_ image: CGImage) -> (w: Int, h: Int) {
            let p = TestImages.Pixels(image)
            var xs: [Int] = [], ys: [Int] = []
            for y in 0..<p.height { for x in 0..<p.width where p[x, y].r > 200 { xs.append(x); ys.append(y) } }
            return ((xs.max()! - xs.min()!), (ys.max()! - ys.min()!))
        }
        let flat = extent(try ImageRenderer.render(square, outputSize: size, watermark: s, opaqueBackground: true))
        s.angle = 90
        let turned = extent(try ImageRenderer.render(square, outputSize: size, watermark: s, opaqueBackground: true))
        #expect(flat.w > flat.h * 3)
        #expect(turned.h > turned.w * 3)
    }

    @Test func previewScaleKeepsProportions() throws {
        var s = watermark(); s.position = .snap(.topLeft)
        let size = CGSize(width: 400, height: 200)
        let full = try ImageRenderer.render(black, outputSize: size, watermark: s, opaqueBackground: true)
        let small = try ImageRenderer.render(black, outputSize: size, watermark: s, scale: 0.5, opaqueBackground: true)
        #expect(small.width == 200 && small.height == 100)
        let ratio = Double(brightPixels(full)) / Double(brightPixels(small))
        #expect((3.5...4.5).contains(ratio))  // area scales with the square of 0.5
    }
}

@MainActor
struct WatermarkUITests {
    @Test func dragPositionIsFractionOfDisplayedImage() {
        let size = CGSize(width: 400, height: 200)
        #expect(PreviewView.freePosition(at: CGPoint(x: 100, y: 150), in: size) == .free(x: 0.25, y: 0.75))
        // Dragging past the edge clamps to the image.
        #expect(PreviewView.freePosition(at: CGPoint(x: -50, y: 900), in: size) == .free(x: 0, y: 1))
    }

    @Test func colorRoundTrip() {
        let c = RGBAColor(red: 0.2, green: 0.4, blue: 0.6)
        let back = RGBAColor(c.swiftUIColor)
        #expect(abs(back.red - 0.2) < 0.01 && abs(back.green - 0.4) < 0.01 && abs(back.blue - 0.6) < 0.01)
    }
}

struct RelativeSizeTests {
    func settings(_ mode: WatermarkSizeMode) -> WatermarkSettings {
        var s = WatermarkSettings()
        s.isEnabled = true; s.text = "Sample"; s.sizeMode = mode
        s.fontSize = 50; s.relativeSize = 5
        s.position = .snap(.topLeft)
        return s
    }

    @Test func relativeSizeScalesWithImageWidth() {
        let s = settings(.relative)
        let small = WatermarkRenderer.layout(for: s, imageSize: CGSize(width: 1000, height: 800))!
        let large = WatermarkRenderer.layout(for: s, imageSize: CGSize(width: 4000, height: 3200))!
        // 5% of the width: 50 px vs 200 px fonts, so everything is 4× bigger.
        #expect(abs(large.contentSize.width / small.contentSize.width - 4) < 0.01)
        #expect(abs(large.center.x / small.center.x - 4) < 0.01)
        #expect(abs(large.boxSize.height / small.boxSize.height - 4) < 0.01)
    }

    @Test func relativeMatchesPixelsAtReferenceSize() {
        // 5% of 1000 px = 50 px, the reference size, so relative and pixel layouts agree.
        let size = CGSize(width: 1000, height: 800)
        let relative = WatermarkRenderer.layout(for: settings(.relative), imageSize: size)!
        let pixels = WatermarkRenderer.layout(for: settings(.pixels), imageSize: size)!
        #expect(abs(relative.center.x - pixels.center.x) < 0.001)
        #expect(abs(relative.boxSize.width - pixels.boxSize.width) < 0.001)
    }

    @Test func pixelSizeIgnoresImageWidth() {
        let s = settings(.pixels)
        let small = WatermarkRenderer.layout(for: s, imageSize: CGSize(width: 1000, height: 800))!
        let large = WatermarkRenderer.layout(for: s, imageSize: CGSize(width: 4000, height: 3200))!
        #expect(small.contentSize == large.contentSize)
    }

    @Test func oldSavedSettingsKeepTheirPixelSize() throws {
        // Saved before sizeMode/relativeSize existed.
        let json = #"{"isEnabled":true,"text":"Hi","fontFamily":"Helvetica","fontSize":80,"color":{"red":1,"green":1,"blue":1,"alpha":1},"bold":true,"italic":false,"underline":false,"opacity":70,"angle":0,"backgroundEnabled":false,"backgroundColor":{"red":0,"green":0,"blue":0,"alpha":1},"position":{"snap":{"_0":"center"}}}"#
        let s = try JSONDecoder().decode(WatermarkSettings.self, from: Data(json.utf8))
        #expect(s.text == "Hi" && s.bold && s.opacity == 70 && s.fontSize == 80)
        #expect(s.sizeMode == .pixels)
    }

    @Test func roundTripKeepsEverything() throws {
        var s = settings(.relative); s.relativeSize = 7.5; s.angle = 30
        let back = try JSONDecoder().decode(WatermarkSettings.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }
}

struct LogoWatermarkTests {
    /// A 200×100 logo: red left half, transparent right half.
    func makeLogo() throws -> URL {
        let ctx = CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                            space: TestImages.srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        return TestImages.write(ctx.makeImage()!, to: try TestImages.tempFolder().appending(path: "logo.png"))
    }

    func logoSettings(_ url: URL) -> WatermarkSettings {
        var s = WatermarkSettings()
        s.isEnabled = true; s.kind = .logo; s.logoURL = url; s.logoWidthPercent = 50
        return s
    }

    @Test func logoSizeIsPercentOfWidthKeepingProportions() throws {
        let s = logoSettings(try makeLogo())
        let layout = try #require(WatermarkRenderer.layout(for: s, imageSize: CGSize(width: 800, height: 600)))
        #expect(layout.contentSize == CGSize(width: 400, height: 200))
        #expect(layout.center == CGPoint(x: 400, y: 300))
    }

    @Test func logoSnapUsesTwoPercentPadding() throws {
        var s = logoSettings(try makeLogo()); s.position = .snap(.bottomRight)
        let layout = try #require(WatermarkRenderer.layout(for: s, imageSize: CGSize(width: 1000, height: 800)))
        // 500×250 logo, 20 px padding (2% of 1000).
        #expect(abs(layout.center.x - (1000 - 250 - 20)) < 0.001)
        #expect(abs(layout.center.y - (800 - 125 - 20)) < 0.001)
    }

    @Test func drawsLogoWithTransparency() throws {
        let s = logoSettings(try makeLogo())
        let black = TestImages.solid(width: 400, height: 200, color: .black)
        let out = try ImageRenderer.render(black, outputSize: CGSize(width: 400, height: 200), watermark: s, opaqueBackground: true)
        let p = TestImages.Pixels(out)
        // Logo is 200×100 centered: x 100...300, y 50...150. Left half red, right half see-through.
        #expect(p[150, 100].r > 200 && p[150, 100].g < 50)
        #expect(p[250, 100].r < 30)
        #expect(p[50, 100].r < 30)
    }

    @Test func missingLogoFileDrawsNothingAndDoesNotFail() throws {
        var s = logoSettings(URL(filePath: "/nonexistent/logo.png"))
        s.opacity = 100
        #expect(WatermarkRenderer.layout(for: s, imageSize: CGSize(width: 400, height: 200)) == nil)
        let black = TestImages.solid(width: 40, height: 20, color: .black)
        let out = try ImageRenderer.render(black, outputSize: CGSize(width: 40, height: 20), watermark: s, opaqueBackground: true)
        #expect(TestImages.Pixels(out).count { $0.r > 30 } == 0)
    }

    @Test func noLogoChosenIsInvisible() {
        var s = WatermarkSettings(); s.isEnabled = true; s.kind = .logo
        #expect(!s.isVisible)
    }

    @Test func storeCopiesAndReplacesPreviousLogo() throws {
        let folder = try TestImages.tempFolder().appending(path: "Logos")
        let first = try LogoStore.store(try makeLogo(), in: folder)
        let second = try LogoStore.store(try makeLogo(), in: folder)
        #expect(first != second)
        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: second.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 1)
    }

    @Test func storeRejectsNonImages() throws {
        let folder = try TestImages.tempFolder()
        let text = folder.appending(path: "notes.png")
        try Data("not an image".utf8).write(to: text)
        #expect(throws: LogoStore.LogoError.self) { try LogoStore.store(text, in: folder.appending(path: "Logos")) }
    }

    @MainActor @Test func setLogoSwitchesToLogoMode() throws {
        let state = AppState()
        let folder = try TestImages.tempFolder().appending(path: "Logos")
        #expect(state.setLogo(from: try makeLogo(), folder: folder) == nil)
        #expect(state.watermark.kind == .logo)
        #expect(state.watermark.logoURL?.deletingLastPathComponent().lastPathComponent == "Logos")
    }
}

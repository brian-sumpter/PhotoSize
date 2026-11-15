import CoreGraphics
import Testing
@testable import PhotoSize

struct ResizeTests {
    let photo = CGSize(width: 4000, height: 3000)

    @Test func disabledKeepsOriginalSize() {
        var s = ResizeSettings(); s.isEnabled = false; s.width = 320
        #expect(s.targetSize(for: photo) == photo)
    }

    @Test func fitWidth() {
        var s = ResizeSettings(); s.isEnabled = true; s.mode = .width; s.width = 1024
        #expect(s.targetSize(for: photo) == CGSize(width: 1024, height: 768))
    }

    @Test func fitHeight() {
        var s = ResizeSettings(); s.isEnabled = true; s.mode = .height; s.height = 600
        #expect(s.targetSize(for: photo) == CGSize(width: 800, height: 600))
    }

    @Test func scalePercent() {
        var s = ResizeSettings(); s.isEnabled = true; s.mode = .scale; s.scalePercent = 25
        #expect(s.targetSize(for: photo) == CGSize(width: 1000, height: 750))
    }

    @Test func roundsAndNeverReachesZero() {
        var s = ResizeSettings(); s.isEnabled = true; s.mode = .width; s.width = 1
        #expect(s.targetSize(for: CGSize(width: 3000, height: 1)) == CGSize(width: 1, height: 1))
        s.width = 333
        #expect(s.targetSize(for: CGSize(width: 1000, height: 1000)) == CGSize(width: 333, height: 333))
    }

    @Test func enlargeWarning() {
        var s = ResizeSettings(); s.isEnabled = true; s.mode = .width; s.width = 2560
        #expect(s.enlarges(CGSize(width: 1024, height: 768)))
        #expect(!s.enlarges(photo))
        s.mode = .scale; s.scalePercent = 100
        #expect(!s.enlarges(photo))
    }

    @Test func presetsMatchOriginalAppAndApply() {
        #expect(ResizePreset.groups.flatMap { $0 }.map(\.title).first == "Fit Width To 320")
        #expect(ResizePreset.groups.flatMap { $0 }.count == 17)
        var s = ResizeSettings()
        ResizePreset(mode: .height, value: 480).apply(to: &s)
        #expect(s.isEnabled && s.mode == .height && s.height == 480)
    }
}

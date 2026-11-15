import Foundation
import Testing
@testable import PhotoSize

@MainActor
struct SettingsPersistenceTests {
    func freshDefaults() -> UserDefaults {
        let name = "PhotoSizeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func settingsSurviveRelaunch() {
        let defaults = freshDefaults()
        let first = AppState(defaults: defaults)
        first.resize.isEnabled = true
        first.resize.mode = .height
        first.resize.height = 480
        first.watermark.text = "Hi"
        first.export.quality = 55

        let second = AppState(defaults: defaults)
        #expect(second.resize == first.resize)
        #expect(second.watermark.text == "Hi")
        #expect(second.export.quality == 55)
    }

    @Test func defaultsWhenNothingSaved() {
        let state = AppState(defaults: freshDefaults())
        #expect(state.resize == ResizeSettings())
        #expect(state.watermark == WatermarkSettings())
    }

    @Test func noDefaultsMeansNoPersistence() {
        let state = AppState()
        state.resize.width = 777
        #expect(AppState().resize.width == ResizeSettings().width)
    }
}

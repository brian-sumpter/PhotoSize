# PhotoSize

A SwiftUI macOS app (macOS 14+) for batch-resizing and watermarking photos. It's a Swift rewrite
of a 2015 Xojo app; see [docs/PORTING.md](docs/PORTING.md) for the history and
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how it fits together.

## Layout

- `PhotoSize/Engine/`: settings, `ImageLoader`, `WatermarkRenderer`/`ImageRenderer`, `Exporter`/`ExportNaming`. All `nonisolated` and UI-free. The preview and the export both draw through `ImageRenderer.render`, so they always match — keep it that way.
- `PhotoSize/Model/`: `Photo`, `PhotoImporter`, `LogoStore`, and `AppState` (`@MainActor @Observable`, owns the photos and all settings).
- `PhotoSize/Views/` and `ContentView.swift`: the UI. `PhotoSizeApp.swift` declares a single `Window` and the menu commands. `AppInfo.swift` has the Help menu links (the GitHub repo).
- `PhotoSizeTests/`: Swift Testing, runs inside the app host.

## Build and test

```bash
xcodebuild test -project PhotoSize.xcodeproj -scheme PhotoSize -destination 'platform=macOS,arch=arm64'
```

- xcodebuild's console sometimes drops a "Test case … passed" line. Count results from the result bundle: `xcrun xcresulttool get test-results summary --path <…/Logs/Test/*.xcresult>`.
- The minimum is **macOS 14**: wrap newer APIs in `if #available` (see `GrabPointer` in `PreviewView.swift`).
- The target defaults to MainActor isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). Mark engine types and extensions `nonisolated`; mark heavy work `@concurrent`.
- The project uses Xcode 27's JSON project format (`PhotoSize.xcodeproj/project.xcproj`), not a pbxproj. Folders are synchronized, so new files in `PhotoSize/` or `PhotoSizeTests/` are picked up automatically. The test target's product type is `bundle.unit-test`; the shared scheme in `xcshareddata/xcschemes/PhotoSize.xcscheme` makes ⌘U work.
- Sandboxed, with user-selected files read/write. Bundle ID `com.emediadesigns.photosize2`.
- Saved settings are JSON in `UserDefaults`. When adding a field to a saved settings struct, decode it with `decodeIfPresent` and a default (see `WatermarkSettings.init(from:)`), or older saved settings fail to load and silently reset.

## Visual checks

- `WindowSnapshotTests` renders the window offscreen to `~/Library/Containers/com.emediadesigns.photosize2/Data/tmp/Snapshots/` when the photos from `docs/sample-photos` are copied into `…/Data/tmp/ShotImages/`. The sidebar comes out black in full-window snapshots (offscreen rendering can't draw its material); that isn't a bug. Native controls such as colour wells and sliders may also be missing from offscreen renders.
- Don't commit screenshots made from personal or stock photos. Use `docs/sample-photos`.

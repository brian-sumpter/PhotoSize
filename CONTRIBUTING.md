# Contributing to PhotoSize

Thanks for helping. Bug reports, ideas and pull requests are all welcome.

## Reporting a bug

[Open an issue](https://github.com/brian-sumpter/PhotoSize/issues) and include:

- your macOS version and Mac type (Apple silicon or Intel),
- what you did, what you expected, and what happened,
- if it's about a particular photo, its format and size (attach it only if you're happy to share it).

## Building and testing

You need Xcode 27 or later (see the README for why).

```bash
xcodebuild test -project PhotoSize.xcodeproj -scheme PhotoSize -destination 'platform=macOS,arch=arm64'
```

or press **⌘U** in Xcode. Please make sure the tests pass and the build has no warnings before
opening a pull request.

### Window snapshots

`WindowSnapshotTests` renders the main window offscreen to PNG files, which is handy for checking
layout changes. It runs only when sample photos are in the app's sandbox temporary folder:

```bash
mkdir -p ~/Library/Containers/com.emediadesigns.photosize2/Data/tmp/ShotImages
cp docs/sample-photos/*.jpg ~/Library/Containers/com.emediadesigns.photosize2/Data/tmp/ShotImages/
```

The images are written to `…/Data/tmp/Snapshots/`. The sidebar comes out black in full-window
snapshots: offscreen rendering can't draw its translucent material. That isn't a bug in the app.

## Code guidelines

- **Keep the engine UI-free.** Everything in `PhotoSize/Engine` is `nonisolated` and uses only
  Core Graphics, Core Text and ImageIO, so it can be tested without a window and run off the main
  thread. Heavy work is marked `@concurrent`.
- **One drawing path.** The preview and the export both go through `ImageRenderer.render`. Don't
  add a separate preview-only drawing path, or the two will drift apart.
- **The app target defaults to main-actor isolation** (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).
  Mark new engine types and extensions `nonisolated`.
- **Support macOS 14.** Wrap newer APIs in `if #available` with a fallback (see `GrabPointer` in
  `PreviewView.swift`). The compiler reports these when building.
- **Saved settings must keep loading.** Settings are saved as JSON in `UserDefaults`. When adding
  a field to a saved settings struct, decode it with `decodeIfPresent` and a default (see
  `WatermarkSettings.init(from:)`). Otherwise older saved settings fail to load and quietly reset.
- **Add tests** for engine changes. Swift Testing (`@Test`, `#expect`) is used throughout.

## Project file

The project uses Xcode's JSON project format (`PhotoSize.xcodeproj/project.xcproj`). The
`PhotoSize/` and `PhotoSizeTests/` folders are synchronized, so new files are picked up
automatically and you rarely need to edit the project file. The shared scheme in
`xcshareddata/xcschemes/PhotoSize.xcscheme` connects the test target to ⌘U.

## License

By contributing, you agree that your contributions are released under the [MIT License](LICENSE).

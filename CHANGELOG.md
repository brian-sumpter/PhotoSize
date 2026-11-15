# Changelog

## 2.0 — 2026

A complete rewrite of PhotoSize in Swift and SwiftUI, released as open source under the MIT License.

### Added
- Logo (image) watermarks.
- Watermark size as a percentage of each photo's width, so it looks the same on any photo size.
- HEIC export, on Macs that can encode it.
- Import whole folders; drag photos straight from apps like Photos.
- Keep photo metadata and colour profiles, with an option to remove location.
- "If a file already exists": keep both or replace.
- Faster, parallel export with progress, a Stop button and a report of any files that failed.
- Dark mode and VoiceOver support.
- Runs on macOS 14 Sonoma and later, on Apple silicon and Intel.

### Fixed
- Portrait photos from phones no longer export sideways.
- Photos with the same name from different folders no longer overwrite each other.
- Numbered files now follow the order of the photo list.
- File names containing dots are no longer cut short.
- Rotated text watermarks are centred correctly.

### Removed
- The crash-report window and the old website links. The Help menu now links to the GitHub
  repository and its issues page.
- The "Rate this app" prompt.

## 1.3.0 — 2015

The original Xojo version, sold on the Mac App Store.

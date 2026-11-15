# Porting notes: Xojo 1.3.0 → Swift 2.0

PhotoSize 1.3.0 (2015–2020) was written in Xojo with the MBS plugins and sold on the Mac App
Store. Version 2.0 is a rewrite in Swift and SwiftUI. The original project was a Xojo
*binary* project file. Its "RbBF" format is a tagged-chunk structure: blocks of 4-character
tags, types and lengths. It was decoded with a small script into readable text, one file per
class or window, and that text served as the specification.

The decoded source isn't in this repository, because it contains third-party plugin licence
details and an old service key. This document records what was learned from it.

## What 1.3.0 did

1. **Import:** drop JPEG/PNG/GIF/TIFF files (including drags from Photos) or use *Add Photos*.
   Thumbnails appear in a sidebar list with `+`/`−` buttons.
2. **Preview:** the selected photo with the live watermark, a warning bar when settings would
   enlarge it, and a status bar.
3. **Batch Resize:** fit width (presets 320, 640, 800, 1024, 1280, 2560), fit height (240, 480,
   600, 768, 1024, 1280), or scale (12, 25, 50, 75, 100%).
4. **Batch Watermark:** multi-line text with a special-characters menu (© ® ℗ ™ № ▲ ▼ ◀ ▶),
   font, size 1–300 px, colour, bold/italic/underline, opacity, angle with Reset, an optional
   background box, a 3×3 snap grid, and dragging on the preview.
5. **Export:** JPG (quality 10–100) or PNG, an optional suffix (default "Copy"), optional
   numbering, and "Open in Finder when finished".
6. **Misc:** saved preferences, full screen, About, a "Rate this app" window, Website/Support
   links, and a crash-report window.

## Behaviour kept exactly

- **Resize** is an aspect fit, and upscaling is allowed (with a warning).
- **Watermark anchor** is the centre of the text. Snap positions sit 20 px from the edges (the
  vertical inset uses the font's ascent, as in the original). Free positions are fractions of
  the image size.
- **Background box** is the text size plus 10 px × 4 horizontally and × 2 vertically, rotated
  with the text.
- **Opacity** applies to both the text and the box.
- **Output names** are `<name>[ <suffix>][ <number>].<EXT>`, with upper-case extensions.

## Fixed rather than copied

| 1.3.0 | 2.0 |
| --- | --- |
| Export ignored EXIF orientation, so portrait phone photos could come out sideways | Orientation is applied everywhere |
| Photos were keyed by file name; two `IMG_0001.jpg` from different folders overwrote each other | Each photo has its own identity |
| Export order was effectively random, so numbering was unpredictable | Export follows the list order |
| Names were cut at the first dot (`my.trip.jpg` → `my`) | Only the extension is removed |
| Existing files were silently overwritten | Choice of "Keep both" (adds " 2", " 3"…) or "Replace" |
| All metadata and the colour profile were dropped | Metadata and colour profile are kept; location can be removed |
| Rotated text was nudged by a fudge factor to work around a centring quirk | Text is centred exactly at every angle |
| Watermark size only in pixels: tiny on large photos | Size can be a percentage of each photo's width |

## Dropped

- **MBS plugins:** replaced by ImageIO, Core Graphics, AppKit and `UserDefaults`.
- **Threads, timers and `YieldToNextThread`:** replaced by Swift concurrency.
- **Crash-report window:** it posted to a server that no longer exists. Crash reports now come
  through the system.
- **Receipt validation:** already disabled in 1.3.0.
- **OS-version checks** for very old macOS releases.
- **Website/Support links:** the old site no longer exists. The Help menu now points to this
  repository and its issues page.
- **Rate this app:** 2.0 isn't on the App Store yet.

## New in 2.0

- HEIC export.
- Logo (image) watermarks.
- Watermark size as a percentage of the photo's width.
- Parallel processing with progress, Stop, and a per-file failure report.
- Folder import, plus drags from apps like Photos.
- Dark mode, VoiceOver labels, and macOS 14+ on Apple silicon and Intel.

## Decisions

- **macOS only.** The engine uses only cross-platform frameworks, so an iPad version could
  follow.
- **macOS 14 minimum,** the first version with the Observation framework.
- **New app identity** (`com.emediadesigns.photosize2`), separate from the original App Store
  listing.
- **Open source** under the MIT License.

## Not done

- **WebP export:** macOS can read WebP but can't write it, so this would need a third-party
  encoder.
- **Removing more metadata** than location.
- **Pixel-for-pixel comparison** against 1.3.0's exports.

# Architecture

PhotoSize is a single-window SwiftUI app for macOS 14 and later. The code is in three layers:
an **engine** with no UI, a **model** that holds the app's state, and **views**.

```
Views (SwiftUI)  ──reads/writes──▶  AppState (@MainActor @Observable)
      │                                   │
      │ preview                           │ export
      ▼                                   ▼
            Engine (nonisolated, no UI): ImageLoader · ImageRenderer · WatermarkRenderer · Exporter
```

## Engine — `PhotoSize/Engine`

Pure image code built on Core Graphics, Core Text and ImageIO. Every type is `nonisolated` and
`Sendable`, so it can run on any thread and be tested without a window.

| File | Responsibility |
| --- | --- |
| `Settings.swift` | `ResizeSettings`, `WatermarkSettings`, `ExportSettings` and their small enums. All `Codable`, so they can be saved. `ResizeSettings.targetSize(for:)` holds the resize maths. |
| `ImageLoader.swift` | Reads images with `CGImageSource`, **always applying the EXIF orientation**. Downsamples while decoding when the output is smaller, which keeps memory low for large batches. |
| `WatermarkRenderer.swift` | `WatermarkRenderer` lays out and draws text (Core Text) or a logo into a `CGContext`. `ImageRenderer.render` produces a finished image: the photo scaled to the output size, with the watermark on top. |
| `Exporter.swift` | `ExportNaming.plan` decides every output file name up front (suffix, numbering, collisions). `Exporter.export` runs the batch with limited parallelism, reports progress, supports cancellation, records per-file failures, and writes metadata. |

### One drawing path

The preview and the exported file are both made by `ImageRenderer.render`. The preview passes a
`scale` smaller than 1, and the renderer scales its drawing context. The watermark is laid out in
*output pixels*, so a reduced preview is an exact miniature of the export. The original app had
separate preview and export drawing code, and the two could disagree.

### Watermark geometry

- Positions are the **centre** of the watermark, in output pixels from the top-left.
- **Snap** positions keep the watermark a padding away from the edges. For text that's 20 px at
  the original's 50 px reference size (scaled proportionally in "% of width" mode); for a logo,
  2% of the image width.
- **Free** positions are stored as fractions of the image's width and height, so a dragged
  watermark lands in the same relative spot on every photo.
- Rotation is clockwise, about the centre. Opacity applies to the text, the background box and
  the logo.

## Model — `PhotoSize/Model`

| File | Responsibility |
| --- | --- |
| `AppState.swift` | The one source of truth for the window: the photo list, selection, the three settings structs, import progress and export-sheet state. `@MainActor @Observable`. Settings are saved as JSON in `UserDefaults` whenever they change. |
| `Photo.swift` | An imported photo: URL, oriented pixel size and a thumbnail. Identified by a UUID, so two files with the same name never collide. |
| `PhotoImporter.swift` | Turns drops and file choices into photos. It expands folders, filters to supported types, reads thumbnails in parallel, and accepts image data dragged from apps like Photos (copied to a temporary folder). |
| `LogoStore.swift` | Copies the chosen logo into the app's Application Support folder. The logo then survives relaunches without extra sandbox permissions, and doesn't depend on the original file staying put. |

## Views — `PhotoSize/Views`

| File | Responsibility |
| --- | --- |
| `ContentView.swift` | The window: the drop zone when empty, otherwise a split view (photo list, preview, inspector). Handles drops, the Add Photos dialog and the export sheet. |
| `PhotoListView.swift` | Sidebar thumbnails with add/remove buttons and a context menu. |
| `PreviewView.swift` | Renders the selected photo through the engine at screen resolution. Click or drag places the watermark. Shows the output size and an enlarge warning. |
| `InspectorView.swift` | The Batch Resize section. |
| `WatermarkSection.swift` | The Batch Watermark section: Text/Logo, styling, the snap grid and reusable rows. |
| `ExportSheet.swift` | Export options, folder choice, progress and the summary. |
| `DropZoneView.swift` | The empty-window state. |

`PhotoSizeApp.swift` declares the window and the menu commands. `AppInfo.swift` holds the Help
menu links.

## Concurrency

- The app target defaults to **main-actor isolation**. UI and `AppState` run on the main actor.
- Engine work that may take time (loading thumbnails, rendering previews, exporting) is marked
  `@concurrent`, so it runs off the main thread. Batches use task groups with limited parallelism
  (thumbnails: 8 at a time; export: half the processor cores), and results keep the original order.
- Exports can be cancelled. Cancellation is checked before and during each photo.

## Sandbox and files

The app is sandboxed with *user-selected files: read/write*:

- Photos you drop or choose are readable for the session. Folders chosen in the Add Photos
  dialog are held open with security-scoped access.
- The export folder is chosen with an open panel, which grants write access.
- Images dragged from other apps, and the logo, are copied into the app's own container.

## Tests — `PhotoSizeTests`

Swift Testing, running inside the app as the test host:

- **Engine:** resize maths, file naming, watermark layout and rendering (checked pixel by
  pixel), relative sizing, logos, export (orientation, transparency, metadata, HEIC, failures,
  cancellation).
- **Model:** importing, removing photos, saved settings (including older formats), logo storage.
- **Snapshots:** offscreen renders of the window for visual review (see CONTRIBUTING.md).

import AppKit
import SwiftUI
import Testing
@testable import PhotoSize

/// Renders the main window offscreen to PNGs for visual review.
/// Runs only when sample photos have been placed in the app container's
/// `tmp/ShotImages` folder; images are written to `tmp/Snapshots`.
@MainActor
struct WindowSnapshotTests {
    nonisolated static let samples = FileManager.default.temporaryDirectory.appending(path: "ShotImages")
    nonisolated static let output = FileManager.default.temporaryDirectory.appending(path: "Snapshots")
    nonisolated static var hasSamples: Bool { FileManager.default.fileExists(atPath: samples.path) }

    func snapshot(_ state: AppState, name: String, size: CGSize = CGSize(width: 1000, height: 620)) async throws {
        try await snapshot(ContentView().environment(state), name: name, size: size)
    }

    func snapshot(_ view: some View, name: String, size: CGSize, dark: Bool = false) async throws {
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view)
        window.contentView = host
        window.setFrame(CGRect(origin: .zero, size: size), display: true)
        host.layoutSubtreeIfNeeded()
        // Let the preview's async load/render tasks finish.
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
        }
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try FileManager.default.createDirectory(at: Self.output, withIntermediateDirectories: true)
        try #require(rep.representation(using: .png, properties: [:]))
            .write(to: Self.output.appending(path: "\(name).png"))
        window.close()
    }

    @Test(.enabled(if: hasSamples)) func emptyWindow() async throws {
        try await snapshot(AppState(), name: "1-empty")
    }

    @Test(.enabled(if: hasSamples)) func darkMode() async throws {
        try await snapshot(ContentView().environment(AppState()), name: "4-dark-empty",
                           size: CGSize(width: 1000, height: 620), dark: true)
        let state = AppState()
        await state.add([Self.samples])
        try await snapshot(ExportSheet().environment(state), name: "5-dark-export-sheet",
                           size: CGSize(width: 460, height: 560), dark: true)
    }

    @Test(.enabled(if: hasSamples)) func loadedWindow() async throws {
        let state = AppState()
        await state.add([Self.samples])
        #expect(state.photos.count > 1)
        state.selection = [state.photos[1].id]
        try await snapshot(state, name: "2-loaded")
        // The sidebar's translucent material doesn't survive cacheDisplay, so also
        // render the list by itself over an opaque background.
        try await snapshot(PhotoListView(addPhotos: {}).environment(state).background(.white),
                           name: "2b-sidebar", size: CGSize(width: 240, height: 620))

        state.resize.isEnabled = true
        state.resize.mode = .width
        state.resize.width = 2560
        state.watermark.isEnabled = true
        state.watermark.text = "© Copyright 2026 photosize"
        state.watermark.bold = true
        state.watermark.sizeMode = .pixels
        state.watermark.fontSize = 120
        state.watermark.backgroundEnabled = true
        state.watermark.position = .snap(.topCenter)
        try await snapshot(state, name: "3-watermark-enlarged")
    }
}

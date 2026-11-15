import CoreGraphics
import Foundation
import Testing
@testable import PhotoSize

struct ImporterTests {
    @Test func expandsFoldersSkipsNonImagesAndDuplicates() throws {
        let root = try TestImages.tempFolder()
        let sub = root.appending(path: "Sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let img = TestImages.solid(width: 10, height: 10, color: .white)
        let a = TestImages.write(img, to: root.appending(path: "a.png"))
        TestImages.write(img, to: sub.appending(path: "b2.png"))
        TestImages.write(img, to: sub.appending(path: "b10.png"))
        TestImages.write(img, to: root.appending(path: ".hidden.png"))
        try Data("text".utf8).write(to: root.appending(path: "notes.txt"))

        let files = PhotoImporter.imageFiles(in: [root, a])
        // Natural sort order inside folders; the explicitly listed duplicate is dropped.
        #expect(files.map(\.lastPathComponent) == ["a.png", "b2.png", "b10.png"])
    }

    @Test func loadKeepsOrderAndReportsFailures() async throws {
        let root = try TestImages.tempFolder()
        let wide = TestImages.write(TestImages.solid(width: 40, height: 20, color: .white), to: root.appending(path: "wide.png"))
        let bad = root.appending(path: "bad.png")
        try Data("nope".utf8).write(to: bad)
        let tall = TestImages.write(TestImages.solid(width: 20, height: 40, color: .white), to: root.appending(path: "tall.png"))

        let result = await PhotoImporter.load([wide, bad, tall])
        #expect(result.photos.map(\.name) == ["wide.png", "tall.png"])
        #expect(result.photos.first?.pixelSize == CGSize(width: 40, height: 20))
        #expect(result.failures == [bad])
    }
}

@MainActor
struct AppStateTests {
    func folderWithImages(_ count: Int) throws -> [URL] {
        let root = try TestImages.tempFolder()
        return (0..<count).map {
            TestImages.write(TestImages.solid(width: 10, height: 10, color: .white), to: root.appending(path: "p\($0).png"))
        }
    }

    @Test func addSelectsFirstAndSkipsAlreadyImported() async throws {
        let urls = try folderWithImages(3)
        let state = AppState()
        await state.add(urls)
        #expect(state.photos.count == 3)
        #expect(state.previewPhoto?.name == "p0.png")
        #expect(!state.isImporting)

        await state.add(urls)
        #expect(state.photos.count == 3)
    }

    @Test func removeSelectsNeighbor() async throws {
        let state = AppState()
        await state.add(try folderWithImages(3))
        let middle = state.photos[1].id
        state.selection = [middle]
        state.removeSelected()
        #expect(state.photos.map(\.name) == ["p0.png", "p2.png"])
        #expect(state.previewPhoto?.name == "p2.png")

        state.selection = [state.photos[1].id]
        state.removeSelected()
        #expect(state.previewPhoto?.name == "p0.png")

        state.removeAll()
        #expect(state.photos.isEmpty && state.selection.isEmpty)
    }

    @Test func previewViewScale() {
        #expect(PreviewView.viewScale(output: CGSize(width: 400, height: 300), available: CGSize(width: 800, height: 600)) == 1)
        #expect(PreviewView.viewScale(output: CGSize(width: 1600, height: 600), available: CGSize(width: 800, height: 600)) == 0.5)
    }
}

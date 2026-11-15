import Foundation
import Testing
@testable import PhotoSize

struct ExportNamingTests {
    let folder = URL(filePath: "/out")
    func src(_ path: String) -> URL { URL(filePath: path) }

    func names(_ sources: [URL], _ settings: ExportSettings, existing: Set<String> = []) -> [String] {
        ExportNaming.plan(sources: sources, folder: folder, settings: settings,
                          fileExists: { existing.contains($0.lastPathComponent) })
            .map(\.destination.lastPathComponent)
    }

    @Test func plainName() {
        #expect(names([src("/a/IMG_1.jpeg")], ExportSettings()) == ["IMG_1.JPG"])
    }

    @Test func pngExtension() {
        var s = ExportSettings(); s.format = .png
        #expect(names([src("/a/IMG_1.jpeg")], s) == ["IMG_1.PNG"])
    }

    @Test func suffixAndNumbering() {
        var s = ExportSettings()
        s.appendSuffix = true; s.suffix = "Copy"
        s.numberFiles = true; s.numberStart = 7
        #expect(names([src("/a/x.jpg"), src("/a/y.jpg")], s) == ["x Copy 7.JPG", "y Copy 8.JPG"])
    }

    @Test func numberingFollowsListOrder() {
        var s = ExportSettings(); s.numberFiles = true; s.numberStart = 1
        #expect(names([src("/a/z.jpg"), src("/a/a.jpg"), src("/a/m.jpg")], s) == ["z 1.JPG", "a 2.JPG", "m 3.JPG"])
    }

    @Test func blankSuffixIsIgnored() {
        var s = ExportSettings(); s.appendSuffix = true; s.suffix = "  "
        #expect(names([src("/a/x.jpg")], s) == ["x.JPG"])
    }

    @Test func keepsDotsInName() {
        // The Xojo app cut names at the first dot ("my.trip.jpg" → "my").
        #expect(names([src("/a/my.trip.jpg")], ExportSettings()) == ["my.trip.JPG"])
    }

    @Test func sameNameFromDifferentFoldersDoesNotCollide() {
        #expect(names([src("/a/IMG_1.jpg"), src("/b/IMG_1.jpg"), src("/c/img_1.png")], ExportSettings())
                == ["IMG_1.JPG", "IMG_1 2.JPG", "img_1 3.JPG"])
    }

    @Test func keepBothAvoidsExistingFiles() {
        #expect(names([src("/a/x.jpg")], ExportSettings(), existing: ["x.JPG", "x 2.JPG"]) == ["x 3.JPG"])
    }

    @Test func replaceOverwritesExistingFiles() {
        var s = ExportSettings(); s.conflictPolicy = .replace
        #expect(names([src("/a/x.jpg")], s, existing: ["x.JPG"]) == ["x.JPG"])
    }
}

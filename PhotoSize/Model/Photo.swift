import CoreGraphics
import Foundation

/// One imported image in the batch.
nonisolated struct Photo: Identifiable, Equatable, @unchecked Sendable {
    let id = UUID()
    let url: URL
    /// Pixel size after EXIF orientation.
    let pixelSize: CGSize
    /// Sidebar thumbnail (immutable `CGImage`, safe to share).
    let thumbnail: CGImage

    var name: String { url.lastPathComponent }

    static func == (a: Photo, b: Photo) -> Bool { a.id == b.id }
}

import AppKit
import Foundation
import UniformTypeIdentifiers

/// Turns dropped or chosen items into `Photo`s.
nonisolated enum PhotoImporter {

    struct Result: Sendable {
        var photos: [Photo] = []
        /// Image files that could not be read.
        var failures: [URL] = []
    }

    /// File types the app accepts.
    static let imageTypes: [UTType] = [.jpeg, .png, .tiff, .gif, .heic, .heif]

    static func isSupportedImage(_ url: URL) -> Bool {
        guard let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
                ?? UTType(filenameExtension: url.pathExtension) else { return false }
        return imageTypes.contains { type.conforms(to: $0) }
    }

    /// Expands folders (recursively, skipping hidden files and packages) and keeps
    /// only supported image files, in the order given. Duplicates are removed.
    static func imageFiles(in urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        var result: [URL] = []
        func add(_ url: URL) {
            let key = url.standardizedFileURL.resolvingSymlinksInPath()
            if isSupportedImage(url), seen.insert(key).inserted { result.append(url) }
        }
        for url in urls {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                let enumerator = FileManager.default.enumerator(
                    at: url, includingPropertiesForKeys: [.contentTypeKey, .isDirectoryKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants])
                let children = (enumerator?.allObjects as? [URL] ?? [])
                    .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
                children.forEach(add)
            } else {
                add(url)
            }
        }
        return result
    }

    /// Reads size and thumbnail for each file, several at a time. Order is preserved.
    static func load(_ urls: [URL],
                     progress: @Sendable (_ completed: Int, _ total: Int) -> Void = { _, _ in }) async -> Result {
        var slots = [Photo?](repeating: nil, count: urls.count)
        await withTaskGroup(of: (Int, Photo?).self) { group in
            var next = 0, completed = 0
            func enqueue() {
                guard next < urls.count else { return }
                let index = next, url = urls[index]
                next += 1
                group.addTask { (index, await loadPhoto(url)) }
            }
            for _ in 0..<min(8, urls.count) { enqueue() }
            while let (index, photo) = await group.next() {
                slots[index] = photo
                completed += 1
                progress(completed, urls.count)
                enqueue()
            }
        }
        var result = Result()
        for (url, photo) in zip(urls, slots) {
            if let photo { result.photos.append(photo) } else { result.failures.append(url) }
        }
        return result
    }

    @concurrent
    static func loadPhoto(_ url: URL) async -> Photo? {
        guard let info = try? ImageLoader.info(for: url),
              let thumbnail = try? ImageLoader.thumbnail(at: url, maxPixelSize: 400) else { return nil }
        return Photo(url: url, pixelSize: info.pixelSize, thumbnail: thumbnail)
    }

    // MARK: Drag and drop

    /// Where images dragged from apps like Photos (file promises / raw image data) are saved.
    static var receivedFilesFolder: URL {
        FileManager.default.temporaryDirectory.appending(path: "Received", directoryHint: .isDirectory)
    }

    /// File URLs for dropped items. Finder items arrive as file URLs; items from
    /// Photos and other apps arrive as image data and are copied to a temporary folder.
    @MainActor
    static func urls(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            if let url = await fileURL(from: provider) {
                urls.append(url)
            } else if let url = await receivedImage(from: provider) {
                urls.append(url)
            }
        }
        return urls
    }

    @MainActor
    private static func fileURL(from provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    @MainActor
    private static func receivedImage(from provider: NSItemProvider) async -> URL? {
        guard let typeID = provider.registeredTypeIdentifiers.first(where: {
            UTType($0)?.conforms(to: .image) == true
        }) else { return nil }
        let suggested = provider.suggestedName
        return await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: typeID) { tempURL, _ in
                // The system deletes `tempURL` when this handler returns, so copy it now.
                guard let tempURL else { return continuation.resume(returning: nil) }
                let folder = receivedFilesFolder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
                var name = suggested ?? tempURL.deletingPathExtension().lastPathComponent
                let ext = tempURL.pathExtension.isEmpty
                    ? (UTType(typeID)?.preferredFilenameExtension ?? "jpg") : tempURL.pathExtension
                if (name as NSString).pathExtension.isEmpty { name += "." + ext }
                let destination = folder.appending(path: name)
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: tempURL, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

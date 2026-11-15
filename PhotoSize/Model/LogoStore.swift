import Foundation

/// Keeps the logo watermark in the app's own storage, so it survives relaunches
/// without extra sandbox permissions and doesn't depend on the original file staying put.
nonisolated enum LogoStore {
    enum LogoError: LocalizedError {
        case notAnImage(URL)

        var errorDescription: String? {
            switch self {
            case .notAnImage(let url): "“\(url.lastPathComponent)” isn't an image PhotoSize can use as a logo."
            }
        }
    }

    static var defaultFolder: URL {
        URL.applicationSupportDirectory.appending(path: "Logos", directoryHint: .isDirectory)
    }

    /// Copies `source` into `folder` under a fresh name and removes any earlier logos there.
    /// - Returns: The copy's URL.
    static func store(_ source: URL, in folder: URL = defaultFolder) throws -> URL {
        // Make sure it's an image before replacing the current logo.
        guard (try? ImageLoader.info(for: source)) != nil else { throw LogoError.notAnImage(source) }

        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        let destination = folder.appending(path: "logo-\(UUID().uuidString).\(ext)")
        try fm.copyItem(at: source, to: destination)

        for old in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        where old.lastPathComponent != destination.lastPathComponent {
            try? fm.removeItem(at: old)
        }
        return destination
    }

    /// Removes every stored logo.
    static func removeAll(in folder: URL = defaultFolder) {
        try? FileManager.default.removeItem(at: folder)
    }
}

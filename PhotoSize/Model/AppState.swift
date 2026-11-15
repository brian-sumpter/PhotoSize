import Foundation
import Observation

/// Everything the main window shows. Lives for the whole app session.
@MainActor @Observable
final class AppState {
    private(set) var photos: [Photo] = []
    var selection: Set<Photo.ID> = []

    var resize = ResizeSettings() { didSet { save(resize, key: Keys.resize) } }
    var watermark = WatermarkSettings() { didSet { save(watermark, key: Keys.watermark) } }
    var export = ExportSettings() { didSet { save(export, key: Keys.export) } }

    /// Where settings are saved between launches; nil keeps them in memory only (tests, previews).
    @ObservationIgnored private let defaults: UserDefaults?

    enum Keys {
        static let resize = "ResizeSettings"
        static let watermark = "WatermarkSettings"
        static let export = "ExportSettings"
    }

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        if let value: ResizeSettings = load(Keys.resize) { resize = value }
        if let value: WatermarkSettings = load(Keys.watermark) { watermark = value }
        if let value: ExportSettings = load(Keys.export) { export = value }
    }

    private func load<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save(_ value: some Encodable, key: String) {
        guard let defaults, let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    /// Non-nil while an import is running: (done, total).
    private(set) var importProgress: (completed: Int, total: Int)?
    /// Files from the last import that couldn't be read, shown in an alert.
    var importFailures: [URL] = []

    /// Folders and files the user granted through the open panel; kept open for the session
    /// so exported reads still work.
    private var securityScopedURLs: [URL] = []

    /// The photo shown in the preview: the first selected one, in list order.
    var previewPhoto: Photo? {
        photos.first { selection.contains($0.id) }
    }

    var isImporting: Bool { importProgress != nil }

    /// Whether the export sheet is open (driven by the toolbar button and File ▸ Export…).
    var isExportSheetShown = false

    var canExport: Bool { !photos.isEmpty && !isImporting }

    // MARK: Adding and removing

    /// Adds images from files and folders. Already-imported files are skipped.
    func add(_ urls: [URL], securityScoped: Bool = false) async {
        if securityScoped {
            for url in urls where url.startAccessingSecurityScopedResource() {
                securityScopedURLs.append(url)
            }
        }

        let existing = Set(photos.map { $0.url.standardizedFileURL.resolvingSymlinksInPath() })
        let files = await Task.detached { PhotoImporter.imageFiles(in: urls) }.value
            .filter { !existing.contains($0.standardizedFileURL.resolvingSymlinksInPath()) }
        guard !files.isEmpty else { return }

        importProgress = (0, files.count)
        let result = await PhotoImporter.load(files) { completed, total in
            Task { @MainActor [weak self] in
                guard let self, self.importProgress != nil else { return }
                self.importProgress = (completed, total)
            }
        }
        importProgress = nil

        let wasEmpty = photos.isEmpty
        photos.append(contentsOf: result.photos)
        importFailures = result.failures
        if wasEmpty || selection.isEmpty, let first = result.photos.first {
            selection = [first.id]
        }
    }

    /// Removes photos and selects the item that took the place of the first removed one.
    func remove(_ ids: Set<Photo.ID>) {
        guard let firstIndex = photos.firstIndex(where: { ids.contains($0.id) }) else { return }
        photos.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
        if selection.isEmpty, !photos.isEmpty {
            selection = [photos[min(firstIndex, photos.count - 1)].id]
        }
    }

    func removeSelected() {
        remove(selection)
    }

    // MARK: Logo watermark

    /// Copies the chosen image into the app's storage and uses it as the logo watermark.
    /// - Returns: An error message for the user, or nil on success.
    @discardableResult
    func setLogo(from url: URL, folder: URL = LogoStore.defaultFolder) -> String? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            watermark.logoURL = try LogoStore.store(url, in: folder)
            watermark.kind = .logo
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func removeAll() {
        photos.removeAll()
        selection.removeAll()
    }
}

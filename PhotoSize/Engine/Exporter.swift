import CoreGraphics
import Foundation
import ImageIO

nonisolated struct ExportJob: Hashable, Sendable {
    let source: URL
    let destination: URL
}

nonisolated struct ExportFailure: Sendable {
    let source: URL
    let message: String
}

nonisolated struct ExportResult: Sendable {
    var written: [URL] = []
    var failures: [ExportFailure] = []
}

nonisolated enum ExportError: LocalizedError {
    case cannotCreateFile(URL)
    case writeFailed(URL)

    var errorDescription: String? {
        switch self {
        case .cannotCreateFile(let url): "“\(url.lastPathComponent)” could not be created."
        case .writeFailed(let url): "“\(url.lastPathComponent)” could not be written."
        }
    }
}

// MARK: - Naming

nonisolated enum ExportNaming {

    /// Output name without the "taken" check:
    /// `<name>[ <suffix>][ <number>].<EXT>`
    static func baseName(for source: URL, index: Int, settings: ExportSettings) -> String {
        var name = source.deletingPathExtension().lastPathComponent
        let suffix = settings.suffix.trimmingCharacters(in: .whitespaces)
        if settings.appendSuffix, !suffix.isEmpty { name += " " + suffix }
        if settings.numberFiles { name += " \(settings.numberStart + index)" }
        return name
    }

    /// Destination for every source, in order. Names never collide within the batch,
    /// and with `.keepBoth` they never collide with files already in `folder`.
    static func plan(sources: [URL],
                     folder: URL,
                     settings: ExportSettings,
                     fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> [ExportJob] {
        var used = Set<String>()  // lower-cased: the default macOS volume is case-insensitive
        return sources.enumerated().map { index, source in
            let base = baseName(for: source, index: index, settings: settings)
            let ext = settings.format.fileExtension
            var candidate = "\(base).\(ext)"
            var counter = 2
            while used.contains(candidate.lowercased())
                    || (settings.conflictPolicy == .keepBoth && fileExists(folder.appending(path: candidate))) {
                candidate = "\(base) \(counter).\(ext)"
                counter += 1
            }
            used.insert(candidate.lowercased())
            return ExportJob(source: source, destination: folder.appending(path: candidate))
        }
    }
}

// MARK: - Exporter

nonisolated enum Exporter {

    /// Exports every job, at most `maxConcurrent` images at a time.
    /// Failures of individual files are collected instead of stopping the batch.
    /// Throws `CancellationError` if the task is cancelled.
    static func export(_ jobs: [ExportJob],
                       resize: ResizeSettings,
                       watermark: WatermarkSettings,
                       settings: ExportSettings,
                       maxConcurrent: Int = max(2, ProcessInfo.processInfo.activeProcessorCount / 2),
                       progress: @Sendable (_ completed: Int, _ total: Int) -> Void = { _, _ in }) async throws -> ExportResult {
        var outcomes = [Result<URL, Error>?](repeating: nil, count: jobs.count)
        var completed = 0

        try await withThrowingTaskGroup(of: (Int, Result<URL, Error>).self) { group in
            var next = 0
            func enqueue() {
                guard next < jobs.count else { return }
                let index = next, job = jobs[index]
                next += 1
                group.addTask {
                    try Task.checkCancellation()
                    do {
                        try await process(job, resize: resize, watermark: watermark, settings: settings)
                        return (index, .success(job.destination))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            for _ in 0..<min(maxConcurrent, jobs.count) { enqueue() }
            while let (index, outcome) = try await group.next() {
                outcomes[index] = outcome
                completed += 1
                progress(completed, jobs.count)
                enqueue()
            }
        }

        var result = ExportResult()
        for (job, outcome) in zip(jobs, outcomes) {
            switch outcome {
            case .success(let url): result.written.append(url)
            case .failure(let error): result.failures.append(ExportFailure(source: job.source, message: error.localizedDescription))
            case nil: break
            }
        }
        return result
    }

    /// Load → resize → watermark → write, for one image.
    @concurrent
    static func process(_ job: ExportJob,
                        resize: ResizeSettings,
                        watermark: WatermarkSettings,
                        settings: ExportSettings) async throws {
        let source = try ImageLoader.source(for: job.source)
        let info = try ImageLoader.info(for: source, url: job.source)
        let target = resize.targetSize(for: info.pixelSize)

        // Let ImageIO downsample when shrinking (fast, low memory);
        // otherwise load full size and let the renderer scale up.
        let fullLongest = Int(max(info.pixelSize.width, info.pixelSize.height))
        let targetLongest = Int(max(target.width, target.height).rounded(.up))
        let image = try ImageLoader.image(from: source, url: job.source,
                                          maxPixelSize: min(targetLongest, fullLongest))
        try Task.checkCancellation()

        let output = try ImageRenderer.render(image, outputSize: target, watermark: watermark,
                                              opaqueBackground: settings.format.needsOpaqueBackground)
        try write(output, to: job.destination, sourceProperties: info.properties, settings: settings)
    }

    static func write(_ image: CGImage, to url: URL, sourceProperties: [String: Any], settings: ExportSettings) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, settings.format.typeIdentifier as CFString, 1, nil) else {
            throw ExportError.cannotCreateFile(url)
        }
        var properties = settings.keepMetadata
            ? metadata(from: sourceProperties, removeLocation: settings.removeLocation, outputSize: CGSize(width: image.width, height: image.height))
            : [:]
        // The pixels are already upright.
        properties[kCGImagePropertyOrientation as String] = 1
        if settings.format.usesQuality {
            properties[kCGImageDestinationLossyCompressionQuality as String] = Double(min(max(settings.quality, 1), 100)) / 100
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ExportError.writeFailed(url) }
    }

    /// The parts of the source metadata worth carrying over, fixed up for the new image.
    static func metadata(from source: [String: Any], removeLocation: Bool, outputSize: CGSize) -> [String: Any] {
        var keys: [CFString] = [
            kCGImagePropertyExifDictionary, kCGImagePropertyExifAuxDictionary,
            kCGImagePropertyTIFFDictionary, kCGImagePropertyIPTCDictionary,
            kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight,
        ]
        if !removeLocation { keys.append(kCGImagePropertyGPSDictionary) }

        var result: [String: Any] = [:]
        for key in keys {
            if let value = source[key as String] { result[key as String] = value }
        }
        if var tiff = result[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            tiff[kCGImagePropertyTIFFOrientation as String] = 1
            result[kCGImagePropertyTIFFDictionary as String] = tiff
        }
        if var exif = result[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            exif[kCGImagePropertyExifPixelXDimension as String] = Int(outputSize.width)
            exif[kCGImagePropertyExifPixelYDimension as String] = Int(outputSize.height)
            result[kCGImagePropertyExifDictionary as String] = exif
        }
        return result
    }
}

import AppKit
import SwiftUI

/// Export options, then progress, then a summary. Writes every photo in the batch.
struct ExportSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case options
        case exporting(completed: Int, total: Int)
        case finished(ExportResult, folder: URL)
    }

    @State private var phase = Phase.options
    @State private var exportTask: Task<Void, Never>?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch phase {
            case .options:
                ExportOptionsForm()
                footer {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Export…") { chooseFolderAndExport() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(state.photos.isEmpty)
                }
            case .exporting(let completed, let total):
                ExportProgressView(completed: completed, total: total)
                footer {
                    Button("Stop", role: .cancel) { exportTask?.cancel() }
                        .keyboardShortcut(.cancelAction)
                }
            case .finished(let result, let folder):
                ExportSummaryView(result: result, folder: folder)
                footer {
                    Button("Show in Finder") { reveal(result, in: folder) }
                        .disabled(result.written.isEmpty)
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 460)
        .interactiveDismissDisabled(isExporting)
        .alert("Export Failed", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            // Saved settings may name a format this Mac can't write (e.g. HEIC without an HEVC encoder).
            if !ExportFormat.available.contains(state.export.format) {
                state.export.format = .jpeg
            }
        }
        .onDisappear { exportTask?.cancel() }
    }

    private var isExporting: Bool {
        if case .exporting = phase { true } else { false }
    }

    private func footer(@ViewBuilder _ buttons: () -> some View) -> some View {
        HStack {
            Spacer()
            buttons()
        }
        .padding(16)
    }

    // MARK: Exporting

    private func chooseFolderAndExport() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export Here"
        panel.message = "Choose a folder for the \(state.photos.count == 1 ? "exported photo" : "\(state.photos.count) exported photos")."
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let folder = panel.url else { return }
            startExport(to: folder)
        }
        // Attach to the sheet's window when there is one; otherwise show the panel on its own.
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    private func startExport(to folder: URL) {
        let sources = state.photos.map(\.url)
        let settings = state.export
        let resize = state.resize
        let watermark = state.watermark
        let jobs = ExportNaming.plan(sources: sources, folder: folder, settings: settings)
        phase = .exporting(completed: 0, total: jobs.count)

        exportTask = Task {
            let accessing = folder.startAccessingSecurityScopedResource()
            defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
            do {
                let result = try await Exporter.export(jobs, resize: resize, watermark: watermark, settings: settings) { done, total in
                    Task { @MainActor in
                        if case .exporting = phase { phase = .exporting(completed: done, total: total) }
                    }
                }
                phase = .finished(result, folder: folder)
                if settings.revealInFinder, !result.written.isEmpty {
                    reveal(result, in: folder)
                }
            } catch is CancellationError {
                phase = .options
            } catch {
                phase = .options
                errorMessage = error.localizedDescription
            }
        }
    }

    private func reveal(_ result: ExportResult, in folder: URL) {
        if result.written.isEmpty {
            NSWorkspace.shared.open(folder)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(result.written)
        }
    }
}

// MARK: - Options

private struct ExportOptionsForm: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        Form {
            Section {
                Picker("Format", selection: $state.export.format) {
                    ForEach(ExportFormat.available, id: \.self) { format in
                        Text(format.title).tag(format)
                    }
                }
                .pickerStyle(.segmented)

                if state.export.format.usesQuality {
                    LabeledContent("Quality") {
                        HStack {
                            Slider(value: qualityBinding, in: 10...100, step: 5)
                                .labelsHidden()
                            Text("\(state.export.quality)%")
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }
            } header: {
                Text("Export Format")
            }

            Section {
                HStack {
                    Toggle("Append suffix", isOn: $state.export.appendSuffix)
                    Spacer()
                    TextField("Suffix", text: $state.export.suffix)
                        .labelsHidden()
                        .frame(width: 120)
                        .disabled(!state.export.appendSuffix)
                }
                HStack {
                    Toggle("Number files from", isOn: $state.export.numberFiles)
                    Spacer()
                    Group {
                        TextField("Start", value: $state.export.numberStart, format: .number.grouping(.never))
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Stepper("Start", value: $state.export.numberStart, in: 0...999_999)
                            .labelsHidden()
                    }
                    .disabled(!state.export.numberFiles)
                }

                Picker("If a file already exists", selection: $state.export.conflictPolicy) {
                    Text("Keep both").tag(ConflictPolicy.keepBoth)
                    Text("Replace it").tag(ConflictPolicy.replace)
                }

                LabeledContent("Example") {
                    Text(exampleName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } header: {
                Text("File Names")
            }

            Section {
                Toggle("Keep photo info (date, camera, copyright)", isOn: $state.export.keepMetadata)
                Toggle("Remove location", isOn: $state.export.removeLocation)
                    .disabled(!state.export.keepMetadata)
                Toggle("Show in Finder when finished", isOn: $state.export.revealInFinder)
            } header: {
                Text("Options")
            } footer: {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var qualityBinding: Binding<Double> {
        Binding(get: { Double(state.export.quality) }, set: { state.export.quality = Int($0) })
    }

    private var exampleName: String {
        guard let first = state.photos.first else { return "—" }
        return "\(ExportNaming.baseName(for: first.url, index: 0, settings: state.export)).\(state.export.format.fileExtension)"
    }

    private var summary: String {
        let count = state.photos.count == 1 ? "1 photo" : "\(state.photos.count) photos"
        var parts = ["\(count) as \(state.export.format.title)"]
        if state.resize.isEnabled {
            let size = switch state.resize.mode {
            case .width: "\(state.resize.width) px wide"
            case .height: "\(state.resize.height) px tall"
            case .scale: "at \(state.resize.scalePercent)%"
            }
            parts.append(size)
        } else {
            parts.append("at original size")
        }
        if state.watermark.isVisible { parts.append("with watermark") }
        return "Exports " + parts.joined(separator: ", ") + "."
    }
}

// MARK: - Progress and summary

private struct ExportProgressView: View {
    let completed: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Exporting…")
                .font(.headline)
            ProgressView(value: Double(completed), total: Double(max(total, 1)))
            Text("\(completed) of \(total) photos")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding([.horizontal, .top], 20)
    }
}

private struct ExportSummaryView: View {
    let result: ExportResult
    let folder: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: result.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(result.failures.isEmpty ? Color.green : Color.orange)
            Text("Saved to “\(folder.lastPathComponent)”.")
                .foregroundStyle(.secondary)
            if !result.failures.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(result.failures, id: \.source) { failure in
                            Text("\(failure.source.lastPathComponent): \(failure.message)")
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            }
        }
        .padding([.horizontal, .top], 20)
    }

    private var title: String {
        let done = result.written.count == 1 ? "1 photo exported" : "\(result.written.count) photos exported"
        if result.failures.isEmpty { return done }
        return "\(done), \(result.failures.count) failed"
    }
}

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var isDropTargeted = false
    @State private var isChoosingFiles = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @AppStorage("InspectorShown") private var isInspectorShown = true

    var body: some View {
        @Bindable var state = state
        Group {
            if state.photos.isEmpty {
                DropZoneView(isTargeted: isDropTargeted, addPhotos: chooseFiles)
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    PhotoListView(addPhotos: chooseFiles)
                        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
                } detail: {
                    Group {
                        if let photo = state.previewPhoto {
                            PreviewView(photo: photo)
                        } else {
                            ContentUnavailableView("No Photo Selected", systemImage: "photo",
                                                   description: Text("Select a photo in the sidebar to preview it."))
                        }
                    }
                    .inspector(isPresented: $isInspectorShown) {
                        InspectorView()
                            .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
                    }
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Export…", systemImage: "square.and.arrow.up") {
                                state.isExportSheetShown = true
                            }
                            .help("Export the photos with the current settings")
                            .disabled(!state.canExport)
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Button("Settings", systemImage: "sidebar.trailing") {
                                isInspectorShown.toggle()
                            }
                            .help(isInspectorShown ? "Hide batch settings" : "Show batch settings")
                        }
                    }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 520)
        .overlay {
            if let progress = state.importProgress {
                ImportProgressView(completed: progress.completed, total: progress.total)
            }
        }
        .overlay {
            if isDropTargeted && !state.photos.isEmpty {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
            Task {
                let urls = await PhotoImporter.urls(from: providers)
                await state.add(urls)
            }
            return true
        }
        .fileImporter(isPresented: $isChoosingFiles,
                      allowedContentTypes: PhotoImporter.imageTypes + [.folder],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                Task { await state.add(urls, securityScoped: true) }
            }
        }
        .fileDialogMessage("Select photos or folders for batch processing")
        .fileDialogConfirmationLabel("Add Photos")
        .alert(failureTitle, isPresented: .init(
            get: { !state.importFailures.isEmpty },
            set: { if !$0 { state.importFailures = [] } })) {
            Button("OK") { state.importFailures = [] }
        } message: {
            Text(state.importFailures.prefix(10).map(\.lastPathComponent).joined(separator: "\n")
                 + (state.importFailures.count > 10 ? "\n…" : ""))
        }
        .sheet(isPresented: $state.isExportSheetShown) {
            ExportSheet()
        }
        .focusedSceneValue(\.addPhotos, chooseFiles)
        .navigationTitle("PhotoSize")
        .navigationSubtitle(subtitle)
    }

    private func chooseFiles() {
        isChoosingFiles = true
    }

    private var subtitle: String {
        switch state.photos.count {
        case 0: ""
        case 1: "1 photo"
        case let n: "\(n) photos"
        }
    }

    private var failureTitle: String {
        state.importFailures.count == 1
            ? "1 file couldn’t be opened as an image."
            : "\(state.importFailures.count) files couldn’t be opened as images."
    }
}

private struct ImportProgressView: View {
    let completed: Int
    let total: Int

    var body: some View {
        VStack(spacing: 10) {
            ProgressView(value: Double(completed), total: Double(max(total, 1)))
                .frame(width: 220)
            Text("Loading \(completed) of \(total)…")
                .font(.callout)
                .monospacedDigit()
        }
        .padding(20)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        .shadow(radius: 10)
    }
}

// MARK: - Menu command plumbing

struct AddPhotosActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var addPhotos: (() -> Void)? {
        get { self[AddPhotosActionKey.self] }
        set { self[AddPhotosActionKey.self] = newValue }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
        .frame(width: 1000, height: 600)
}

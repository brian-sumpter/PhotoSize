import SwiftUI

@main
struct PhotoSizeApp: App {
    @State private var state = AppState(defaults: .standard)

    var body: some Scene {
        // One window, like the original app.
        Window("PhotoSize", id: "main") {
            ContentView()
                .environment(state)
        }
        .defaultSize(width: 1000, height: 620)
        .commands {
            PhotoCommands(state: state)
        }
    }
}

private struct PhotoCommands: Commands {
    let state: AppState
    @FocusedValue(\.addPhotos) private var addPhotos
    @AppStorage("InspectorShown") private var isInspectorShown = true

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Photos…") { addPhotos?() }
                .keyboardShortcut("o")
                .disabled(addPhotos == nil)
            Divider()
            Button("Export…") { state.isExportSheetShown = true }
                .keyboardShortcut("e")
                .disabled(!state.canExport || state.isExportSheetShown)
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Remove from Batch") { state.removeSelected() }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(state.selection.isEmpty)
            Button("Remove All Photos") { state.removeAll() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(state.photos.isEmpty)
        }
        CommandGroup(after: .sidebar) {
            Button(isInspectorShown ? "Hide Batch Settings" : "Show Batch Settings") {
                isInspectorShown.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(state.photos.isEmpty)
        }
        CommandGroup(replacing: .help) {
            Link("PhotoSize on GitHub", destination: AppInfo.repository)
            Link("Report an Issue…", destination: AppInfo.issues)
        }
    }
}

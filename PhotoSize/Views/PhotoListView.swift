import SwiftUI

/// Sidebar: thumbnails of every photo in the batch.
struct PhotoListView: View {
    @Environment(AppState.self) private var state
    let addPhotos: () -> Void

    var body: some View {
        @Bindable var state = state
        List(selection: $state.selection) {
            ForEach(state.photos) { photo in
                PhotoRow(photo: photo)
                    .tag(photo.id)
            }
        }
        .contextMenu(forSelectionType: Photo.ID.self) { ids in
            if !ids.isEmpty {
                Button("Show in Finder") {
                    let urls = state.photos.filter { ids.contains($0.id) }.map(\.url)
                    NSWorkspace.shared.activateFileViewerSelecting(urls)
                }
                Divider()
                Button(ids.count == 1 ? "Remove from Batch" : "Remove \(ids.count) Photos from Batch",
                       role: .destructive) { state.remove(ids) }
            }
        }
        .onDeleteCommand { state.removeSelected() }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            ControlGroup {
                Button("Add Photos…", systemImage: "plus", action: addPhotos)
                    .help("Add more photos to the batch")
                Button("Remove", systemImage: "minus") { state.removeSelected() }
                    .disabled(state.selection.isEmpty)
                    .help("Remove the selected photos from the batch")
            }
            .labelStyle(.iconOnly)
            .controlSize(.small)
            .fixedSize()

            Text(state.photos.count == 1 ? "1 photo" : "\(state.photos.count) photos")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.bar)
    }
}

private struct PhotoRow: View {
    let photo: Photo

    var body: some View {
        VStack(spacing: 6) {
            Image(decorative: photo.thumbnail, scale: 2)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 110)
                .clipShape(.rect(cornerRadius: 4))
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            Text(photo.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Text("\(Int(photo.pixelSize.width)) × \(Int(photo.pixelSize.height))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

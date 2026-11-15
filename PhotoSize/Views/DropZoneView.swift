import SwiftUI

/// Empty state: shown until photos are added.
struct DropZoneView: View {
    let isTargeted: Bool
    let addPhotos: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(.banner)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 400)
                .clipShape(.rect(cornerRadius: 8))
                .accessibilityLabel("PhotoSize")

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                .symbolEffect(.bounce, value: isTargeted)

            Text("Drag and drop your photos here")
                .font(.title3)
                .foregroundStyle(.secondary)

            Button("Add Photos…", action: addPhotos)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(maxWidth: 520)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                              style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .background(RoundedRectangle(cornerRadius: 16).fill(.background.secondary))
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.15), value: isTargeted)
    }
}

#Preview {
    DropZoneView(isTargeted: false, addPhotos: {})
        .frame(width: 900, height: 560)
}

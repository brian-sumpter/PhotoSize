import SwiftUI

/// Center pane: the selected photo exactly as it will be exported, scaled to fit.
struct PreviewView: View {
    @Environment(AppState.self) private var state
    @Environment(\.displayScale) private var displayScale
    let photo: Photo

    @State private var source: LoadedSource?
    @State private var rendered: CGImage?

    /// Room left around the image and for the size label under it.
    private let margin: CGFloat = 24
    private let labelHeight: CGFloat = 28

    var body: some View {
        GeometryReader { geometry in
            let output = state.resize.targetSize(for: photo.pixelSize)
            let viewScale = Self.viewScale(output: output, available: CGSize(
                width: geometry.size.width - margin * 2,
                height: geometry.size.height - margin * 2 - labelHeight))
            let displaySize = CGSize(width: output.width * viewScale, height: output.height * viewScale)
            // Render no more pixels than the screen shows, and never more than the output has.
            let renderScale = min(1, viewScale * displayScale)

            VStack(spacing: 8) {
                ZStack {
                    if let rendered {
                        Image(decorative: rendered, scale: 1)
                            .resizable()
                            .interpolation(.high)
                    } else {
                        Rectangle().fill(.quaternary)
                    }
                }
                .frame(width: displaySize.width, height: displaySize.height)
                .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
                .contentShape(.rect)
                .gesture(placeWatermark(in: displaySize), including: state.watermark.isEnabled ? .all : .subviews)
                .modifier(GrabPointer(isActive: state.watermark.isEnabled))
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isImage)
                .accessibilityLabel("Preview of \(photo.name), \(Int(output.width)) by \(Int(output.height)) pixels")
                .accessibilityHint(state.watermark.isEnabled ? "Click or drag to place the watermark" : "")

                SizeLabel(output: output, width: displaySize.width)
                    .frame(height: labelHeight - 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: photo.id) {
                source = nil
                rendered = nil
                source = await Self.loadSource(photo)
            }
            .task(id: RenderKey(source: source?.id, output: output, watermark: state.watermark, scale: renderScale)) {
                guard let source, source.id == photo.id else { return }
                rendered = await Self.render(source.image, output: output, watermark: state.watermark, scale: renderScale)
            }
        }
        .background(Color(white: 0.16))
        .safeAreaInset(edge: .top, spacing: 0) {
            if state.resize.enlarges(photo.pixelSize) {
                EnlargeWarning()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StatusBar(photo: photo, output: state.resize.targetSize(for: photo.pixelSize))
        }
    }

    // MARK: Helpers

    /// Click or drag on the image to center the watermark there.
    private func placeWatermark(in displaySize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                state.watermark.position = Self.freePosition(at: drag.location, in: displaySize)
            }
    }

    /// A point in the displayed image as a free position (fractions of width and height, clamped).
    static func freePosition(at point: CGPoint, in size: CGSize) -> WatermarkPosition {
        guard size.width > 0, size.height > 0 else { return .snap(.center) }
        return .free(x: min(max(point.x / size.width, 0), 1),
                     y: min(max(point.y / size.height, 0), 1))
    }

    /// Points per output pixel: 100% unless the output is bigger than the room available.
    static func viewScale(output: CGSize, available: CGSize) -> CGFloat {
        guard output.width > 0, output.height > 0, available.width > 0, available.height > 0 else { return 0 }
        return min(1, available.width / output.width, available.height / output.height)
    }

    struct LoadedSource: @unchecked Sendable {
        let id: Photo.ID
        let image: CGImage
    }

    struct RenderKey: Equatable {
        let source: Photo.ID?
        let output: CGSize
        let watermark: WatermarkSettings
        let scale: CGFloat
    }

    /// The source, downsampled enough for any window size.
    @concurrent
    static func loadSource(_ photo: Photo) async -> LoadedSource? {
        let longest = Int(max(photo.pixelSize.width, photo.pixelSize.height))
        guard let image = try? ImageLoader.image(at: photo.url, maxPixelSize: min(longest, 3000)) else { return nil }
        return LoadedSource(id: photo.id, image: image)
    }

    @concurrent
    static func render(_ image: CGImage, output: CGSize, watermark: WatermarkSettings, scale: CGFloat) async -> CGImage? {
        guard scale > 0, !Task.isCancelled else { return nil }
        return try? ImageRenderer.render(image, outputSize: output, watermark: watermark,
                                         scale: scale, opaqueBackground: false)
    }
}

/// Shows the open-hand pointer over the preview while the watermark can be dragged.
private struct GrabPointer: ViewModifier {
    let isActive: Bool
    @State private var isPushed = false

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.pointerStyle(isActive ? .grabIdle : nil)
        } else {
            // macOS 14: push and pop the AppKit cursor on hover.
            content
                .onHover { inside in update(inside && isActive) }
                .onChange(of: isActive) { _, active in if !active { update(false) } }
                .onDisappear { update(false) }
        }
    }

    private func update(_ show: Bool) {
        guard show != isPushed else { return }
        if show { NSCursor.openHand.push() } else { NSCursor.pop() }
        isPushed = show
    }
}

/// "1024 × 768 px" with a dimension line, under the image (like the original's "max 800 px").
private struct SizeLabel: View {
    let output: CGSize
    let width: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            line
            Text("\(Int(output.width)) × \(Int(output.height)) px")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize()
            line
        }
        .frame(width: max(width, 120))
    }

    private var line: some View {
        Rectangle().fill(.white.opacity(0.4)).frame(height: 1)
    }
}

private struct EnlargeWarning: View {
    var body: some View {
        Label("These settings enlarge this photo past its original size. Quality may suffer.",
              systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(.orange.opacity(0.9), ignoresSafeAreaEdges: [])
            .foregroundStyle(.black)
    }
}

private struct StatusBar: View {
    let photo: Photo
    let output: CGSize

    var body: some View {
        HStack {
            Text(photo.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text("Original \(Int(photo.pixelSize.width)) × \(Int(photo.pixelSize.height))")
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }
}

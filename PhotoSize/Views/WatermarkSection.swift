import AppKit
import SwiftUI

/// "Batch Watermark": text (font, style, background box) or a logo image, plus opacity, angle and position.
struct WatermarkSection: View {
    @Environment(AppState.self) private var state

    /// The original app's special-characters menu.
    static let specialCharacters = ["©", "®", "℗", "™", "№", "▲", "▼", "◀︎", "▶︎"]
    static let fontFamilies = NSFontManager.shared.availableFontFamilies.sorted()

    var body: some View {
        @Bindable var state = state
        Section {
            Toggle("Add watermark", isOn: $state.watermark.isEnabled)

            Group {
                Picker("Type", selection: $state.watermark.kind) {
                    Text("Text").tag(WatermarkKind.text)
                    Text("Logo").tag(WatermarkKind.logo)
                }
                .pickerStyle(.segmented)

                if state.watermark.kind == .text {
                    LabeledContent("Text") {
                        HStack(alignment: .top, spacing: 6) {
                            TextField("Text", text: $state.watermark.text, prompt: Text("© 2026 Your Name"), axis: .vertical)
                                .labelsHidden()
                                .lineLimit(1...4)
                            Menu {
                                ForEach(Self.specialCharacters, id: \.self) { character in
                                    Button(character) { state.watermark.text += character }
                                }
                                Divider()
                                Button("More Characters…") { NSApp.orderFrontCharacterPalette(nil) }
                            } label: {
                                Image(systemName: "character")
                            }
                            .menuIndicator(.hidden)
                            .fixedSize()
                            .help("Insert a special character")
                        }
                    }

                    Picker("Font", selection: $state.watermark.fontFamily) {
                        if !Self.fontFamilies.contains(state.watermark.fontFamily) {
                            Text(state.watermark.fontFamily).tag(state.watermark.fontFamily)
                        }
                        ForEach(Self.fontFamilies, id: \.self) { family in
                            Text(family).tag(family)
                        }
                    }

                    LabeledContent("Style") {
                        HStack(spacing: 4) {
                            ColorPicker("Text color", selection: colorBinding(\.color), supportsOpacity: false)
                                .labelsHidden()
                            Toggle(isOn: $state.watermark.bold) { Image(systemName: "bold") }
                                .help("Bold")
                            Toggle(isOn: $state.watermark.italic) { Image(systemName: "italic") }
                                .help("Italic")
                            Toggle(isOn: $state.watermark.underline) { Image(systemName: "underline") }
                                .help("Underline")
                        }
                        .toggleStyle(.button)
                    }

                    Picker("Size in", selection: $state.watermark.sizeMode) {
                        Text("% of width").tag(WatermarkSizeMode.relative)
                        Text("Pixels").tag(WatermarkSizeMode.pixels)
                    }
                    .pickerStyle(.segmented)
                    .help("Percent of width keeps the watermark the same size relative to every photo")

                    if state.watermark.sizeMode == .relative {
                        SliderRow(title: "Size", unit: "%", value: $state.watermark.relativeSize, range: 0.5...30, step: 0.5)
                    } else {
                        SliderRow(title: "Size", unit: "px", value: $state.watermark.fontSize, range: 1...300)
                    }
                    LabeledContent("Background") {
                        HStack(spacing: 8) {
                            Toggle("Background box", isOn: $state.watermark.backgroundEnabled)
                                .labelsHidden()
                            ColorPicker("Background color", selection: colorBinding(\.backgroundColor), supportsOpacity: false)
                                .labelsHidden()
                                .disabled(!state.watermark.backgroundEnabled)
                        }
                    }
                } else {
                    LogoRow()
                    SliderRow(title: "Size", unit: "%", value: $state.watermark.logoWidthPercent, range: 1...100)
                        .help("Logo width as a percentage of each photo's width")
                }

                SliderRow(title: "Opacity", unit: "%", value: $state.watermark.opacity, range: 0...100)
                SliderRow(title: "Angle", unit: "°", value: $state.watermark.angle, range: 0...360) {
                    Button("Reset") { state.watermark.angle = 0 }
                        .controlSize(.small)
                        .disabled(state.watermark.angle == 0)
                }

                LabeledContent("Position") {
                    VStack(alignment: .trailing, spacing: 4) {
                        SnapGrid(position: $state.watermark.position)
                        if case .free = state.watermark.position {
                            Text("Custom — drag on the preview")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .disabled(!state.watermark.isEnabled)
        } header: {
            Text("Batch Watermark")
        } footer: {
            Text(state.watermark.isEnabled
                 ? "Click or drag on the preview to place the watermark anywhere."
                 : "No watermark is added.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func colorBinding(_ keyPath: WritableKeyPath<WatermarkSettings, RGBAColor>) -> Binding<Color> {
        Binding(
            get: { state.watermark[keyPath: keyPath].swiftUIColor },
            set: { state.watermark[keyPath: keyPath] = RGBAColor($0) })
    }
}

/// The 3×3 snap grid; the button for the current anchor is highlighted.
struct SnapGrid: View {
    @Binding var position: WatermarkPosition

    private static let rows: [[(SnapAnchor, String, String)]] = [
        [(.topLeft, "arrow.up.left", "Top left"), (.topCenter, "arrow.up", "Top center"), (.topRight, "arrow.up.right", "Top right")],
        [(.centerLeft, "arrow.left", "Middle left"), (.center, "circle.fill", "Center"), (.centerRight, "arrow.right", "Middle right")],
        [(.bottomLeft, "arrow.down.left", "Bottom left"), (.bottomCenter, "arrow.down", "Bottom center"), (.bottomRight, "arrow.down.right", "Bottom right")],
    ]

    var body: some View {
        Grid(horizontalSpacing: 2, verticalSpacing: 2) {
            ForEach(Self.rows.indices, id: \.self) { row in
                GridRow {
                    ForEach(Self.rows[row], id: \.0) { anchor, symbol, name in
                        let isOn = position == .snap(anchor)
                        Button {
                            position = .snap(anchor)
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: anchor == .center ? 7 : 10, weight: .semibold))
                                .frame(width: 24, height: 20)
                                .foregroundStyle(isOn ? Color.white : .secondary)
                                .background(isOn ? Color.accentColor : Color.secondary.opacity(0.12),
                                            in: .rect(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        .help("Snap to \(name.lowercased())")
                        .accessibilityLabel("Snap to \(name.lowercased())")
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
            }
        }
    }
}

/// Slider plus a number field and unit, clamped to `range`.
struct SliderRow<Accessory: View>: View {
    let title: String
    let unit: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    @ViewBuilder var accessory: Accessory

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Slider(value: clamped, in: range)
                    .labelsHidden()
                    .frame(minWidth: 70)
                TextField(title, value: clamped, format: .number.precision(.fractionLength(0...(step < 1 ? 1 : 0))))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 44)
                Text(unit)
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .leading)
                accessory
            }
        }
    }

    private var clamped: Binding<Double> {
        Binding(get: { value },
                set: { value = min(max(($0 / step).rounded() * step, range.lowerBound), range.upperBound) })
    }
}

extension SliderRow where Accessory == EmptyView {
    init(title: String, unit: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double = 1) {
        self.init(title: title, unit: unit, value: value, range: range, step: step) { EmptyView() }
    }
}

extension RGBAColor {
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(red: ns.redComponent, green: ns.greenComponent, blue: ns.blueComponent, alpha: ns.alphaComponent)
    }

    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

/// Shows the current logo and lets the user choose or remove it.
struct LogoRow: View {
    @Environment(AppState.self) private var state
    @State private var errorMessage: String?

    var body: some View {
        LabeledContent("Image") {
            HStack(spacing: 8) {
                if let url = state.watermark.logoURL, let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 44, height: 28)
                        .background(.quaternary, in: .rect(cornerRadius: 3)) // shows transparency
                        .accessibilityLabel("Current logo")
                    Button("Remove", systemImage: "xmark.circle.fill") { state.watermark.logoURL = nil }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Remove the logo")
                } else {
                    Text("None")
                        .foregroundStyle(.secondary)
                }
                Button("Choose…", action: chooseLogo)
                    .help("Pick an image to use as the watermark; PNGs with transparency work best")
            }
        }
        .alert("Couldn't Use That Image", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func chooseLogo() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = PhotoImporter.imageTypes
        panel.prompt = "Use as Logo"
        panel.message = "Choose an image for the logo watermark. PNGs with transparency work best."
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            errorMessage = state.setLogo(from: url)
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }
}

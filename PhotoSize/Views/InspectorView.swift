import SwiftUI

/// Right-hand panel with the batch settings.
struct InspectorView: View {
    var body: some View {
        Form {
            ResizeSection()
            WatermarkSection()
        }
        .formStyle(.grouped)
    }
}

/// "Batch Resize": fit width, fit height or scale, with the original app's presets.
struct ResizeSection: View {
    @Environment(AppState.self) private var state

    static let sizeRange = 1...20_000
    static let scaleRange = 1...1_000

    var body: some View {
        @Bindable var state = state
        Section {
            Toggle("Resize photos", isOn: $state.resize.isEnabled)

            Group {
                Picker("Fit to", selection: $state.resize.mode) {
                    Text("Width").tag(ResizeMode.width)
                    Text("Height").tag(ResizeMode.height)
                    Text("Scale").tag(ResizeMode.scale)
                }
                .pickerStyle(.segmented)

                switch state.resize.mode {
                case .width:
                    NumberRow(title: "Width", unit: "px", value: $state.resize.width, range: Self.sizeRange, step: 10)
                case .height:
                    NumberRow(title: "Height", unit: "px", value: $state.resize.height, range: Self.sizeRange, step: 10)
                case .scale:
                    NumberRow(title: "Scale", unit: "%", value: $state.resize.scalePercent, range: Self.scaleRange, step: 5)
                }

                Picker("Presets", selection: presetBinding) {
                    Text("Custom").tag(ResizePreset?.none)
                    ForEach(ResizePreset.groups, id: \.first?.id) { group in
                        Divider()
                        ForEach(group) { preset in
                            Text(preset.title).tag(Optional(preset))
                        }
                    }
                }
            }
            .disabled(!state.resize.isEnabled)

            if let photo = state.previewPhoto {
                LabeledContent("Selected photo") {
                    Text(summary(for: photo))
                        .monospacedDigit()
                        .foregroundStyle(state.resize.enlarges(photo.pixelSize) ? .orange : .secondary)
                }
            }
        } header: {
            Text("Batch Resize")
        } footer: {
            Text(footer)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The preset matching the current settings, if any. Choosing one applies it.
    private var presetBinding: Binding<ResizePreset?> {
        Binding(
            get: {
                let r = state.resize
                let value = switch r.mode {
                case .width: r.width
                case .height: r.height
                case .scale: r.scalePercent
                }
                return ResizePreset.groups.joined().first { $0.mode == r.mode && $0.value == value }
            },
            set: { preset in
                guard let preset else { return }
                preset.apply(to: &state.resize)
            })
    }

    private func summary(for photo: Photo) -> String {
        let from = photo.pixelSize
        let to = state.resize.targetSize(for: from)
        return "\(Int(from.width)) × \(Int(from.height)) → \(Int(to.width)) × \(Int(to.height))"
    }

    private var footer: String {
        guard state.resize.isEnabled else { return "Photos are exported at their original size." }
        return switch state.resize.mode {
        case .width: "Every photo is scaled to \(state.resize.width) px wide, keeping its proportions."
        case .height: "Every photo is scaled to \(state.resize.height) px tall, keeping its proportions."
        case .scale: "Every photo is scaled to \(state.resize.scalePercent)% of its original size."
        }
    }
}

/// A labeled number field with a stepper and unit, clamped to `range`.
struct NumberRow: View {
    let title: String
    let unit: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, value: clamped, format: .number.grouping(.never))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Stepper(title, value: clamped, in: range, step: step)
                    .labelsHidden()
                Text(unit)
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .leading)
            }
        }
    }

    private var clamped: Binding<Int> {
        Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) })
    }
}

#Preview {
    InspectorView()
        .environment(AppState())
        .frame(width: 300, height: 400)
}

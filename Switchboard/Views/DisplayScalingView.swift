import SwiftUI

struct DisplayScalingView: View {
    @ObservedObject var controller: DisplayScalingController
    let close: () -> Void

    private var externalDisplays: [ScalingDisplay] {
        controller.displays.filter { !$0.isBuiltIn }
    }

    private var selectionLocked: Bool {
        controller.isBusy || controller.confirmationSeconds != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(20)
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if externalDisplays.isEmpty {
                        emptyState
                    } else {
                        displaySelection
                        if let display = controller.selectedDisplay {
                            if let reason = display.unavailableReason {
                                message(reason, symbol: "info.circle")
                            } else if controller.presets.isEmpty {
                                message("No supported text sizes are available for this display.",
                                        symbol: "info.circle")
                            } else {
                                scaleSelection
                                textPreview
                            }
                        }
                    }
                    if let error = controller.errorMessage {
                        message(error, symbol: "exclamationmark.triangle")
                            .accessibilityLabel("Scaling error: \(error)")
                    }
                    if let status = controller.statusMessage,
                       !controller.isBusy, controller.confirmationSeconds == nil {
                        message(status, symbol: "info.circle")
                    }
                    qualityNote
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Hairline()
            footer.padding(20)
        }
        .font(.bodyText)
        .foregroundStyle(Theme.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
        .onExitCommand {
            if controller.confirmationSeconds != nil || controller.isBusy {
                controller.windowWillClose()
            } else {
                close()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "display")
                .font(.system(size: 28))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("Make text easier to read")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Choose a comfortable size for your external monitor with HiDPI rendering.")
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Connect an external monitor", systemImage: "cable.connector")
                .font(.headline)
            Text("Connect your Dell or another external monitor, then click Refresh Displays. Built-in displays keep their macOS scaling settings.")
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Refresh Displays", action: controller.refresh)
                .disabled(selectionLocked)
                .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .groupSurface()
    }

    private var displaySelection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Display").font(.sectionHeader)
                Spacer()
                Button("Refresh", action: controller.refresh)
                    .disabled(selectionLocked)
                    .accessibilityLabel("Refresh connected displays")
            }
            Picker("Display", selection: $controller.selectedDisplayID) {
                Text("Choose a display").tag(Optional<UInt32>.none)
                ForEach(externalDisplays) { display in
                    Text("\(display.name) · \(display.resolutionLabel)")
                        .tag(Optional(display.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(selectionLocked)
            .accessibilityLabel("External display")
            if let display = controller.selectedDisplay {
                Text("Monitor resolution: \(display.resolutionLabel)")
                    .font(.rowSubtitle)
                    .foregroundStyle(Theme.secondary)
            }
        }
        .padding(14)
        .groupSurface()
    }

    private var scaleSelection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Text and interface size").font(.sectionHeader)
                Spacer()
                Text("HiDPI").font(.rowSubtitle).foregroundStyle(Theme.secondary)
            }
            Picker("Text and interface size", selection: $controller.selectedPresetID) {
                ForEach(controller.presets) { preset in
                    Text(preset.title).tag(preset.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(selectionLocked)
            .accessibilityLabel("Text and interface size")
            .accessibilityHint("A higher percentage makes text and controls larger and fits less on screen.")
            if let preset = controller.selectedPreset {
                Text("Looks like \(preset.resolutionLabel). Higher percentages make everything larger.")
                    .font(.rowSubtitle)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .groupSurface()
    }

    private var textPreview: some View {
        HStack(spacing: 16) {
            Text("Aa")
                .font(.system(size: 24 * Double(controller.selectedPreset?.percent ?? 100) / 100,
                              weight: .medium))
                .frame(width: 96, height: 64)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Find your comfortable size").font(.headline)
                Text("Try it on your screen, then keep it if the text is clear.")
                    .font(.rowSubtitle)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .groupSurface()
        .accessibilityElement(children: .combine)
    }

    private var qualityNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What to expect").font(.sectionHeader)
            Text("HiDPI draws text in more detail. Intermediate sizes can soften edges; your monitor’s physical pixels still set the sharpness limit.")
            Text("This version supports SDR colour at a fixed refresh rate. HDR and variable refresh rate are not supported while scaling.")
            Text("The monitor may blink when you try a size. Scaling stays active while Switchboard runs and ends on display sleep or disconnection.")
        }
        .font(.rowSubtitle)
        .foregroundStyle(Theme.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let seconds = controller.confirmationSeconds {
                Label("Keep this size? Reverting in \(seconds) seconds.", systemImage: "timer")
                    .font(.headline)
                    .monospacedDigit()
                    .accessibilityLabel("Keep this size? Automatically reverting in \(seconds) seconds.")
                HStack {
                    Button("Revert", action: controller.restore)
                    Spacer()
                    Button("Keep Scaling", action: controller.keep)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                if controller.isBusy {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Preparing the display…")
                    }
                    .accessibilityElement(children: .combine)
                } else if controller.isActive, let preset = controller.activePreset {
                    Label("Scaling active · \(preset.percent)%", systemImage: "checkmark.circle")
                        .font(.rowSubtitle)
                }
                HStack {
                    if controller.isActive {
                        Button("Restore Original", action: controller.restore)
                            .disabled(controller.isBusy)
                    }
                    Spacer()
                    Button("Done", action: close)
                    if !externalDisplays.isEmpty {
                        Button("Try Scaling") { controller.preview() }
                            .buttonStyle(.borderedProminent)
                            .disabled(!controller.canPreview)
                    }
                }
            }
        }
    }

    private func message(_ text: String, symbol: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).accessibilityHidden(true)
        }
        .font(.rowSubtitle)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .groupSurface()
    }
}

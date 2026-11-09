import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @SwiftUI.State private var model = SettingsModel()

    @SwiftUI.State private var isCustomPromptPresented = false
    @SwiftUI.State private var customWidth = ""
    @SwiftUI.State private var customHeight = ""
    @SwiftUI.State private var isCustomNoticePresented = false

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            Form {
                videoSection
                inputSection(model: $model)
                hostSection(model: $model)

                Section("Advanced") {
                    Toggle("Statistics Overlay", isOn: $model.statsOverlay)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) {
                        model.save()
                        dismiss()
                    }
                }
            }
        }
        // Settings are saved when the sheet goes away, like the old sidebar did on close
        .onDisappear { model.save() }
        .alert("Enter Custom Resolution", isPresented: $isCustomPromptPresented) {
            TextField("Video Width", text: $customWidth)
                .keyboardType(.numberPad)
            TextField("Video Height", text: $customHeight)
                .keyboardType(.numberPad)
            Button("OK") { applyCustomResolution() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Custom Resolution Selected", isPresented: $isCustomNoticePresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Custom resolutions are not officially supported by GeForce Experience, so it will not set your host display resolution. You will need to set it manually while in game.\n\nResolutions that are not supported by your client or host PC may cause streaming errors.")
        }
    }

    // MARK: Video

    private var videoSection: some View {
        @Bindable var model = model

        return Section {
            Picker("Resolution", selection: Binding(
                get: { model.resolutionIndex },
                set: { newValue in
                    if newValue == SettingsModel.customResolutionIndex {
                        promptCustomResolution()
                    } else {
                        model.selectResolution(at: newValue)
                    }
                }
            )) {
                ForEach(0..<SettingsModel.resolutionNames.count, id: \.self) { index in
                    Text(model.resolutionTitle(at: index))
                        .tag(index)
                        .disabled(!model.isResolutionEnabled(at: index))
                }
            }

            if model.resolutionIndex == SettingsModel.customResolutionIndex {
                Button("Edit Custom Resolution…") { promptCustomResolution() }
            }

            Picker("Frame Rate", selection: Binding(
                get: { model.framerate },
                set: { model.selectFramerate($0) }
            )) {
                Text("30 FPS").tag(30)
                Text("60 FPS").tag(60)
                if model.supports120Fps || model.framerate == 120 {
                    Text("120 FPS").tag(120)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Bitrate") {
                    Text(model.bitrateText)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Slider(
                    value: $model.bitrateSliderValue,
                    in: 0...Double(SettingsModel.bitrateTable.count - 1),
                    step: 1
                )
                .accessibilityLabel("Bitrate")
                .accessibilityValue(model.bitrateText)
            }

            Picker("Preferred Codec", selection: $model.codec) {
                ForEach(model.availableCodecs, id: \.self) { codec in
                    Text(codec.title).tag(codec)
                }
            }

            Toggle("HDR (Beta)", isOn: $model.hdr)
                .disabled(!model.supportsHDR)

            Picker("Frame Pacing Preference", selection: $model.framePacing) {
                Text("Lowest Latency").tag(false)
                Text("Smoothest Video").tag(true)
            }

            Link(destination: URL(string: HelpURL.customResolution)!) {
                LabeledContent {
                    Text("\(model.chosenResolution.width) × \(model.chosenResolution.height)")
                        .monospacedDigit()
                } label: {
                    Label("Set PC/Game resolution", systemImage: "arrow.up.right.square")
                }
            }
        } header: {
            Text("Video")
        } footer: {
            if !model.supportsHDR {
                Text("HDR: Unsupported on this device")
            }
        }
    }

    // MARK: Input

    private func inputSection(model: Bindable<SettingsModel>) -> some View {
        Section("Input") {
            Picker("Touch Mode", selection: model.absoluteTouchMode) {
                Text("Touchpad").tag(false)
                Text("Touchscreen").tag(true)
            }
            .pickerStyle(.segmented)

            Picker("On-Screen Controls", selection: model.onscreenControls) {
                Text("Off").tag(0)
                Text("Auto").tag(1)
                Text("Simple").tag(2)
                Text("Full").tag(3)
            }
            // Disable on-screen controls in absolute touch mode
            .disabled(model.wrappedValue.absoluteTouchMode)

            Picker("Multi-Controller Mode", selection: model.multiController) {
                Text("Single").tag(false)
                Text("Auto").tag(true)
            }

            Toggle("Swap A/B and X/Y Buttons", isOn: model.swapABXYButtons)
            Toggle("Citrix X1 Mouse Support", isOn: model.btMouseSupport)
        }
    }

    private func hostSection(model: Bindable<SettingsModel>) -> some View {
        Section("Host & Audio") {
            Toggle("Optimize Game Settings", isOn: model.optimizeGames)
            Toggle("Play Audio on PC", isOn: model.playAudioOnPC)
        }
    }

    // MARK: Custom resolution

    private func promptCustomResolution() {
        let current = model.resolutionTable[SettingsModel.customResolutionIndex]
        customWidth = current.width == 0 ? "" : String(current.width)
        customHeight = current.height == 0 ? "" : String(current.height)
        isCustomPromptPresented = true
    }

    private func applyCustomResolution() {
        let width = Int(customWidth.trimmingCharacters(in: .whitespaces)) ?? 0
        let height = Int(customHeight.trimmingCharacters(in: .whitespaces)) ?? 0
        guard model.setCustomResolution(width: width, height: height) else {
            // Previous selection stays in place
            return
        }
        Task {
            // The prompt alert must finish dismissing before the notice can appear
            try? await Task.sleep(for: .milliseconds(500))
            isCustomNoticePresented = true
        }
    }
}

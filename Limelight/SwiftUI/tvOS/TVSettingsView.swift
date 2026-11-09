import SwiftUI

struct TVSettingsView: View {
    @SwiftUI.State private var settings = TVSettings.load()

    var body: some View {
        Form {
            Section("Video") {
                TVPickerRow("Resolution", selection: $settings.resolution) {
                    ForEach(TVSettings.resolutions, id: \.value) { Text($0.title).tag($0.value) }
                }
                TVPickerRow("Frame Rate", selection: $settings.framerate) {
                    ForEach(TVSettings.framerates, id: \.self) { Text("\($0) FPS").tag($0) }
                }
                TVPickerRow("Bitrate", selection: $settings.bitrate) {
                    ForEach(settings.bitrateOptions, id: \.self) { Text(TVSettings.bitrateTitle($0)).tag($0) }
                }
                TVPickerRow("Preferred Codec", selection: $settings.codec) {
                    ForEach(TVSettings.codecs, id: \.value) { Text($0.title).tag($0.value) }
                }
                TVPickerRow("Frame Pacing", selection: $settings.framePacing) {
                    ForEach(TVSettings.framePacing, id: \.value) { Text($0.title).tag($0.value) }
                }
                Toggle("Request HDR Video", isOn: $settings.hdr)
            }

            Section("Audio") {
                TVPickerRow("Audio Configuration", selection: $settings.audioConfig) {
                    ForEach(TVSettings.audioConfigs, id: \.value) { Text($0.title).tag($0.value) }
                }
                Toggle("Play Audio on Host PC", isOn: $settings.playAudioOnPC)
            }

            Section("Host") {
                Toggle("Optimize Game Settings", isOn: $settings.optimizeGames)
            }

            Section("Input") {
                Toggle("Automatic Game Controller Detection", isOn: $settings.multiController)
                Toggle("Swap A/B and X/Y Buttons", isOn: $settings.swapABXYButtons)
                Toggle("Citrix X1 Mouse Support", isOn: $settings.btMouseSupport)
            }

            Section("Troubleshooting") {
                Toggle("Statistics Overlay", isOn: $settings.statsOverlay)
            }
        }
        .navigationTitle("Settings")
        // Picking a resolution or frame rate re-derives the bitrate, like the iOS settings do
        .onChange(of: settings.resolution) { settings.applyAutoBitrate() }
        .onChange(of: settings.framerate) { settings.applyAutoBitrate() }
        .onChange(of: settings) { _, new in new.save() }
        .onDisappear { settings.save() }
    }
}

/// Label on the left, menu-style picker on the right (a plain menu Picker drops its label in a tvOS Form).
private struct TVPickerRow<Value: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: Value
    @ViewBuilder let content: Content

    init(_ title: String, selection: Binding<Value>, @ViewBuilder content: () -> Content) {
        self.title = title
        self._selection = selection
        self.content = content()
    }

    var body: some View {
        LabeledContent(title) {
            Picker(title, selection: $selection) { content }
                .pickerStyle(.menu)
                .labelsHidden()
        }
    }
}

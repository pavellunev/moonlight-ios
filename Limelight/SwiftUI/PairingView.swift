import SwiftUI

struct PairingView: View {
    @Environment(HostStore.self) private var store
    let info: PairingInfo

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                        .padding(.top, 8)

                    VStack(spacing: 6) {
                        Text("Pair with \(info.hostName)")
                            .font(.title2.weight(.semibold))
                        Text("Enter the following PIN on the host machine:")
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)

                    GlassEffectContainer(spacing: 12) {
                        HStack(spacing: 12) {
                            ForEach(Array(info.pin.enumerated()), id: \.offset) { _, digit in
                                Text(String(digit))
                                    .font(.system(size: 52, weight: .semibold, design: .monospaced))
                                    .frame(width: 62, height: 82)
                                    .glassEffect(.regular, in: .rect(cornerRadius: 18))
                            }
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("PIN \(info.pin.map(String.init).joined(separator: " "))")

                    Text("If your host PC is running Sunshine, navigate to the Sunshine web UI to enter the PIN.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Waiting for PIN…")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Pairing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .destructive) {
                        store.cancelPairing()
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

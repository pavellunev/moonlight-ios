import SwiftUI

struct TVPairingView: View {
    @Environment(HostStore.self) private var store
    let info: PairingInfo

    var body: some View {
        VStack(spacing: 48) {
            Image(systemName: "lock.shield")
                .font(.system(size: 96, weight: .light))
                .foregroundStyle(.tint)

            VStack(spacing: 12) {
                Text("Pair with \(info.hostName)")
                    .font(.largeTitle.weight(.bold))
                Text("Enter the following PIN on the host machine:")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            GlassEffectContainer(spacing: 24) {
                HStack(spacing: 24) {
                    ForEach(Array(info.pin.enumerated()), id: \.offset) { _, digit in
                        Text(String(digit))
                            .font(.system(size: 120, weight: .semibold, design: .monospaced))
                            .frame(width: 150, height: 200)
                            .glassEffect(.regular, in: .rect(cornerRadius: 36))
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("PIN \(info.pin.map(String.init).joined(separator: " "))")

            Text("If your host PC is running Sunshine, navigate to the Sunshine web UI to enter the PIN.")
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 1000)

            HStack(spacing: 16) {
                ProgressView()
                Text("Waiting for PIN…")
                    .foregroundStyle(.secondary)
            }
            .font(.headline)

            Button("Cancel", role: .destructive) {
                store.cancelPairing()
            }
            .buttonStyle(.glass)
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand {
            store.cancelPairing()
        }
        .interactiveDismissDisabled()
    }
}

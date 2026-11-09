import SwiftUI

struct TVAddHostView: View {
    @Environment(HostStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @SwiftUI.State private var address = ""
    @SwiftUI.State private var isWorking = false
    @SwiftUI.State private var errorText: String?

    private var trimmed: String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 40) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 96, weight: .light))
                .foregroundStyle(.tint)

            Text("Add PC")
                .font(.largeTitle.weight(.bold))

            Text("If Moonlight doesn't find your local gaming PC automatically, enter the IP address of your PC")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 900)

            TextField("IP address or hostname", text: $address)
                .textContentType(.URL)
                .autocorrectionDisabled()
                .disabled(isWorking)
                .onSubmit(add)
                .frame(maxWidth: 800)

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 900)
            }

            HStack(spacing: 24) {
                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(.glass)

                Button(action: add) {
                    HStack(spacing: 12) {
                        if isWorking {
                            ProgressView()
                        }
                        Text(isWorking ? "Adding…" : "Add")
                    }
                    .frame(minWidth: 160)
                }
                .buttonStyle(.glassProminent)
                .disabled(trimmed.isEmpty || isWorking)
            }
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func add() {
        guard !trimmed.isEmpty, !isWorking else { return }
        isWorking = true
        errorText = nil
        Task {
            let error = await store.addHost(address: trimmed)
            isWorking = false
            if let error {
                errorText = error
            } else {
                dismiss()
            }
        }
    }
}

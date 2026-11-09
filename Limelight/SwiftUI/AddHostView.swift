import SwiftUI

struct AddHostView: View {
    @Environment(HostStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @SwiftUI.State private var address = ""
    @SwiftUI.State private var isWorking = false
    @SwiftUI.State private var errorText: String?
    @FocusState private var focused: Bool

    private var trimmed: String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                        .padding(.top, 8)

                    Text("If Moonlight doesn't find your local gaming PC automatically, enter the IP address of your PC")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

                    TextField("IP address or hostname", text: $address)
                        .textFieldStyle(.plain)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($focused)
                        .disabled(isWorking)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
                        .onSubmit(add)

                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(action: add) {
                        HStack(spacing: 8) {
                            if isWorking {
                                ProgressView()
                            }
                            Text(isWorking ? "Adding…" : "Add")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(trimmed.isEmpty || isWorking)
                }
                .padding(24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Add PC")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
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

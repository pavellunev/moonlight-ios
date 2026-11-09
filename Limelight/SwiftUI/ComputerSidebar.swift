import SwiftUI

struct ComputerSidebar: View {
    @Environment(HostStore.self) private var store

    var body: some View {
        List(selection: Binding(
            get: { store.selectedHostID },
            set: { store.userSelected($0) }
        )) {
            ForEach(store.hosts) { host in
                HostRow(host: host)
                    .tag(host.id)
                    .contextMenu {
                        ForEach(store.actions(for: host), id: \.self) { action in
                            Button(role: action == .remove ? .destructive : nil) {
                                store.perform(action, on: host)
                            } label: {
                                Label(action.title, systemImage: action.symbol)
                            }
                        }
                    }
            }
        }
        .navigationTitle("Computers")
        .overlay {
            if store.hosts.isEmpty {
                ContentUnavailableView {
                    Label("Searching for PCs on your network…", systemImage: "desktopcomputer")
                } description: {
                    Text("Make sure your PC is on and running GeForce Experience or Sunshine.")
                } actions: {
                    Button("Add PC") { store.isAddHostPresented = true }
                        .buttonStyle(.glass)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape") {
                    store.isSettingsPresented = true
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add PC", systemImage: "plus") {
                    store.isAddHostPresented = true
                }
            }
        }
    }
}

private struct HostRow: View {
    let host: HostItem

    private var statusColor: Color {
        switch host.connection {
        case .checking: return .orange
        case .offline: return .red
        case .online: return host.pairing == .unpaired ? .yellow : .green
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "desktopcomputer")
                .font(.title2)
                .foregroundStyle(host.connection == .offline ? .secondary : .primary)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(host.name)
                    .font(.headline)
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(host.statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            switch (host.connection, host.pairing) {
            case (.checking, _):
                ProgressView()
            case (.online, .unpaired):
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Not paired")
            default:
                EmptyView()
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

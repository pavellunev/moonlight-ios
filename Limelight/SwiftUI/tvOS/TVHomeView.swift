import SwiftUI

/// Home screen: a shelf of computers, and below it the app library of the selected computer.
struct TVHomeView: View {
    @Environment(HostStore.self) private var store
    @FocusState private var focusedApp: String?

    private var showsLibrary: Bool {
        store.selectedHostID != nil && (store.appsLoaded || !store.apps.isEmpty)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 56) {
                header
                computerShelf
                if showsLibrary, let host = store.selectedHostItem {
                    TVAppLibrary(host: host, focusedApp: $focusedApp)
                }
            }
            .padding(.bottom, 80)
        }
        .scrollClipDisabled()
        .onChange(of: store.apps.first?.id) { _, first in
            // Apps just arrived for the selected computer: move focus down into the library
            if let first, focusedApp == nil {
                focusedApp = first
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Moonlight")
                .font(.largeTitle.weight(.bold))
        }
    }

    private var computerShelf: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Computers")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 40) {
                    ForEach(store.hosts) { host in
                        TVComputerCard(host: host, isSelected: host.id == store.selectedHostID)
                    }
                    TVAddComputerCard()
                    TVSettingsCard()
                }
                .padding(.vertical, 40)
            }
            .scrollClipDisabled()

            if store.hosts.isEmpty {
                HStack(spacing: 16) {
                    ProgressView()
                    Text("Searching for PCs on your network…")
                        .foregroundStyle(.secondary)
                }
                .font(.headline)
            }
        }
    }
}

private let computerCardSize = CGSize(width: 440, height: 280)

private struct TVComputerCard: View {
    @Environment(HostStore.self) private var store
    let host: HostItem
    let isSelected: Bool

    private var statusColor: Color {
        switch host.connection {
        case .checking: return .orange
        case .offline: return .red
        case .online: return host.pairing == .unpaired ? .yellow : .green
        }
    }

    var body: some View {
        Button {
            store.userSelected(host.id)
        } label: {
            VStack(spacing: 18) {
                Image(systemName: host.connection == .online && host.pairing == .unpaired ? "lock.desktopcomputer" : "desktopcomputer")
                    .font(.system(size: 84, weight: .light))
                    .foregroundStyle(host.connection == .offline ? .secondary : .primary)

                Text(host.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                HStack(spacing: 10) {
                    if host.connection == .checking {
                        ProgressView()
                    } else {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 14, height: 14)
                    }
                    Text(host.statusText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(width: computerCardSize.width, height: computerCardSize.height)
            .overlay(alignment: .topLeading) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .padding(18)
                }
            }
        }
        .buttonStyle(.card)
        .contextMenu {
            ForEach(store.actions(for: host), id: \.self) { action in
                Button(role: action == .remove ? .destructive : nil) {
                    store.perform(action, on: host)
                } label: {
                    Label(action.title, systemImage: action.symbol)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct TVAddComputerCard: View {
    @Environment(HostStore.self) private var store

    var body: some View {
        Button {
            store.isAddHostPresented = true
        } label: {
            VStack(spacing: 18) {
                Image(systemName: "plus")
                    .font(.system(size: 84, weight: .light))
                Text("Add PC")
                    .font(.title3.weight(.semibold))
            }
            .frame(width: computerCardSize.width, height: computerCardSize.height)
        }
        .buttonStyle(.card)
    }
}

private struct TVSettingsCard: View {
    @Environment(HostStore.self) private var store

    var body: some View {
        Button {
            store.isSettingsPresented = true
        } label: {
            VStack(spacing: 18) {
                Image(systemName: "gearshape")
                    .font(.system(size: 84, weight: .light))
                Text("Settings")
                    .font(.title3.weight(.semibold))
            }
            .frame(width: computerCardSize.width, height: computerCardSize.height)
        }
        .buttonStyle(.card)
    }
}

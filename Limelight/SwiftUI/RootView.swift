import SwiftUI
import UIKit

/// Entry point used by SceneDelegate.m
@objc(MLRootFactory)
final class RootFactory: NSObject {
    @objc static func makeRootViewController() -> UIViewController {
        UIHostingController(rootView: RootView())
    }
}

struct RootView: View {
    @SwiftUI.State private var store = HostStore()

    var body: some View {
        @Bindable var store = store

        NavigationSplitView {
            ComputerSidebar()
        } detail: {
            AppLibraryView()
        }
        .environment(store)
        .overlay {
            if let message = store.busyMessage {
                BusyOverlay(message: message)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.25), value: store.busyMessage)
        .sheet(isPresented: $store.isAddHostPresented) {
            AddHostView()
                .environment(store)
        }
        .sheet(isPresented: $store.isSettingsPresented) {
            SettingsView()
        }
        .sheet(item: $store.pairing) { info in
            PairingView(info: info)
                .environment(store)
        }
        .alert(
            store.alert?.title ?? "",
            isPresented: Binding(get: { store.alert != nil }, set: { if !$0 { store.alert = nil } }),
            presenting: store.alert
        ) { content in
            if content.showsHelp {
                Button("Help") { store.openHelp() }
            }
            Button("OK", role: .cancel) {}
        } message: { content in
            Text(content.message)
        }
        .confirmationDialog(
            store.hostActionsTarget?.name ?? "",
            isPresented: Binding(get: { store.hostActionsTarget != nil }, set: { if !$0 { store.hostActionsTarget = nil } }),
            titleVisibility: .visible,
            presenting: store.hostActionsTarget
        ) { host in
            ForEach(store.actions(for: host), id: \.self) { action in
                Button(action.title, role: action == .remove ? .destructive : nil) {
                    store.perform(action, on: host)
                }
            }
        } message: { host in
            Text(host.detailedStatusText)
        }
        .confirmationDialog(
            "Remove PC",
            isPresented: Binding(get: { store.removeTarget != nil }, set: { if !$0 { store.removeTarget = nil } }),
            titleVisibility: .visible,
            presenting: store.removeTarget
        ) { host in
            Button("Remove \(host.name)", role: .destructive) {
                store.confirmRemove(host)
            }
        } message: { host in
            Text("\(host.name) will be removed from this device. You can add it again later.")
        }
        .task {
            store.start()
        }
    }
}

struct BusyOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text(message)
                    .font(.headline)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
        }
        .accessibilityElement(children: .combine)
    }
}

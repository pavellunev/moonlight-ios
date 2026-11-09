import SwiftUI
import UIKit

/// Entry point used by SceneDelegate.m
@objc(MLRootFactory)
final class RootFactory: NSObject {
    @objc static func makeRootViewController() -> UIViewController {
        UIHostingController(rootView: TVRootView())
    }
}

struct TVRootView: View {
    @SwiftUI.State private var store = HostStore()

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            TVHomeView()
                .navigationDestination(isPresented: $store.isSettingsPresented) {
                    TVSettingsView()
                }
        }
        // Like the old modal loading screen: nothing underneath takes focus while busy
        .disabled(store.busyMessage != nil)
        .environment(store)
        .overlay {
            if let message = store.busyMessage {
                TVBusyOverlay(message: message)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.25), value: store.busyMessage)
        .sheet(isPresented: $store.isAddHostPresented) {
            TVAddHostView()
                .environment(store)
        }
        .fullScreenCover(item: $store.pairing) { info in
            TVPairingView(info: info)
                .environment(store)
        }
        .alert(
            store.alert?.title ?? "",
            isPresented: Binding(get: { store.alert != nil }, set: { if !$0 { store.alert = nil } }),
            presenting: store.alert
        ) { _ in
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
        .confirmationDialog(
            store.appActionsTarget?.name ?? "",
            isPresented: Binding(get: { store.appActionsTarget != nil }, set: { if !$0 { store.appActionsTarget = nil } }),
            titleVisibility: .visible,
            presenting: store.appActionsTarget
        ) { app in
            ForEach(store.actions(for: app), id: \.self) { action in
                Button(action.title, role: action.isDestructive ? .destructive : nil) {
                    store.perform(action, on: app)
                }
            }
        } message: { app in
            Text(store.message(for: app))
        }
        .task {
            store.start()
        }
    }
}

struct TVBusyOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                ProgressView()
                    .controlSize(.large)
                Text(message)
                    .font(.title3.weight(.semibold))
            }
            .padding(.horizontal, 64)
            .padding(.vertical, 44)
            .glassEffect(.regular, in: .rect(cornerRadius: 40))
        }
        .accessibilityElement(children: .combine)
    }
}

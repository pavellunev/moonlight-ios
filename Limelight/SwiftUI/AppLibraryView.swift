import SwiftUI

struct AppLibraryView: View {
    @Environment(HostStore.self) private var store

    var body: some View {
        Group {
            if let host = store.selectedHostItem {
                library(for: host)
            } else {
                ContentUnavailableView("Select a Computer", systemImage: "desktopcomputer",
                                       description: Text("Choose a PC from the list to see its apps."))
            }
        }
    }

    @ViewBuilder
    private func library(for host: HostItem) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 20)], spacing: 24) {
                ForEach(store.apps) { app in
                    AppCard(app: app)
                }
            }
            .padding(20)
        }
        .overlay {
            if store.apps.isEmpty && store.appsLoaded {
                ContentUnavailableView("No Apps", systemImage: "square.grid.2x2",
                                       description: Text(store.showHiddenApps
                                                         ? "This PC has no apps."
                                                         : "This PC has no visible apps."))
            }
        }
        .refreshable {
            await store.refreshAppList()
        }
        .navigationTitle(host.name)
        .navigationSubtitle(host.statusText)
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
    }
}

private struct AppCard: View {
    @Environment(HostStore.self) private var store
    let app: AppItem

    @SwiftUI.State private var image: UIImage?

    var body: some View {
        Button {
            store.appClicked(app.id)
        } label: {
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Placeholder(name: app.name)
                }
            }
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 18))
            .overlay(alignment: .top) {
                badges
            }
            .shadow(color: .black.opacity(app.hidden ? 0 : 0.3), radius: 8, y: 4)
            .opacity(app.hidden ? 0.45 : 1)
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(CardButtonStyle())
        .contextMenu {
            ForEach(store.actions(for: app), id: \.self) { action in
                Button(role: action.isDestructive ? .destructive : nil) {
                    store.perform(action, on: app)
                } label: {
                    Label(action.title, systemImage: action.symbol)
                }
            }
        }
        .accessibilityLabel(app.name)
        .accessibilityValue(app.running ? "Running" : "")
        .task(id: store.artVersion) {
            image = await store.boxArt(for: app.id)
        }
    }

    @ViewBuilder
    private var badges: some View {
        if app.running || app.hidden {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    if app.running {
                        Label("Running", systemImage: "play.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .glassEffect(.regular.tint(.green.opacity(0.45)), in: .capsule)
                    }
                    Spacer(minLength: 0)
                    if app.hidden {
                        Image(systemName: "eye.slash")
                            .font(.caption.weight(.semibold))
                            .padding(7)
                            .glassEffect(.regular, in: .circle)
                    }
                }
            }
            .padding(10)
        }
    }
}

private struct Placeholder: View {
    let name: String

    // Stable per-name hue (String.hashValue is randomized per launch)
    private var hue: Double {
        Double(name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 360 }) / 360.0
    }

    var body: some View {
        LinearGradient(
            colors: [Color(hue: hue, saturation: 0.55, brightness: 0.55),
                     Color(hue: hue, saturation: 0.7, brightness: 0.28)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .overlay {
            VStack(spacing: 10) {
                Image(systemName: "gamecontroller.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.7))
                Text(name)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
            }
            .padding(12)
        }
    }
}

private struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.smooth(duration: 0.18), value: configuration.isPressed)
    }
}

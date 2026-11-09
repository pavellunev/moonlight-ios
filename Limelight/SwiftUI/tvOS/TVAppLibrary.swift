import SwiftUI

struct TVAppLibrary: View {
    @Environment(HostStore.self) private var store
    let host: HostItem
    var focusedApp: FocusState<String?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(host.name)
                    .font(.title2.weight(.semibold))
                Text(store.showHiddenApps ? "\(host.statusText) · All apps" : host.statusText)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            if store.apps.isEmpty {
                ContentUnavailableView("No Apps", systemImage: "square.grid.2x2",
                                       description: Text(store.showHiddenApps
                                                         ? "This PC has no apps."
                                                         : "This PC has no visible apps."))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 300), spacing: 48)], spacing: 56) {
                    ForEach(store.apps) { app in
                        TVAppCard(app: app)
                            .focused(focusedApp, equals: app.id)
                    }
                }
                .padding(.vertical, 24)
            }
        }
        .focusSection()
        // Menu goes back to the computer shelf, like the old menu-button intercept
        .onExitCommand {
            focusedApp.wrappedValue = nil
            store.showHostSelectionView()
        }
    }
}

private struct TVAppCard: View {
    @Environment(HostStore.self) private var store
    let app: AppItem

    @SwiftUI.State private var image: UIImage?

    var body: some View {
        VStack(spacing: 16) {
            Button {
                store.appClicked(app.id)
            } label: {
                ZStack {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        TVPlaceholder(name: app.name)
                    }
                }
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .clipped()
                .overlay(alignment: .top) { badges }
                .opacity(app.hidden ? 0.45 : 1)
            }
            .buttonStyle(.card)
            .contextMenu {
                ForEach(store.actions(for: app), id: \.self) { action in
                    Button(role: action.isDestructive ? .destructive : nil) {
                        store.perform(action, on: app)
                    } label: {
                        Label(action.title, systemImage: action.symbol)
                    }
                }
            }

            Text(app.name)
                .font(.headline)
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(app.name)
        .accessibilityValue(app.running ? "Running" : "")
        .task(id: store.artVersion) {
            image = await store.boxArt(for: app.id)
        }
    }

    @ViewBuilder
    private var badges: some View {
        if app.running || app.hidden {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    if app.running {
                        Label("Running", systemImage: "play.fill")
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .glassEffect(.regular.tint(.green.opacity(0.45)), in: .capsule)
                    }
                    Spacer(minLength: 0)
                    if app.hidden {
                        Image(systemName: "eye.slash")
                            .font(.callout.weight(.semibold))
                            .padding(10)
                            .glassEffect(.regular, in: .circle)
                    }
                }
            }
            .padding(14)
        }
    }
}

private struct TVPlaceholder: View {
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
            VStack(spacing: 14) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.white.opacity(0.7))
                Text(name)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
            }
            .padding(20)
        }
    }
}

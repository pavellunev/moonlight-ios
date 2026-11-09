import Foundation

/// Value snapshot of a TemporaryHost. TemporaryHost is mutated from discovery threads,
/// so the UI only ever reads these immutable copies.
struct HostItem: Identifiable, Equatable {
    enum Connection { case checking, offline, online }
    enum Pairing { case unknown, unpaired, paired }

    let id: String
    let name: String
    let connection: Connection
    let pairing: Pairing
    let isNvidiaServerSoftware: Bool

    var statusText: String {
        switch connection {
        case .checking: return "Checking…"
        case .offline: return "Offline"
        case .online: return pairing == .unpaired ? "Not paired" : "Online"
        }
    }

    /// Same wording as the original action sheet message.
    var detailedStatusText: String {
        switch connection {
        case .offline: return "Offline"
        case .checking: return "Connecting"
        case .online: return pairing == .paired ? "Online - Paired" : "Online - Not Paired"
        }
    }
}

/// Value snapshot of a TemporaryApp.
struct AppItem: Identifiable, Equatable {
    let id: String
    let name: String
    let hidden: Bool
    let running: Bool
}

enum HostAction: Hashable {
    case wake, viewAllApps, gameStreamEndOfService, testNetwork, connectionHelp, remove

    var title: String {
        switch self {
        case .wake: return "Wake PC"
        case .viewAllApps: return "View All Apps"
        case .gameStreamEndOfService: return "NVIDIA GameStream End-of-Service"
        case .testNetwork: return "Test Network"
        case .connectionHelp: return "Connection Help"
        case .remove: return "Remove PC"
        }
    }

    var symbol: String {
        switch self {
        case .wake: return "power"
        case .viewAllApps: return "square.grid.2x2"
        case .gameStreamEndOfService: return "info.circle"
        case .testNetwork: return "network"
        case .connectionHelp: return "questionmark.circle"
        case .remove: return "trash"
        }
    }
}

enum AppAction: Hashable {
    case launch(title: String)
    case quit(title: String)
    case setHidden(Bool)

    var title: String {
        switch self {
        case .launch(let title), .quit(let title): return title
        case .setHidden(let hidden): return hidden ? "Hide App" : "Show App"
        }
    }

    var symbol: String {
        switch self {
        case .launch: return "play.fill"
        case .quit: return "stop.fill"
        case .setHidden(let hidden): return hidden ? "eye.slash" : "eye"
        }
    }

    var isDestructive: Bool {
        switch self {
        case .quit: return true
        case .setHidden(let hidden): return hidden
        case .launch: return false
        }
    }
}

struct AlertContent: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var showsHelp = false
}

struct PairingInfo: Identifiable {
    let id = UUID()
    let hostName: String
    let pin: String
}

enum HelpURL {
    static let troubleshooting = "https://github.com/moonlight-stream/moonlight-docs/wiki/Troubleshooting"
    static let gameStreamEndOfService = "https://github.com/moonlight-stream/moonlight-docs/wiki/NVIDIA-GameStream-End-Of-Service-Announcement-FAQ"
    static let customResolution = "https://moonlight-stream.org/custom-resolution"
}

extension TemporaryHost {
    var appObjects: [TemporaryApp] {
        appList.compactMap { $0 as? TemporaryApp }
    }
}

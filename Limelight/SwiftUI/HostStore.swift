import Observation
import SwiftUI
import UIKit

/// Adapts the ObjC discovery/pairing/asset callbacks (which arrive off the main thread) to the store.
final class HostStoreBridge: NSObject, DiscoveryCallback, PairCallback, AppAssetCallback {
    weak var store: HostStore?

    private func onMain(_ work: @escaping @MainActor (HostStore) -> Void) {
        // Plain main-queue dispatch (not a Task) so callbacks keep their order:
        // startPairing must be handled before any pairFailed/pairSuccessful.
        DispatchQueue.main.async { [weak self] in
            guard let store = self?.store else { return }
            MainActor.assumeIsolated { work(store) }
        }
    }

    func updateAllHosts(_ hosts: [Any]!) {
        // Copy now: the array may be modified before the main thread dispatch happens
        let copy = (hosts as? [TemporaryHost]) ?? []
        onMain { $0.updateAllHosts(copy) }
    }

    func startPairing(_ PIN: String!) {
        let pin = PIN ?? ""
        onMain { $0.startPairing(pin) }
    }

    func pairSuccessful(_ serverCert: Data!) {
        onMain { $0.pairSuccessful(serverCert) }
    }

    func pairFailed(_ message: String!) {
        let text = message ?? ""
        onMain { $0.pairFailed(text) }
    }

    func alreadyPaired() {
        onMain { $0.pairedAlready() }
    }

    func receivedAsset(for app: TemporaryApp!) {
        onMain { $0.receivedAsset(for: app) }
    }
}

/// Port of MainFrameViewController's behaviour (discovery, pairing, app list, quit, wake, ...)
/// for the SwiftUI interface.
// Same value as CONN_TEST_SERVER in Connection.h (that header can't be imported from Swift)
// Posted by StreamFrameViewController (MLStreamDidEndNotification; that header can't be imported from Swift)
private let streamDidEndNotification = Notification.Name("MLStreamDidEndNotification")

private let connectivityTestServer = "ios.conntest.moonlight-stream.org"

@MainActor
@Observable
final class HostStore {
    // MARK: Observable UI state
    private(set) var hosts: [HostItem] = []
    private(set) var apps: [AppItem] = []
    private(set) var showHiddenApps = false
    private(set) var artVersion = 0
    private(set) var appsLoaded = false

    var selectedHostID: String?
    var busyMessage: String?
    var alert: AlertContent?
    var pairing: PairingInfo?
    var isAddHostPresented = false
    var isSettingsPresented = false
    var hostActionsTarget: HostItem?
    var removeTarget: HostItem?
    var appActionsTarget: AppItem?

    // MARK: Internals
    @ObservationIgnored private let bridge = HostStoreBridge()
    @ObservationIgnored private var discMan: DiscoveryManager!
    @ObservationIgnored private var appManager: AppAssetManager!
    @ObservationIgnored private let opQueue = OperationQueue()
    @ObservationIgnored private var hostList: [TemporaryHost] = []
    @ObservationIgnored private var selectedHost: TemporaryHost?
    @ObservationIgnored private var clientCert: Data?
    @ObservationIgnored private var isBackground = false
    @ObservationIgnored private var isStreaming = false
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private let boxArtCache = NSCache<NSString, UIImage>()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        bridge.store = self

        // Set up crypto
        CryptoManager.generateKeyPairUsingSSL()
        clientCert = CryptoManager.readCertFromFile()

        appManager = AppAssetManager(callback: bridge)

        retrieveSavedHosts()
        discMan = DiscoveryManager(hosts: hostList, andCallback: bridge)
        refreshHostItems()

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleReturnToForeground() }
        })
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleEnterBackground() }
        })
        observers.append(center.addObserver(forName: streamDidEndNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.streamDidEnd() }
        })

        // Mirrors viewDidLoad: with a single known PC, go straight to it
        if hostList.count == 1, let host = hostList.first {
            hostClicked(host, userInitiated: false)
        }
    }

    // MARK: Lookups

    private func hostObject(id: String) -> TemporaryHost? {
        hostList.first { $0.uuid == id }
    }

    private func appObject(id: String, in host: TemporaryHost) -> TemporaryApp? {
        host.appObjects.first { $0.id == id }
    }

    private func item(for host: TemporaryHost) -> HostItem {
        let connection: HostItem.Connection
        switch host.state {
        case .online: connection = .online
        case .offline: connection = .offline
        default: connection = .checking
        }
        let pairing: HostItem.Pairing
        switch host.pairState {
        case .paired: pairing = .paired
        case .unpaired: pairing = .unpaired
        default: pairing = .unknown
        }
        return HostItem(id: host.uuid, name: host.name, connection: connection, pairing: pairing,
                        isNvidiaServerSoftware: host.isNvidiaServerSoftware)
    }

    var selectedHostItem: HostItem? {
        guard let id = selectedHostID else { return nil }
        return hosts.first { $0.id == id }
    }

    private func findRunningApp(_ host: TemporaryHost) -> TemporaryApp? {
        host.appObjects.first { $0.id == host.currentGame }
    }

    // MARK: Snapshots

    private func refreshHostItems() {
        let sorted = hostList.sorted { $0.compareName($1) == .orderedAscending }
        let items = sorted.map { item(for: $0) }
        if items != hosts {
            hosts = items
        }
        if let id = selectedHostID, !items.contains(where: { $0.id == id }) {
            // The selected host disappeared (removed)
            showHostSelectionView()
        }
    }

    /// Refreshes the dynamic parts (running, hidden) of the currently displayed apps.
    /// The set of displayed apps itself only changes in updateAppsForHost.
    private func refreshAppItems() {
        guard let host = selectedHost else { return }
        var updated: [AppItem] = []
        for existing in apps {
            guard let app = appObject(id: existing.id, in: host) else { continue }
            updated.append(AppItem(id: existing.id, name: app.name ?? existing.name, hidden: app.hidden,
                                   running: app.id == host.currentGame))
        }
        if updated != apps {
            apps = updated
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.refreshHostItems()
                self.refreshAppItems()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: Saved hosts / discovery

    private func retrieveSavedHosts() {
        let saved = (DataManager().getHosts() as? [TemporaryHost]) ?? []
        for host in saved where !hostList.contains(where: { $0 === host }) {
            hostList.append(host)
        }

        // Initialize the non-persistent host state
        for host in hostList {
            if host.activeAddress == nil { host.activeAddress = host.localAddress }
            if host.activeAddress == nil { host.activeAddress = host.externalAddress }
            if host.activeAddress == nil { host.activeAddress = host.address }
            if host.activeAddress == nil { host.activeAddress = host.ipv6Address }
        }
    }

    fileprivate func updateAllHosts(_ hosts: [TemporaryHost]) {
        hostList = hosts
        updateHosts()
    }

    private func updateHosts() {
        refreshHostItems()
        updateHostShortcuts()
    }

    private func updateHostShortcuts() {
        #if os(iOS)
        var quickActions: [UIApplicationShortcutItem] = []
        for host in hostList {
            // Pair state may be unknown if we haven't polled it yet, but the app list
            // count will persist from paired PCs
            if host.appList.count > 0 {
                quickActions.append(UIApplicationShortcutItem(
                    type: "PC",
                    localizedTitle: host.name,
                    localizedSubtitle: nil,
                    icon: UIApplicationShortcutIcon(type: .play),
                    userInfo: ["UUID": host.uuid as NSString]))
            }
        }
        UIApplication.shared.shortcutItems = quickActions
        #endif
    }

    // MARK: Lifecycle

    /// Called when the root view appears (mirrors viewDidAppear/viewWillAppear of the old main screen).
    func start() {
        handlePendingShortcutAction()
        beginForegroundRefresh()
    }

    private func beginForegroundRefresh() {
        guard !isBackground, !isStreaming else { return }

        // This will kick off box art caching
        updateHosts()
        startPolling()

        // Reset state first so we can rediscover hosts that were deleted before
        discMan.resetDiscoveryState()
        discMan.startDiscovery()

        // This will refresh the applist when a paired host is selected
        if let host = selectedHost, host.pairState == .paired {
            hostClicked(host, userInitiated: false)
        }
    }

    private func handleReturnToForeground() {
        isBackground = false
        guard !isStreaming else { return }
        beginForegroundRefresh()

        // Check for a pending shortcut action when returning to foreground
        handlePendingShortcutAction()
    }

    private func handleEnterBackground() {
        isBackground = true
        guard !isStreaming else { return }
        discMan.stopDiscovery()
        stopPolling()
    }

    private func streamDidEnd() {
        isStreaming = false
        boxArtCache.removeAllObjects()
        // Re-fetches the selected host's serverinfo so currentGame is fresh
        beginForegroundRefresh()
        handlePendingShortcutAction()
    }

    private func handlePendingShortcutAction() {
        #if os(iOS)
        guard let delegate = UIApplication.shared.delegate as? AppDelegate,
              let uuid = delegate.pcUuidToLoad else { return }

        // Find the host it corresponds to
        let matchingHost = hostList.first { $0.uuid == uuid }

        // Clear the pending shortcut action
        delegate.pcUuidToLoad = nil

        // Complete the request
        if let completion = delegate.shortcutCompletionHandler {
            completion(matchingHost != nil)
            delegate.shortcutCompletionHandler = nil
        }

        if let matchingHost, selectedHost !== matchingHost {
            // Navigate to the host page
            hostClicked(matchingHost, userInitiated: false)
        }
        #endif
    }

    // MARK: Selection

    /// Sidebar selection changed by the user.
    func userSelected(_ id: String?) {
        guard let id else {
            if selectedHost != nil {
                showHostSelectionView()
            }
            return
        }
        guard let host = hostObject(id: id) else { return }
        if selectedHost !== host {
            // "View All Apps" applies only to the host it was chosen for
            showHiddenApps = false
        }
        hostClicked(host, userInitiated: true)
    }

    func showHostSelectionView() {
        appManager.stopRetrieving()
        showHiddenApps = false
        selectedHost = nil
        selectedHostID = nil
        apps = []
        appsLoaded = false
    }

    private func setSelected(_ host: TemporaryHost) {
        if selectedHost !== host {
            apps = []
            appsLoaded = false
        }
        selectedHost = host
        selectedHostID = host.uuid
    }

    // MARK: Host click / connect / pair

    private func hostClicked(_ host: TemporaryHost, userInitiated: Bool) {
        // Treat clicks on offline hosts to be long clicks: this shows the actions
        // (wake, remove, ...) rather than just hanging for a while and failing.
        if host.state != .online && userInitiated {
            hostActionsTarget = item(for: host)
            // Keep the sidebar selection in sync with the actual selection
            selectedHostID = selectedHost?.uuid
            return
        }

        setSelected(host)

        // If we are online, paired, and have a cached app list, skip straight
        // to the app grid without a loading frame. This is the fast path that users
        // should hit most. We don't take it after coming back from streaming or the
        // foreground, since we need to fetch serverinfo too so that our active game data is correct.
        if host.state == .online && host.pairState == .paired && host.appList.count > 0 && userInitiated {
            alreadyPaired()
            return
        }

        busyMessage = "Connecting…"
        let discMan = discMan!
        let clientCert = clientCert
        let bridge = bridge
        let opQueue = opQueue

        Task.detached { [weak self] in
            // Wait for the PC's status to be known
            while host.state == .unknown {
                try? await Task.sleep(for: .seconds(1))
            }

            // Don't bother polling if the server is already offline
            if host.state == .offline {
                await MainActor.run {
                    self?.busyMessage = nil
                    self?.showHostSelectionView()
                }
                return
            }

            let hMan = HttpManager(host: host)!
            let serverInfoResp = ServerInfoResponse()

            // Exempt this host from discovery while handling the serverinfo request
            discMan.pauseDiscovery(for: host)
            hMan.executeRequestSynchronously(HttpRequest(for: serverInfoResp, with: hMan.newServerInfoRequest(false),
                                                         fallbackError: 401, fallbackRequest: hMan.newHttpServerInfoRequest()))
            discMan.resumeDiscovery(for: host)

            if !serverInfoResp.isStatusOk() {
                let message = serverInfoResp.statusMessage ?? ""
                await MainActor.run {
                    guard let self else { return }
                    if host !== self.selectedHost {
                        self.busyMessage = nil
                        return
                    }

                    // Only display an alert if this was the result of a real
                    // user action, not just passively entering the foreground again
                    self.busyMessage = nil
                    self.showHostSelectionView()
                    if userInitiated {
                        self.alert = AlertContent(title: "Connection Failed", message: message, showsHelp: true)
                    }
                    host.state = .offline
                }
            } else {
                // Update the host object with this data
                serverInfoResp.populateHost(host)
                if host.pairState == .paired {
                    NSLog("Already Paired")
                    await MainActor.run { self?.alreadyPaired() }
                }
                // Only pair when this was the result of explicit user action
                else if userInitiated {
                    NSLog("Trying to pair")
                    // Polling the server while pairing causes the server to screw up
                    discMan.stopDiscoveryBlocking()
                    let pairManager = PairManager(manager: hMan, clientCert: clientCert, callback: bridge)!
                    opQueue.addOperation(pairManager)
                } else {
                    // Not user action, so just return to host screen
                    await MainActor.run {
                        self?.busyMessage = nil
                        self?.showHostSelectionView()
                    }
                }
            }
        }
    }

    fileprivate func startPairing(_ pin: String) {
        // The loading overlay stays behind the sheet, like the original alert did
        pairing = PairingInfo(hostName: selectedHost?.name ?? "your PC", pin: pin)
    }

    func cancelPairing() {
        pairing = nil
        discMan.startDiscovery()
        busyMessage = nil
        showHostSelectionView()
    }

    fileprivate func pairFailed(_ message: String) {
        guard pairing != nil else { return }
        pairing = nil

        discMan.startDiscovery()
        busyMessage = nil
        showHostSelectionView()
        showAlert(AlertContent(title: "Pairing Failed", message: message, showsHelp: true), afterSheet: true)
    }

    fileprivate func pairSuccessful(_ serverCert: Data) {
        // Store the cert from pairing with the host
        selectedHost?.serverCert = serverCert

        pairing = nil
        discMan.startDiscovery()
        busyMessage = "Loading apps…"
        alreadyPaired()
    }

    fileprivate func pairedAlready() {
        pairing = nil
        busyMessage = "Loading apps…"
        alreadyPaired()
    }

    // MARK: App list

    private func alreadyPaired() {
        // Capture the host here because it can change once we leave the main thread
        guard let host = selectedHost else {
            busyMessage = nil
            return
        }

        if host.appList.count > 0 {
            updateAppsForHost(host)
            busyMessage = nil
        }

        let discMan = discMan!
        Task.detached { [weak self] in
            // Exempt this host from discovery while handling the applist query
            discMan.pauseDiscovery(for: host)
            let appListResp = ConnectionHelper.getAppList(for: host)
            discMan.resumeDiscovery(for: host)

            let appList = appListResp?.getAppList()
            if appListResp == nil || !appListResp!.isStatusOk() || appList == nil {
                let message = appListResp?.statusMessage ?? ""
                await MainActor.run {
                    guard let self else { return }
                    if host !== self.selectedHost {
                        self.busyMessage = nil
                        return
                    }
                    self.busyMessage = nil
                    self.showHostSelectionView()
                    self.alert = AlertContent(title: "Connection Interrupted", message: message, showsHelp: true)
                    host.state = .offline
                }
            } else {
                await MainActor.run {
                    guard let self else { return }
                    self.updateApplist(appList!, for: host)

                    if host !== self.selectedHost {
                        self.busyMessage = nil
                        return
                    }

                    self.updateAppsForHost(host)
                    self.appManager.stopRetrieving()
                    self.appManager.retrieveAssets(from: host)
                    self.busyMessage = nil
                }
            }
        }
    }

    /// Pull to refresh: re-fetches the app list without any overlay.
    func refreshAppList() async {
        guard let host = selectedHost, host.pairState == .paired else { return }
        let discMan = discMan!
        let appList: Set<AnyHashable>? = await Task.detached {
            discMan.pauseDiscovery(for: host)
            let response = ConnectionHelper.getAppList(for: host)
            discMan.resumeDiscovery(for: host)
            guard let response, response.isStatusOk() else { return nil }
            return response.getAppList()
        }.value

        guard let appList, host === selectedHost else { return }
        updateApplist(appList, for: host)
        updateAppsForHost(host)
        appManager.stopRetrieving()
        appManager.retrieveAssets(from: host)
    }

    private func updateAppEntry(_ app: TemporaryApp, for host: TemporaryHost) {
        let database = DataManager()
        for savedApp in host.appObjects where savedApp.id == app.id {
            savedApp.name = app.name
            savedApp.hdrSupported = app.hdrSupported
            savedApp.hidden = app.hidden

            database.updateApps(forExisting: host)
            return
        }
    }

    private func updateApplist(_ newList: Set<AnyHashable>, for host: TemporaryHost) {
        let database = DataManager()
        var merged = host.appList
        let newApps = newList.compactMap { $0 as? TemporaryApp }

        for app in newApps {
            let saved = merged.compactMap({ $0 as? TemporaryApp }).first { $0.id == app.id }
            if let saved {
                saved.name = app.name
                saved.hdrSupported = app.hdrSupported
                // Don't propagate hidden, because we want the local data to prevail
            } else {
                app.host = host
                merged.insert(app)
            }
        }

        for case let app as TemporaryApp in Array(merged) where !newApps.contains(where: { $0.id == app.id }) {
            merged.remove(app)

            // It's important to remove the app record from the database
            // since we'll have a constraint violation now that appList
            // doesn't have this app in it.
            database.remove(app)
        }

        host.appList = merged
        database.updateApps(forExisting: host)

        // This host may be eligible for a shortcut now that the app list
        // has been populated
        updateHostShortcuts()
    }

    private func updateAppsForHost(_ host: TemporaryHost) {
        guard host === selectedHost else {
            NSLog("Mismatched host during app update")
            return
        }

        var list = host.appObjects
        list.sort { $0.compareName($1) == .orderedAscending }
        if !showHiddenApps {
            list = list.filter { !$0.hidden }
        }
        apps = list.compactMap { app in
            guard let id = app.id else { return nil }
            return AppItem(id: id, name: app.name ?? "", hidden: app.hidden, running: id == host.currentGame)
        }
        appsLoaded = true
    }

    // MARK: Box art

    fileprivate func receivedAsset(for app: TemporaryApp) {
        boxArtCache.removeObject(forKey: artKey(host: app.host?.uuid, appID: app.id))
        artVersion += 1
    }

    private func artKey(host: String?, appID: String?) -> NSString {
        "\(host ?? "")/\(appID ?? "")" as NSString
    }

    /// Returns the decoded box art, or nil when there's none (including the blank GFE placeholder).
    func boxArt(for appID: String) async -> UIImage? {
        guard let host = selectedHost, let app = appObject(id: appID, in: host) else { return nil }
        let key = artKey(host: host.uuid, appID: appID)
        if let cached = boxArtCache.object(forKey: key) {
            return cached
        }

        let path = AppAssetManager.boxArtPath(for: app)
        let image: UIImage? = await Task.detached {
            guard let path, let loaded = UIImage(contentsOfFile: path) else { return nil }

            // This size of image might be blank image received from GameStream.
            if (loaded.size.width == 130 && loaded.size.height == 180) || // GFE 2.0
                (loaded.size.width == 628 && loaded.size.height == 888) { // GFE 3.0
                return nil
            }
            // Force decoding now rather than lazily while scrolling
            return await loaded.byPreparingForDisplay() ?? loaded
        }.value

        if let image {
            boxArtCache.setObject(image, forKey: key)
        }
        return image
    }

    // MARK: Host actions

    func actions(for host: HostItem) -> [HostAction] {
        var actions: [HostAction] = []
        if host.connection != .online {
            actions.append(.wake)
        } else if host.pairing == .paired {
            actions.append(.viewAllApps)
            #if os(iOS)
            if host.isNvidiaServerSoftware {
                actions.append(.gameStreamEndOfService)
            }
            #endif
        }
        actions.append(.testNetwork)
        #if os(iOS)
        if host.connection != .online {
            actions.append(.gameStreamEndOfService)
            actions.append(.connectionHelp)
        }
        #endif
        actions.append(.remove)
        return actions
    }

    func perform(_ action: HostAction, on item: HostItem) {
        guard let host = hostObject(id: item.id) else { return }
        switch action {
        case .wake:
            if host.mac == nil || host.mac == "00:00:00:00:00:00" {
                alert = AlertContent(title: "Wake-On-LAN", message: "Host MAC unknown, unable to send WOL Packet")
            } else {
                DispatchQueue.global().async {
                    WakeOnLanManager.wake(host)
                }
                alert = AlertContent(title: "Wake-On-LAN", message: "Successfully sent wake-up request. It may take a few moments for the PC to wake. If it never wakes up, ensure it's properly configured for Wake-on-LAN.")
            }

        case .viewAllApps:
            showHiddenApps = true
            hostClicked(host, userInitiated: true)

        case .gameStreamEndOfService:
            #if os(iOS)
            Utils.launchUrl(HelpURL.gameStreamEndOfService)
            #endif

        case .connectionHelp:
            #if os(iOS)
            Utils.launchUrl(HelpURL.troubleshooting)
            #endif

        case .testNetwork:
            testNetwork()

        case .remove:
            removeTarget = item
        }
    }

    func confirmRemove(_ item: HostItem) {
        guard let host = hostObject(id: item.id) else { return }
        discMan.removeHost(fromDiscovery: host)
        DataManager().remove(host)
        hostList.removeAll { $0 === host }
        if selectedHost === host {
            showHostSelectionView()
        }
        updateAllHosts(hostList)
    }

    private func testNetwork() {
        busyMessage = "Testing network…"
        Task.detached { [weak self] in
            // Perform the network test on a worker thread. It may take a while.
            let portTestResult = LiTestClientConnectivity(connectivityTestServer, 443, UInt32(ML_PORT_FLAG_ALL))
            let message: String
            if portTestResult == 0 {
                message = "This network does not appear to be blocking Moonlight. If you still have trouble connecting, check your PC's firewall settings.\n\nVisit the Moonlight Setup Guide on GitHub for additional setup help and troubleshooting steps."
            } else if portTestResult == UInt32(ML_TEST_RESULT_INCONCLUSIVE) {
                message = "The network test could not be performed because none of Moonlight's connection testing servers were reachable. Check your Internet connection or try again later."
            } else {
                var buffer = [CChar](repeating: 0, count: 512)
                LiStringifyPortFlags(portTestResult, "\n", &buffer, Int32(buffer.count))
                message = "Your current network connection seems to be blocking Moonlight. Streaming may not work while connected to this network.\n\nThe following network ports were blocked:\n\(String(cString: buffer))"
            }
            await MainActor.run {
                self?.busyMessage = nil
                self?.alert = AlertContent(title: "Network Test Complete", message: message)
            }
        }
    }

    /// Adds a PC by address. Returns nil on success or the message to show inline.
    func addHost(address: String) async -> String? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let discMan = discMan!

        let result: (TemporaryHost?, String?) = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                discMan.discoverHost(trimmed) { host, error in
                    continuation.resume(returning: (host, error))
                }
            }
        }

        if let host = result.0 {
            if !hostList.contains(where: { $0 === host }) {
                hostList.append(host)
            }
            updateHosts()
            return nil
        }

        var error = result.1 ?? "Failed to add the PC."
        let portTestResults = await Task.detached {
            LiTestClientConnectivity(connectivityTestServer, 443, UInt32(ML_PORT_FLAG_TCP_47984 | ML_PORT_FLAG_TCP_47989))
        }.value
        if portTestResults != UInt32(ML_TEST_RESULT_INCONCLUSIVE) && portTestResults != 0 {
            error += "\n\nYour device's network connection is blocking Moonlight. Streaming may not work while connected to this network."
        }
        return error
    }

    // MARK: App actions

    func appClicked(_ id: String) {
        guard let host = selectedHost, let app = appObject(id: id, in: host) else { return }
        appManager.stopRetrieving()

        if findRunningApp(host) != nil {
            // If there's a running app, display a menu
            appActionsTarget = apps.first { $0.id == id }
        } else {
            prepareToStreamApp(app)
        }
    }

    func actions(for item: AppItem) -> [AppAction] {
        guard let host = selectedHost else { return [] }
        let currentApp = findRunningApp(host)
        let isCurrent = currentApp?.id == item.id

        var actions: [AppAction] = []
        actions.append(.launch(title: currentApp == nil ? "Launch App" : (isCurrent ? "Resume App" : "Resume Running App")))
        if currentApp != nil {
            actions.append(.quit(title: isCurrent ? "Quit App" : "Quit Running App and Start"))
        }
        if currentApp == nil || !isCurrent || item.hidden {
            actions.append(.setHidden(!item.hidden))
        }
        return actions
    }

    func message(for item: AppItem) -> String {
        guard let host = selectedHost else { return "" }
        let currentApp = findRunningApp(host)
        if currentApp == nil || currentApp?.id == item.id {
            return item.hidden ? "Hidden" : ""
        }
        return "\(currentApp?.name ?? "An app") is currently running"
    }

    func perform(_ action: AppAction, on item: AppItem) {
        guard let host = selectedHost, let app = appObject(id: item.id, in: host) else { return }
        appManager.stopRetrieving()
        let currentApp = findRunningApp(host)

        switch action {
        case .launch:
            if let currentApp {
                NSLog("Resuming application: %@", currentApp.name ?? "")
                prepareToStreamApp(currentApp)
            } else {
                NSLog("Launching application: %@", app.name ?? "")
                prepareToStreamApp(app)
            }

        case .quit:
            guard let currentApp else { return }
            quit(currentApp: currentApp, thenStart: app)

        case .setHidden(let hidden):
            app.hidden = hidden
            updateAppEntry(app, for: host)
            // Don't call updateAppsForHost because that will nuke this
            // app immediately if we're not showing hidden apps.
            refreshAppItems()
        }
    }

    private func quit(currentApp: TemporaryApp, thenStart app: TemporaryApp) {
        NSLog("Quitting application: %@", currentApp.name ?? "")
        guard let host = app.host else { return }
        busyMessage = "Quitting \(currentApp.name ?? "app")…"
        let discMan = discMan!

        Task.detached { [weak self] in
            let hMan = HttpManager(host: host)!
            let quitResponse = HttpResponse()
            let quitRequest = HttpRequest(for: quitResponse, with: hMan.newQuitAppRequest())

            // Exempt this host from discovery while handling the quit operation
            discMan.pauseDiscovery(for: host)
            hMan.executeRequestSynchronously(quitRequest)
            if quitResponse.statusCode == 200 {
                let serverInfoResp = ServerInfoResponse()
                hMan.executeRequestSynchronously(HttpRequest(for: serverInfoResp, with: hMan.newServerInfoRequest(false),
                                                             fallbackError: 401, fallbackRequest: hMan.newHttpServerInfoRequest()))
                if !serverInfoResp.isStatusOk() || (serverInfoResp.getStringTag("state")?.hasSuffix("_SERVER_BUSY") ?? false) {
                    // On newer GFE versions, the quit request succeeds even though the app doesn't
                    // really quit if another client tries to kill your app. We'll patch the response
                    // to look like the old error in that case, so the UI behaves.
                    quitResponse.statusCode = 599
                } else if serverInfoResp.isStatusOk() {
                    // Update the host object with this info
                    serverInfoResp.populateHost(host)
                }
            }
            discMan.resumeDiscovery(for: host)

            let succeeded = quitResponse.statusCode == 200
            await MainActor.run {
                guard let self else { return }
                // If it fails, display an error and stop the current operation
                if !succeeded {
                    self.updateAppsForHost(host)
                    self.busyMessage = nil
                    self.alert = AlertContent(title: "Quitting App Failed",
                                              message: "Failed to quit app. If this app was started by another device, you'll need to quit from that device.")
                } else {
                    host.currentGame = "0"
                    self.refreshAppItems()
                    // If it succeeds and we're to start streaming, start the stream
                    if app.id != currentApp.id {
                        self.prepareToStreamApp(app)
                        self.busyMessage = nil
                    } else {
                        // Otherwise, just hide the loading icon
                        self.busyMessage = nil
                    }
                }
            }
        }
    }

    private func prepareToStreamApp(_ app: TemporaryApp) {
        isStreaming = true
        stopPolling()
        discMan.stopDiscovery()
        appManager.stopRetrieving()
        let config = StreamLauncher.makeConfiguration(for: app)
        if !StreamLauncher.present(config) {
            streamDidEnd()
        }
    }

    // MARK: Alerts

    /// Alerts raised right after a sheet closes need a moment, otherwise SwiftUI drops them.
    private func showAlert(_ content: AlertContent, afterSheet: Bool) {
        guard afterSheet else {
            alert = content
            return
        }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            alert = content
        }
    }

    func openHelp() {
        #if os(iOS)
        Utils.launchUrl(HelpURL.troubleshooting)
        #endif
    }
}

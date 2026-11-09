import Foundation

/// tvOS settings, persisted to the same NSUserDefaults keys that Settings.bundle (the system
/// Settings app) edits and TemporarySettings reads on tvOS.
struct TVSettings: Equatable {
    // Values of the `streamResolution` key (see TemporarySettings.m): 0 = 720p, 1 = 1080p, 2 = 4K, 3 = 1440p
    static let resolutions: [(title: String, value: Int, width: Int, height: Int)] = [
        ("720p", 0, 1280, 720),
        ("1080p", 1, 1920, 1080),
        ("1440p", 3, 2560, 1440),
        ("4K", 2, 3840, 2160),
    ]
    static let framerates = [30, 60]
    static let audioConfigs: [(title: String, value: Int)] = [("Stereo", 2), ("LPCM 5.1", 6), ("LPCM 7.1", 8)]
    static let codecs: [(title: String, value: Int)] = [("Auto", 0), ("H.264", 1), ("HEVC", 2)]
    static let framePacing: [(title: String, value: Int)] = [("Lowest Latency", 0), ("Smoothest Video", 1)]
    // Same list as Settings.bundle, plus the notches the auto-bitrate formula can produce
    static let bitrates = [500, 1000, 1500, 2000, 2500, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 10000,
                           12000, 15000, 18000, 20000, 25000, 30000, 40000, 50000, 60000, 70000, 80000,
                           100000, 120000, 150000]

    var resolution = 1
    var framerate = 60
    var bitrate = 20000
    var audioConfig = 2
    var codec = 0
    var framePacing = 0
    var hdr = false
    var playAudioOnPC = false
    var optimizeGames = true
    var multiController = true
    var swapABXYButtons = false
    var btMouseSupport = false
    var statsOverlay = false

    var bitrateOptions: [Int] {
        Self.bitrates.contains(bitrate) ? Self.bitrates : (Self.bitrates + [bitrate]).sorted()
    }

    static func bitrateTitle(_ bitrate: Int) -> String {
        let mbps = Double(bitrate) / 1000.0
        return mbps == mbps.rounded() ? "\(Int(mbps)) Mbps" : String(format: "%.1f Mbps", mbps)
    }

    /// Same behaviour as the iOS settings: picking a resolution or frame rate re-derives the bitrate.
    mutating func applyAutoBitrate() {
        guard let res = Self.resolutions.first(where: { $0.value == resolution }) else { return }
        bitrate = SettingsModel.autoBitrate(fps: framerate, width: res.width, height: res.height)
    }

    static func load() -> TVSettings {
        // Creating TemporarySettings registers the defaults from Settings.bundle
        _ = DataManager().getSettings()
        let defaults = UserDefaults.standard

        var settings = TVSettings()
        settings.resolution = defaults.integer(forKey: "streamResolution")
        settings.framerate = defaults.integer(forKey: "framerate") == 30 ? 30 : 60
        settings.bitrate = defaults.integer(forKey: "bitrate")
        settings.audioConfig = defaults.integer(forKey: "audioConfig")
        settings.codec = defaults.integer(forKey: "preferredCodec")
        settings.framePacing = defaults.integer(forKey: "useFramePacing") != 0 ? 1 : 0
        settings.hdr = defaults.bool(forKey: "enableHdr")
        settings.playAudioOnPC = defaults.bool(forKey: "audioOnPC")
        settings.optimizeGames = defaults.bool(forKey: "optimizeGames")
        settings.multiController = defaults.bool(forKey: "multipleControllers")
        settings.swapABXYButtons = defaults.bool(forKey: "swapABXYButtons")
        settings.btMouseSupport = defaults.bool(forKey: "btMouseSupport")
        settings.statsOverlay = defaults.bool(forKey: "statsOverlay")
        return settings
    }

    func save() {
        let defaults = UserDefaults.standard
        // Multi-value keys are strings in Settings.bundle; keep that encoding for the system Settings app
        defaults.set(String(resolution), forKey: "streamResolution")
        defaults.set(String(framerate), forKey: "framerate")
        defaults.set(String(bitrate), forKey: "bitrate")
        defaults.set(String(audioConfig), forKey: "audioConfig")
        defaults.set(String(codec), forKey: "preferredCodec")
        defaults.set(String(framePacing), forKey: "useFramePacing")
        defaults.set(hdr, forKey: "enableHdr")
        defaults.set(playAudioOnPC, forKey: "audioOnPC")
        defaults.set(optimizeGames, forKey: "optimizeGames")
        defaults.set(multiController, forKey: "multipleControllers")
        defaults.set(swapABXYButtons, forKey: "swapABXYButtons")
        defaults.set(btMouseSupport, forKey: "btMouseSupport")
        defaults.set(statsOverlay, forKey: "statsOverlay")
    }
}

import AVFoundation
import Observation
import UIKit
import VideoToolbox

/// Port of SettingsViewController: tables, capability checks, auto-bitrate and persistence.
@MainActor
@Observable
final class SettingsModel {
    enum Codec: Hashable {
        case h264, hevc, av1, auto

        var title: String {
            switch self {
            case .h264: return "H.264"
            case .hevc: return "HEVC"
            case .av1: return "AV1"
            case .auto: return "Auto"
            }
        }
    }

    struct Resolution: Equatable {
        var width: Int
        var height: Int
    }

    static let bitrateTable: [Int] = [
        500, 1000, 1500, 2000, 2500, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 10000,
        12000, 15000, 18000, 20000, 30000, 40000, 50000, 60000, 70000, 80000, 100000,
        120000, 150000,
    ]

    // Values of the anonymous preferredCodec enum in TemporarySettings.h (not imported into Swift)
    static let codecPrefAUTO = 0
    static let codecPrefH264 = 1
    static let codecPrefHEVC = 2
    static let codecPrefAV1 = 3

    static let customResolutionIndex = 6
    static let resolutionNames = ["360p", "720p", "1080p", "4K", "Safe Area", "Full", "Custom"]

    // Capability checks
    let supports120Fps: Bool
    let supportsHEVC: Bool
    let supportsAV1: Bool
    let supportsHDR: Bool
    let availableCodecs: [Codec]

    private(set) var resolutionTable: [Resolution]
    private(set) var resolutionIndex: Int
    private(set) var bitrate: Int

    var framerate: Int
    var codec: Codec
    var hdr: Bool
    var absoluteTouchMode: Bool
    var onscreenControls: Int
    var optimizeGames: Bool
    var multiController: Bool
    var swapABXYButtons: Bool
    var playAudioOnPC: Bool
    var framePacing: Bool
    var btMouseSupport: Bool
    var statsOverlay: Bool

    init() {
        let current = DataManager().getSettings()!

        let screen = StreamLauncher.activeWindowScene()?.screen ?? UIScreen.main
        supports120Fps = screen.maximumFramesPerSecond > 62
        supportsHEVC = VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
        supportsAV1 = VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
        supportsHDR = supportsHEVC && AVPlayer.availableHDRModes.contains(.hdr10)

        var codecs: [Codec] = [.h264]
        if supportsHEVC { codecs.append(.hevc) }
        if supportsAV1 { codecs.append(.av1) }
        codecs.append(.auto)
        availableCodecs = codecs

        // Ensure we pick a bitrate that falls exactly onto a slider notch
        bitrate = Self.bitrateTable[Self.sliderIndex(forBitrate: current.bitrate.intValue)]

        // Get the size of the screen with and without safe area insets
        let window = StreamLauncher.activeWindowScene()?.windows.first
        let scale = screen.scale
        let windowSize = window?.frame.size ?? screen.bounds.size
        let insets = window?.safeAreaInsets ?? .zero
        let safeAreaWidth = (windowSize.width - insets.left - insets.right) * scale
        let fullScreenWidth = windowSize.width * scale
        let fullScreenHeight = windowSize.height * scale

        var table = [
            Resolution(width: 640, height: 360),
            Resolution(width: 1280, height: 720),
            Resolution(width: 1920, height: 1080),
            Resolution(width: 3840, height: 2160),
            Resolution(width: Int(safeAreaWidth), height: Int(fullScreenHeight)),
            Resolution(width: Int(fullScreenWidth), height: Int(fullScreenHeight)),
            Resolution(width: current.width.intValue, height: current.height.intValue), // custom initial value
        ]

        // Don't populate the custom entry unless we have a custom resolution
        if !Self.isCustomResolution(table[Self.customResolutionIndex], table: table) {
            table[Self.customResolutionIndex] = Resolution(width: 0, height: 0)
        }
        resolutionTable = table

        var index = 1
        for (i, res) in table.enumerated() where res.height == current.height.intValue && res.width == current.width.intValue {
            index = i
            break
        }
        resolutionIndex = index

        switch current.framerate.intValue {
        case 30: framerate = 30
        case 120: framerate = 120
        default: framerate = 60
        }

        let preferred = Int(current.preferredCodec)
        if preferred == Self.codecPrefAV1 && supportsAV1 {
            codec = .av1
        } else if preferred == Self.codecPrefHEVC && supportsHEVC {
            codec = .hevc
        } else if preferred == Self.codecPrefH264 {
            codec = .h264
        } else {
            codec = .auto
        }

        hdr = supportsHDR && current.enableHdr
        absoluteTouchMode = current.absoluteTouchMode
        onscreenControls = current.onscreenControls.intValue
        optimizeGames = current.optimizeGames
        multiController = current.multiController
        swapABXYButtons = current.swapABXYButtons
        playAudioOnPC = current.playAudioOnPC
        framePacing = current.useFramePacing
        btMouseSupport = current.btMouseSupport
        statsOverlay = current.statsOverlay
    }

    // MARK: Resolution

    private static func isCustomResolution(_ res: Resolution, table: [Resolution]) -> Bool {
        if res.width == 0 && res.height == 0 {
            return false
        }
        for i in 0..<customResolutionIndex where table[i] == res {
            return false
        }
        return true
    }

    var chosenResolution: Resolution {
        resolutionTable[resolutionIndex]
    }

    var hasCustomResolution: Bool {
        resolutionTable[Self.customResolutionIndex] != Resolution(width: 0, height: 0)
    }

    func resolutionTitle(at index: Int) -> String {
        let res = resolutionTable[index]
        switch index {
        case 4, 5: return "\(Self.resolutionNames[index]) (\(res.width) × \(res.height))"
        case Self.customResolutionIndex:
            return hasCustomResolution ? "Custom (\(res.width) × \(res.height))" : "Custom…"
        default: return Self.resolutionNames[index]
        }
    }

    func isResolutionEnabled(at index: Int) -> Bool {
        // Only enable the 4K option for "recent" devices. We'll judge that by whether
        // they support HEVC decoding (A9 or later).
        index == 3 ? supportsHEVC : true
    }

    func selectResolution(at index: Int) {
        resolutionIndex = index
        updateBitrate()
    }

    /// Returns false when the dimensions are unusable (the previous selection is kept).
    @discardableResult
    func setCustomResolution(width: Int, height: Int) -> Bool {
        if width <= 0 || height <= 0 {
            return false
        }

        // H.264 maximum, or the HEVC maximum when the device decodes HEVC
        let maxDimension = supportsHEVC ? 8192 : 4096

        // Cap to maximum and minimum valid dimensions
        let w = max(min(width, maxDimension), 256)
        let h = max(min(height, maxDimension), 256)

        resolutionTable[Self.customResolutionIndex] = Resolution(width: w, height: h)
        resolutionIndex = Self.customResolutionIndex
        updateBitrate()
        return true
    }

    // MARK: Bitrate

    static func sliderIndex(forBitrate bitrate: Int) -> Int {
        for (i, value) in bitrateTable.enumerated() where bitrate <= value {
            return i
        }
        // Return the last entry in the table
        return bitrateTable.count - 1
    }

    var bitrateSliderValue: Double {
        get { Double(Self.sliderIndex(forBitrate: bitrate)) }
        set { bitrate = Self.bitrateTable[Int(newValue.rounded())] }
    }

    var bitrateText: String {
        String(format: "%.1f Mbps", Double(bitrate) / 1000.0)
    }

    func selectFramerate(_ fps: Int) {
        framerate = fps
        updateBitrate()
    }

    func updateBitrate() {
        bitrate = Self.autoBitrate(fps: framerate, width: chosenResolution.width, height: chosenResolution.height)
    }

    nonisolated static func autoBitrate(fps: Int, width: Int, height: Int) -> Int {
        // This logic is shamelessly stolen from Moonlight Qt:
        // https://github.com/moonlight-stream/moonlight-qt/blob/master/app/settings/streamingpreferences.cpp

        // Don't scale bitrate linearly beyond 60 FPS. It's definitely not a linear
        // bitrate increase for frame rate once we get to values that high.
        let frameRateFactor: Float = (fps <= 60 ? Float(fps) : (sqrtf(Float(fps) / 60.0) * 60.0)) / 30.0

        let resTable: [(pixels: Int, factor: Int)] = [
            (640 * 360, 1),
            (854 * 480, 2),
            (1280 * 720, 5),
            (1920 * 1080, 10),
            (2560 * 1440, 20),
            (3840 * 2160, 40),
        ]

        // Calculate the resolution factor by linear interpolation of the resolution table
        var resolutionFactor: Float = Float(resTable[resTable.count - 1].factor)
        let pixels = width * height
        for i in 0..<resTable.count {
            if pixels == resTable[i].pixels {
                // We can bail immediately for exact matches
                resolutionFactor = Float(resTable[i].factor)
                break
            } else if pixels < resTable[i].pixels {
                if i == 0 {
                    // Never go below the lowest resolution entry
                    resolutionFactor = Float(resTable[i].factor)
                } else {
                    // Interpolate between the entry greater than the chosen resolution (i) and the entry less than the chosen resolution (i-1)
                    let span = Float(resTable[i].pixels - resTable[i - 1].pixels)
                    resolutionFactor = (Float(pixels - resTable[i - 1].pixels) / span)
                        * Float(resTable[i].factor - resTable[i - 1].factor) + Float(resTable[i - 1].factor)
                }
                break
            }
            // Never go above the highest resolution entry (the default above)
        }

        let defaultBitrate = Int((resolutionFactor * frameRateFactor).rounded()) * 1000
        // Like the original, the computed value isn't snapped to a slider notch (only the slider position is)
        return min(defaultBitrate, 100000)
    }

    // MARK: Persistence

    func save() {
        let preferredCodec: UInt32
        switch codec {
        case .h264: preferredCodec = UInt32(Self.codecPrefH264)
        case .hevc: preferredCodec = UInt32(Self.codecPrefHEVC)
        case .av1: preferredCodec = UInt32(Self.codecPrefAV1)
        case .auto: preferredCodec = UInt32(Self.codecPrefAUTO)
        }
        let res = chosenResolution

        DataManager().saveSettings(withBitrate: bitrate,
                                   framerate: framerate,
                                   height: res.height,
                                   width: res.width,
                                   audioConfig: 2, // Stereo
                                   onscreenControls: onscreenControls,
                                   optimizeGames: optimizeGames,
                                   multiController: multiController,
                                   swapABXYButtons: swapABXYButtons,
                                   audioOnPC: playAudioOnPC,
                                   preferredCodec: preferredCodec,
                                   useFramePacing: framePacing,
                                   enableHdr: supportsHDR && hdr,
                                   btMouseSupport: btMouseSupport,
                                   absoluteTouchMode: absoluteTouchMode,
                                   statsOverlay: statsOverlay)
    }
}

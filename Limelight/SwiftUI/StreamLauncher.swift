import AVFoundation
import UIKit
import VideoToolbox

/// Builds a StreamConfiguration exactly like MainFrameViewController's prepareToStreamApp:
/// and presents the (UIKit) stream screen full screen.
enum StreamLauncher {
    private static func makeAudioConfiguration(channelCount: Int32, channelMask: Int32) -> Int32 {
        // Mirrors MAKE_AUDIO_CONFIGURATION() from Limelight.h
        return (channelMask << 16) | (channelCount << 8) | 0xCA
    }

    static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    static func makeConfiguration(for app: TemporaryApp) -> StreamConfiguration {
        let config = StreamConfiguration()
        config.host = app.host?.activeAddress
        config.httpsPort = app.host?.httpsPort ?? 0
        config.appID = app.id
        config.appName = app.name
        config.serverCert = app.host?.serverCert

        let streamSettings = DataManager().getSettings()!

        config.frameRate = streamSettings.framerate.int32Value
        // Don't stream more FPS than the display can show
        let maxFps = Int32((activeWindowScene()?.screen ?? UIScreen.main).maximumFramesPerSecond)
        if config.frameRate > maxFps {
            config.frameRate = maxFps
            NSLog("Clamping FPS to maximum refresh rate: %d", config.frameRate)
        }

        config.height = streamSettings.height.int32Value
        config.width = streamSettings.width.int32Value

        config.bitRate = streamSettings.bitrate.int32Value
        config.optimizeGameSettings = streamSettings.optimizeGames
        config.playAudioOnPC = streamSettings.playAudioOnPC
        config.useFramePacing = streamSettings.useFramePacing
        config.swapABXYButtons = streamSettings.swapABXYButtons

        // multiController must be set before calling getConnectedGamepadMask
        config.multiController = streamSettings.multiController
        config.gamepadMask = ControllerSupport.getConnectedGamepadMask(config)

        // Probe for supported channel configurations
        let physicalOutputChannels = Int32(AVAudioSession.sharedInstance().maximumOutputNumberOfChannels)
        NSLog("Audio device supports %d channels", physicalOutputChannels)

        let numberOfChannels = min(streamSettings.audioConfig.int32Value, physicalOutputChannels)
        NSLog("Selected number of audio channels %d", numberOfChannels)
        if numberOfChannels >= 8 {
            config.audioConfiguration = makeAudioConfiguration(channelCount: 8, channelMask: 0x63F)
        } else if numberOfChannels >= 6 {
            config.audioConfiguration = makeAudioConfiguration(channelCount: 6, channelMask: 0x3F)
        } else {
            config.audioConfiguration = makeAudioConfiguration(channelCount: 2, channelMask: 0x3)
        }

        config.serverCodecModeSupport = app.host?.serverCodecModeSupport ?? 0

        let hevcSupported = VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
        let av1Supported = VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
        let hdrSupported = AVPlayer.availableHDRModes.contains(.hdr10)

        let preferred = Int(streamSettings.preferredCodec)
        // Same fall-through chain as the original switch: AV1 -> HEVC -> H.264
        if preferred == SettingsModel.codecPrefAV1 && av1Supported {
            config.supportedVideoFormats |= VIDEO_FORMAT_AV1_MAIN8
        }
        if preferred == SettingsModel.codecPrefAV1 || preferred == SettingsModel.codecPrefAUTO || preferred == SettingsModel.codecPrefHEVC {
            if hevcSupported {
                config.supportedVideoFormats |= VIDEO_FORMAT_H265
            }
        }
        config.supportedVideoFormats |= VIDEO_FORMAT_H264

        // HEVC is supported if the user wants it (or it's required by the chosen resolution) and the SoC supports it
        if (config.width > 4096 || config.height > 4096 || streamSettings.enableHdr) && hevcSupported {
            config.supportedVideoFormats |= VIDEO_FORMAT_H265

            // HEVC Main10 is supported if the user wants it and the display supports it
            if streamSettings.enableHdr && hdrSupported {
                config.supportedVideoFormats |= VIDEO_FORMAT_H265_MAIN10
            }
        }

        // Add the AV1 Main10 format if AV1 and HDR are both enabled and supported
        if (config.supportedVideoFormats & VIDEO_FORMAT_MASK_AV1) != 0 && streamSettings.enableHdr && av1Supported && hdrSupported {
            config.supportedVideoFormats |= VIDEO_FORMAT_AV1_MAIN10
        }

        return config
    }

    /// Returns false if there was nothing to present the stream from.
    @MainActor
    @discardableResult
    static func present(_ config: StreamConfiguration) -> Bool {
        let stream = StreamControllerFactory.makeStreamViewController(withConfig: config)!

        let navigation = UINavigationController(rootViewController: stream)
        navigation.isNavigationBarHidden = true
        navigation.modalPresentationStyle = .fullScreen

        guard var top = activeWindowScene()?.keyWindow?.rootViewController ?? activeWindowScene()?.windows.first?.rootViewController else {
            return false
        }
        // Skip controllers that are on their way out, such as a confirmation
        // dialog dismissing after its action was chosen
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        top.present(navigation, animated: true)
        return true
    }
}

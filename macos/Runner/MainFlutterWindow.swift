import Cocoa
import FlutterMacOS
import MediaPlayer
import desktop_multi_window

class MainFlutterWindow: NSWindow, NSSpeechSynthesizerDelegate {
  private let nativeTts = NSSpeechSynthesizer()
  private var pendingTts: (text: String, result: FlutterResult)?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 1024, height: 680)
    nativeTts.delegate = self

    RegisterGeneratedPlugins(registry: flutterViewController)
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
    }
    configureNativeTts(with: flutterViewController)
    configureSystemMediaControls(with: flutterViewController)

    super.awakeFromNib()
  }

  private func configureSystemMediaControls(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "com.shadowing.english/system_media_controls",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "updatePlaybackState",
            let arguments = call.arguments as? [String: Any],
            let isPlaying = arguments["isPlaying"] as? Bool else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.updateSystemMediaPlaybackState(isPlaying: isPlaying)
      result(nil)
    }
    let commands = MPRemoteCommandCenter.shared()
    updateSystemMediaPlaybackState(isPlaying: false)
    commands.playCommand.isEnabled = true
    commands.pauseCommand.isEnabled = true
    commands.togglePlayPauseCommand.isEnabled = true
    commands.nextTrackCommand.isEnabled = true
    commands.previousTrackCommand.isEnabled = true
    commands.playCommand.addTarget { _ in
      channel.invokeMethod("play", arguments: nil)
      return .success
    }
    commands.pauseCommand.addTarget { _ in
      channel.invokeMethod("pause", arguments: nil)
      return .success
    }
    commands.togglePlayPauseCommand.addTarget { _ in
      channel.invokeMethod("toggle", arguments: nil)
      return .success
    }
    commands.nextTrackCommand.addTarget { _ in
      channel.invokeMethod("next", arguments: nil)
      return .success
    }
    commands.previousTrackCommand.addTarget { _ in
      channel.invokeMethod("previous", arguments: nil)
      return .success
    }
  }

  private func updateSystemMediaPlaybackState(isPlaying: Bool) {
    let infoCenter = MPNowPlayingInfoCenter.default()
    infoCenter.nowPlayingInfo = [
      MPMediaItemPropertyTitle: "英语学习",
      MPMediaItemPropertyArtist: "语言避难所",
      MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1 : 0
    ]
    infoCenter.playbackState = isPlaying ? .playing : .paused
  }

  private func configureNativeTts(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "com.shadowing.english/native_tts",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(false)
        return
      }

      switch call.method {
      case "speak":
        let arguments = call.arguments as? [String: Any]
        let text = (arguments?["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
          result(true)
          return
        }
        let voice = NSSpeechSynthesizer.VoiceName(
          rawValue: (arguments?["voice"] as? String) ?? ""
        )
        if NSSpeechSynthesizer.availableVoices.contains(voice) {
          self.nativeTts.setVoice(voice)
        }
        if let rate = arguments?["rate"] as? Double {
          self.nativeTts.rate = Float(rate) * 200
        }
        self.pendingTts = (text, result)
        if self.nativeTts.isSpeaking {
          self.nativeTts.stopSpeaking()
        } else {
          self.startPendingTts()
        }
      case "stop":
        self.pendingTts = nil
        self.nativeTts.stopSpeaking()
        result(true)
      case "getEngines":
        result(["defaultEngine": "", "engines": []])
      case "getVoices":
        let voices = NSSpeechSynthesizer.availableVoices.map { voice in
          let name = voice.rawValue
            .split(separator: ".")
            .last
            .map(String.init)?
            .replacingOccurrences(of: "-", with: " ")
            .capitalized ?? voice.rawValue
          return ["id": voice.rawValue, "label": name]
        }
        result(["voices": voices])
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func startPendingTts() {
    guard let pendingTts else {
      return
    }
    self.pendingTts = nil
    pendingTts.result(nativeTts.startSpeaking(pendingTts.text))
  }

  func speechSynthesizer(
    _ sender: NSSpeechSynthesizer,
    didFinishSpeaking finishedSpeaking: Bool
  ) {
    startPendingTts()
  }
}

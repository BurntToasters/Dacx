import Cocoa
import FlutterMacOS
import MediaPlayer

/// Bridges the Dart `run.rosie.dacx/media_session` channel to
/// `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`.
final class MediaSessionBridge {
  private let channelName = "run.rosie.dacx/media_session"
  private var channel: FlutterMethodChannel?
  private var enabled = false
  private var info: [String: Any] = [:]

  func attach(messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    ch.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    channel = ch
    configureRemoteCommands()
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setEnabled":
      let args = call.arguments as? [String: Any]
      enabled = (args?["enabled"] as? Bool) ?? false
      if !enabled { clear() }
      result(nil)
    case "update":
      guard enabled, let args = call.arguments as? [String: Any] else {
        result(nil); return
      }
      apply(args)
      result(nil)
    case "clear":
      clear()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func apply(_ args: [String: Any]) {
    if let title = args["title"] as? String, !title.isEmpty {
      info[MPMediaItemPropertyTitle] = title
    }
    if let artist = args["artist"] as? String, !artist.isEmpty {
      info[MPMediaItemPropertyArtist] = artist
    }
    if let album = args["album"] as? String, !album.isEmpty {
      info[MPMediaItemPropertyAlbumTitle] = album
    }
    if let durMs = args["durationMs"] as? Int, durMs > 0 {
      info[MPMediaItemPropertyPlaybackDuration] = Double(durMs) / 1000.0
    }
    if let posMs = args["positionMs"] as? Int {
      info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(posMs) / 1000.0
    }
    if let playing = args["playing"] as? Bool {
      info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
      MPNowPlayingInfoCenter.default().playbackState =
        playing ? .playing : .paused
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }

  private func clear() {
    info.removeAll()
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    MPNowPlayingInfoCenter.default().playbackState = .stopped
  }

  private func configureRemoteCommands() {
    let cc = MPRemoteCommandCenter.shared()
    cc.playCommand.isEnabled = true
    cc.pauseCommand.isEnabled = true
    cc.togglePlayPauseCommand.isEnabled = true
    cc.stopCommand.isEnabled = true
    cc.nextTrackCommand.isEnabled = true
    cc.previousTrackCommand.isEnabled = true
    cc.changePlaybackPositionCommand.isEnabled = true

    cc.playCommand.addTarget { [weak self] _ in
      self?.invokeCommand("play"); return .success
    }
    cc.pauseCommand.addTarget { [weak self] _ in
      self?.invokeCommand("pause"); return .success
    }
    cc.togglePlayPauseCommand.addTarget { [weak self] _ in
      self?.invokeCommand("toggle"); return .success
    }
    cc.stopCommand.addTarget { [weak self] _ in
      self?.invokeCommand("stop"); return .success
    }
    cc.nextTrackCommand.addTarget { [weak self] _ in
      self?.invokeCommand("next"); return .success
    }
    cc.previousTrackCommand.addTarget { [weak self] _ in
      self?.invokeCommand("previous"); return .success
    }
    cc.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let evt = event as? MPChangePlaybackPositionCommandEvent else {
        return .commandFailed
      }
      let posMs = Int(evt.positionTime * 1000.0)
      self?.invokeCommand("seek", positionMs: posMs)
      return .success
    }
  }

  private func invokeCommand(_ action: String, positionMs: Int? = nil) {
    var args: [String: Any] = ["action": action]
    if let pos = positionMs { args["positionMs"] = pos }
    DispatchQueue.main.async { [weak self] in
      self?.channel?.invokeMethod("command", arguments: args)
    }
  }
}

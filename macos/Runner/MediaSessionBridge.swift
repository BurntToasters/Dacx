import Cocoa
import FlutterMacOS
import MediaPlayer

/// Bridges the Dart `run.rosie.dacx/media_session` channel to
/// `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` (both process
/// singletons). Multiple Flutter engines may attach; the most recently
/// active one (last `setEnabled(true)` or `update`) receives remote-command
/// callbacks.
///
/// All mutable state (`channels`, `activeChannel`, `info`, `artworkTask`,
/// `enabled`) is owned by `stateQueue` (a serial queue) to keep multi-
/// engine attach/detach and the URLSession artwork callback off each other's
/// read-modify-write paths.
final class MediaSessionBridge {
  private let channelName = "run.rosie.dacx/media_session"
  private let stateQueue = DispatchQueue(label: "run.rosie.dacx.media-session-bridge.state")
  private var channels: [FlutterMethodChannel] = []
  private weak var activeChannel: FlutterMethodChannel?
  private var enabled = false
  private var info: [String: Any] = [:]
  private var artworkRequestId: UInt64 = 0
  private var artworkTask: URLSessionDataTask?
  private var commandsConfigured = false
  private var playbackRate: Double = 1.0

  deinit {
    let task = stateQueue.sync { artworkTask }
    task?.cancel()
  }

  func attach(messenger: FlutterBinaryMessenger) -> FlutterMethodChannel {
    let ch = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    ch.setMethodCallHandler { [weak self, weak ch] call, result in
      self?.handle(call, from: ch, result: result)
    }
    let needsCommandSetup: Bool = stateQueue.sync {
      channels.append(ch)
      if activeChannel == nil { activeChannel = ch }
      if commandsConfigured { return false }
      commandsConfigured = true
      return true
    }
    if needsCommandSetup {
      configureRemoteCommands()
    }
    return ch
  }

  /// Drop a previously-attached channel when its window closes.
  func detach(channel: FlutterMethodChannel) {
    channel.setMethodCallHandler(nil)
    stateQueue.sync {
      channels.removeAll { $0 === channel }
      if activeChannel === channel {
        activeChannel = channels.last
      }
    }
  }

  private func handle(_ call: FlutterMethodCall, from channel: FlutterMethodChannel?, result: @escaping FlutterResult) {
    switch call.method {
    case "setEnabled":
      let args = call.arguments as? [String: Any]
      let want = (args?["enabled"] as? Bool) ?? false
      let shouldClear: Bool = stateQueue.sync {
        if want {
          enabled = true
          if let channel { activeChannel = channel }
          return false
        }
        // Only the active engine may disable globally.
        if activeChannel === channel {
          enabled = false
          return true
        }
        return false
      }
      if shouldClear { clear() }
      result(nil)
    case "update":
      guard let args = call.arguments as? [String: Any] else {
        result(nil); return
      }
      apply(args, fromChannel: channel)
      result(nil)
    case "clear":
      let shouldClear: Bool = stateQueue.sync {
        return activeChannel === channel || activeChannel == nil
      }
      if shouldClear { clear() }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Applies an update to `info` and the now-playing center. The whole
  /// read-modify-write happens inside one `stateQueue.sync` so concurrent
  /// `update` calls from two engines can't overwrite each other.
  /// `loadRemoteArtworkAsync` is dispatched from inside the same lock to
  /// keep the request-id increment paired with the assignment.
  private func apply(_ args: [String: Any], fromChannel channel: FlutterMethodChannel?) {
    var pendingArtUri: String? = nil
    let result: (info: [String: Any], playing: Bool?)? = stateQueue.sync {
      guard enabled else { return nil }
      // Latest writer wins.
      if let channel { activeChannel = channel }

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
      var playingFlag: Bool? = nil
      if let rate = args["rate"] as? Double, rate > 0 {
        playbackRate = rate
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = rate
      }
      if let playing = args["playing"] as? Bool {
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? playbackRate : 0.0
        playingFlag = playing
      } else if args.keys.contains("rate"),
                let current = info[MPNowPlayingInfoPropertyPlaybackRate] as? Double,
                current > 0 {
        // Live rate update while already playing.
        info[MPNowPlayingInfoPropertyPlaybackRate] = playbackRate
      }
      if let artUri = args["artUri"] as? String, !artUri.isEmpty {
        if isLocalArtwork(artUri) {
          if let image = loadLocalArtwork(artUri) {
            info[MPMediaItemPropertyArtwork] = makeArtwork(image)
          } else {
            info.removeValue(forKey: MPMediaItemPropertyArtwork)
          }
        } else {
          // Remote URLs may stall on the main thread; fetch in the background.
          info.removeValue(forKey: MPMediaItemPropertyArtwork)
          pendingArtUri = artUri
        }
      } else if args.keys.contains("artUri") {
        info.removeValue(forKey: MPMediaItemPropertyArtwork)
      }
      return (info, playingFlag)
    }
    guard let result = result else { return }
    if let playing = result.playing {
      MPNowPlayingInfoCenter.default().playbackState =
        playing ? .playing : .paused
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = result.info
    if let uri = pendingArtUri {
      loadRemoteArtworkAsync(uri)
    }
  }

  private func makeArtwork(_ image: NSImage) -> MPMediaItemArtwork {
    let size = image.size
    return MPMediaItemArtwork(boundsSize: size) { requested in
      return resizedImage(image, to: requested) ?? image
    }
  }

  private func loadRemoteArtworkAsync(_ uri: String) {
    guard let url = URL(string: uri),
          let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https",
          isPublicRemoteArtworkHost(url.host) else { return }
    let token: UInt64 = stateQueue.sync {
      artworkRequestId = artworkRequestId &+ 1
      artworkTask?.cancel()
      return artworkRequestId
    }
    let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
      guard let self = self,
            let data = data,
            let image = NSImage(data: data) else { return }
      let artwork = self.makeArtwork(image)
      let snapshot: [String: Any]? = self.stateQueue.sync {
        // A newer update may have superseded this fetch.
        guard self.artworkRequestId == token else { return nil }
        self.info[MPMediaItemPropertyArtwork] = artwork
        return self.info
      }
      guard let nextInfo = snapshot else { return }
      DispatchQueue.main.async {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nextInfo
      }
    }
    stateQueue.sync { artworkTask = task }
    task.resume()
  }

  private func clear() {
    stateQueue.sync {
      info.removeAll()
      artworkTask?.cancel()
      artworkTask = nil
    }
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
    cc.changePlaybackRateCommand.isEnabled = true
    cc.changePlaybackRateCommand.supportedPlaybackRates = [
      0.5, 0.75, 1.0, 1.25, 1.5, 2.0,
    ]

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
    cc.changePlaybackRateCommand.addTarget { [weak self] event in
      guard let evt = event as? MPChangePlaybackRateCommandEvent else {
        return .commandFailed
      }
      self?.invokeCommand("rate", value: Double(evt.playbackRate))
      return .success
    }
  }

  private func invokeCommand(
    _ action: String,
    positionMs: Int? = nil,
    value: Double? = nil
  ) {
    var args: [String: Any] = ["action": action]
    if let pos = positionMs { args["positionMs"] = pos }
    if let value { args["value"] = value }
    let target: FlutterMethodChannel? = stateQueue.sync {
      activeChannel ?? channels.first
    }
    DispatchQueue.main.async {
      target?.invokeMethod("command", arguments: args)
    }
  }
}

private func isLocalArtwork(_ uri: String) -> Bool {
  let lower = uri.lowercased()
  return !(lower.hasPrefix("http://") || lower.hasPrefix("https://"))
}

/// Rejects loopback / private / link-local / .local hosts for remote artwork.
private func isPublicRemoteArtworkHost(_ rawHost: String?) -> Bool {
  guard let raw = rawHost?.trimmingCharacters(in: .whitespacesAndNewlines),
        !raw.isEmpty else { return false }
  let host = raw.lowercased()
  if host == "localhost" || host == "127.0.0.1" || host == "::1" {
    return false
  }
  if host.hasSuffix(".local") { return false }
  if host.hasPrefix("10.") { return false }
  if host.hasPrefix("192.168.") { return false }
  if host.hasPrefix("169.254.") { return false }
  // 172.16.0.0 - 172.31.255.255
  if host.hasPrefix("172.") {
    let parts = host.split(separator: ".")
    if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) {
      return false
    }
  }
  return true
}

private func loadLocalArtwork(_ uri: String) -> NSImage? {
  if uri.hasPrefix("file://") {
    if let url = URL(string: uri), let image = NSImage(contentsOf: url) {
      return image
    }
    // Fall back to manual percent-decoding for paths URL(string:) couldn't open.
    let path = String(uri.dropFirst("file://".count))
      .removingPercentEncoding ?? String(uri.dropFirst("file://".count))
    return NSImage(contentsOf: URL(fileURLWithPath: path))
  }
  return NSImage(contentsOf: URL(fileURLWithPath: uri))
}

private func resizedImage(_ source: NSImage, to size: CGSize) -> NSImage? {
  guard size.width > 0, size.height > 0 else { return source }
  let result = NSImage(size: size)
  result.lockFocus()
  source.draw(
    in: NSRect(origin: .zero, size: size),
    from: NSRect(origin: .zero, size: source.size),
    operation: .copy,
    fraction: 1.0)
  result.unlockFocus()
  return result
}

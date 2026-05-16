import Foundation
import FlutterMacOS
import os.log

private let bookmarkLog = OSLog(subsystem: "run.rosie.dacx", category: "bookmarks")

final class BookmarkBridge {
    static let channelName = "run.rosie.dacx/bookmarks"

    private let channel: FlutterMethodChannel
    private let queue = DispatchQueue(label: "run.rosie.dacx.bookmark-bridge")
    private var scopedURLs: [String: URL] = [:]

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: BookmarkBridge.channelName,
                                       binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call: call, result: result)
        }
    }

    deinit {
        channel.setMethodCallHandler(nil)
        let urls = queue.sync { Array(scopedURLs.values) }
        for url in urls {
            url.stopAccessingSecurityScopedResource()
        }
    }

    private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "create":
            createBookmark(arguments: call.arguments, result: result)
        case "resolveAndStart":
            resolveBookmark(arguments: call.arguments, result: result)
        case "stop":
            stopAccess(arguments: call.arguments, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func createBookmark(arguments: Any?, result: @escaping FlutterResult) {
        guard let args = arguments as? [String: Any],
              let path = args["path"] as? String, !path.isEmpty else {
            result(FlutterError(code: "INVALID_ARGS",
                                message: "create requires path",
                                details: nil))
            return
        }
        let url = URL(fileURLWithPath: path)
        do {
            let data = try url.bookmarkData(options: [.withSecurityScope],
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil)
            result(data.base64EncodedString())
        } catch {
            os_log("bookmark create failed for %{private}@: %{public}@",
                   log: bookmarkLog, type: .error, path, "\(error)")
            result(FlutterError(code: "BOOKMARK_FAILED",
                                message: "could not create bookmark: \(error.localizedDescription)",
                                details: nil))
        }
    }

    private func resolveBookmark(arguments: Any?, result: @escaping FlutterResult) {
        guard let args = arguments as? [String: Any],
              let encoded = args["bookmark"] as? String, !encoded.isEmpty,
              let data = Data(base64Encoded: encoded) else {
            result(FlutterError(code: "INVALID_ARGS",
                                message: "resolveAndStart requires bookmark",
                                details: nil))
            return
        }

        var isStale = false
        let resolved: URL
        do {
            resolved = try URL(resolvingBookmarkData: data,
                               options: [.withSecurityScope],
                               relativeTo: nil,
                               bookmarkDataIsStale: &isStale)
        } catch {
            os_log("bookmark resolve failed: %{public}@",
                   log: bookmarkLog, type: .error, "\(error)")
            result(FlutterError(code: "BOOKMARK_RESOLVE_FAILED",
                                message: error.localizedDescription,
                                details: nil))
            return
        }

        let started = resolved.startAccessingSecurityScopedResource()
        let token = UUID().uuidString
        if started {
            queue.sync { scopedURLs[token] = resolved }
        }

        var refreshed: String? = nil
        if isStale {
            if let newData = try? resolved.bookmarkData(options: [.withSecurityScope],
                                                       includingResourceValuesForKeys: nil,
                                                       relativeTo: nil) {
                refreshed = newData.base64EncodedString()
            }
        }

        result([
            "path": resolved.path,
            "token": started ? token : "",
            "stale": isStale,
            "refreshed": refreshed as Any,
        ])
    }

    private func stopAccess(arguments: Any?, result: @escaping FlutterResult) {
        guard let args = arguments as? [String: Any],
              let token = args["token"] as? String, !token.isEmpty else {
            result(nil)
            return
        }
        let url = queue.sync { () -> URL? in
            return scopedURLs.removeValue(forKey: token)
        }
        url?.stopAccessingSecurityScopedResource()
        result(nil)
    }
}

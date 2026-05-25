import Foundation
import FlutterMacOS
import os.log

private let bridgeLog = OSLog(subsystem: "run.rosie.dacx", category: "update-bridge")

/// Bridges the Dart `MethodChannel('run.rosie.dacx/update')` to the bundled
/// `run.rosie.dacx.UpdateHelper.xpc` service. The XPC service is un-sandboxed
/// and performs the actual `/Applications/Dacx.app` swap on behalf of the
/// sandboxed main app.
final class UpdateBridge {
    static let channelName = "run.rosie.dacx/update"
    static let xpcServiceName = "run.rosie.dacx.UpdateHelper"

    private let channel: FlutterMethodChannel

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: UpdateBridge.channelName,
                                       binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call: call, result: result)
        }
    }

    deinit {
        channel.setMethodCallHandler(nil)
    }

    private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "installUpdate":
            installUpdate(arguments: call.arguments, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func installUpdate(arguments: Any?, result: @escaping FlutterResult) {
        guard let args = arguments as? [String: Any],
              let newAppPath = args["newAppPath"] as? String, !newAppPath.isEmpty,
              let installedAppPath = args["installedAppPath"] as? String, !installedAppPath.isEmpty,
              let expectedTeamId = args["expectedTeamId"] as? String, !expectedTeamId.isEmpty,
              let expectedVersion = args["expectedVersion"] as? String, !expectedVersion.isEmpty
        else {
            result(FlutterError(code: "INVALID_ARGS",
                                message: "installUpdate requires newAppPath, installedAppPath, expectedTeamId, expectedVersion",
                                details: nil))
            return
        }
        let relaunch = (args["relaunch"] as? Bool) ?? true

        let connection = NSXPCConnection(serviceName: UpdateBridge.xpcServiceName)
        connection.remoteObjectInterface = NSXPCInterface(with: UpdateHelperProtocol.self)

        let didReply = DispatchQueue(label: "run.rosie.dacx.update-bridge.reply-guard")
        var replied = false
        func sendOnce(_ payload: [String: Any?]) {
            let shouldSend: Bool = didReply.sync {
                if replied { return false }
                replied = true
                return true
            }
            guard shouldSend else { return }
            DispatchQueue.main.async {
                result(payload)
                connection.invalidate()
            }
        }

        connection.interruptionHandler = {
            os_log("XPC connection interrupted", log: bridgeLog, type: .error)
            sendOnce(["accepted": false, "error": "XPC connection interrupted"])
        }
        connection.invalidationHandler = {
            os_log("XPC connection invalidated", log: bridgeLog, type: .info)
            sendOnce(["accepted": false, "error": "XPC connection invalidated"])
        }
        connection.resume()

        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            os_log("XPC proxy error: %{public}@", log: bridgeLog, type: .error, error.localizedDescription)
            sendOnce(["accepted": false, "error": "XPC proxy error: \(error.localizedDescription)"])
        } as? UpdateHelperProtocol

        guard let proxy = proxy else {
            sendOnce(["accepted": false, "error": "could not obtain UpdateHelper proxy"])
            return
        }

        // Backstop in case the XPC service never replies and the connection's
        // interruption / invalidation handlers never fire (launchd hiccups,
        // missing .xpc bundle taking too long to report, etc.). The handler
        // only spawns a worker — milliseconds in the happy path.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            sendOnce(["accepted": false, "error": "XPC update helper did not respond — check that the .xpc bundle is present inside the app"])
        }

        let parentPID = getpid()
        proxy.install(newAppPath: newAppPath,
                      installedAppPath: installedAppPath,
                      expectedTeamId: expectedTeamId,
                      expectedVersion: expectedVersion,
                      parentPID: parentPID,
                      relaunch: relaunch) { accepted, error in
            os_log("XPC install replied accepted=%{public}@ error=%{public}@",
                   log: bridgeLog, type: .info,
                   accepted ? "true" : "false", error ?? "")
            sendOnce(["accepted": accepted, "error": error as Any?])
        }
    }
}

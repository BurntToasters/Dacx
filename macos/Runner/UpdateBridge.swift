import Foundation
import FlutterMacOS
import os.log

private let bridgeLog = OSLog(subsystem: "run.rosie.dacx", category: "update-bridge")

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
        case "installUpdateFromUrl":
            installUpdateFromUrl(arguments: call.arguments, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func makeConnection(result: @escaping FlutterResult,
                                timeoutSeconds: Double) -> (NSXPCConnection, (([String: Any?]) -> Void)) {
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

        // Backstop: fires if XPC service never replies. Timeout must be generous
        // because the helper now downloads the zip (~100 MB) before replying.
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds) {
            sendOnce(["accepted": false, "error": "XPC update helper timed out after \(Int(timeoutSeconds))s; check that the .xpc bundle is present inside the app"])
        }

        return (connection, sendOnce)
    }

    private func installUpdateFromUrl(arguments: Any?, result: @escaping FlutterResult) {
        guard let args = arguments as? [String: Any],
              let zipUrl = args["zipUrl"] as? String, !zipUrl.isEmpty,
              let checksumHex = args["checksumHex"] as? String, !checksumHex.isEmpty,
              let installedAppPath = args["installedAppPath"] as? String, !installedAppPath.isEmpty,
              let expectedTeamId = args["expectedTeamId"] as? String, !expectedTeamId.isEmpty,
              let expectedVersion = args["expectedVersion"] as? String, !expectedVersion.isEmpty
        else {
            result(FlutterError(code: "INVALID_ARGS",
                                message: "installUpdateFromUrl requires zipUrl, checksumHex, installedAppPath, expectedTeamId, expectedVersion",
                                details: nil))
            return
        }
        let relaunch = (args["relaunch"] as? Bool) ?? true

        // Timeout: 15 minutes. The helper downloads the zip (can be 100+ MB on a
        // slow connection) before replying, so the old 30-second backstop was wrong.
        let (connection, sendOnce) = makeConnection(result: result, timeoutSeconds: 900)

        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            os_log("XPC proxy error: %{public}@", log: bridgeLog, type: .error, error.localizedDescription)
            sendOnce(["accepted": false, "error": "XPC proxy error: \(error.localizedDescription)"])
        } as? UpdateHelperProtocol

        guard let proxy = proxy else {
            sendOnce(["accepted": false, "error": "could not obtain UpdateHelper proxy"])
            return
        }

        let parentPID = getpid()
        proxy.installFromUrl(zipUrl: zipUrl,
                             checksumHex: checksumHex,
                             installedAppPath: installedAppPath,
                             expectedTeamId: expectedTeamId,
                             expectedVersion: expectedVersion,
                             parentPID: parentPID,
                             relaunch: relaunch) { accepted, error in
            os_log("XPC installFromUrl replied accepted=%{public}@ error=%{public}@",
                   log: bridgeLog, type: .info,
                   accepted ? "true" : "false", error ?? "")
            sendOnce(["accepted": accepted, "error": error as Any?])
        }
    }
}

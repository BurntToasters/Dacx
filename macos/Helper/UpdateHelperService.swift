import Foundation

@main
enum UpdateHelperService {
    static func main() {
        let env = ProcessInfo.processInfo.environment

        // Re-execed via osascript with admin privileges: do the swap as root,
        // then exit. The user-side worker is waiting on this child's exit.
        if env["DACX_UPDATE_ROOT"] == "1" {
            exit(runRootInstall())
        }

        // Detached worker spawned by the XPC service. Waits for the connecting
        // app to exit, then performs (or escalates and performs) the swap and
        // optional relaunch.
        if env["DACX_UPDATE_WORKER"] == "1" {
            exit(runWorkerInstall())
        }

        // Default: vend the XPC service.
        let delegate = UpdateHelperServiceDelegate()
        let listener = NSXPCListener.service()
        listener.delegate = delegate
        listener.resume()
        dispatchMain()
    }
}

final class UpdateHelperServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        let iface = NSXPCInterface(with: UpdateHelperProtocol.self)
        newConnection.exportedInterface = iface
        newConnection.exportedObject = UpdateHelperImpl()
        newConnection.resume()
        return true
    }
}

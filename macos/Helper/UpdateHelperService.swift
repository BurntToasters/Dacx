import Foundation
import Security
import os.log

private let serviceLog = OSLog(subsystem: "run.rosie.dacx", category: "update-helper-service")

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
        guard let requirement = buildCallerRequirement() else {
            os_log("XPC listener REFUSING to start: could not resolve own Team ID. Exiting.",
                   log: serviceLog, type: .fault)
            exit(1)
        }
        os_log("XPC listener starting; caller requirement: %{public}@",
               log: serviceLog, type: .info, requirement)

        let delegate = UpdateHelperServiceDelegate(codeRequirement: requirement)
        let listener = NSXPCListener.service()
        listener.delegate = delegate
        listener.resume()
        dispatchMain()
    }
}

// Construct the SecRequirement string used to gate XPC connections. We bind
// the caller's bundle identifier *and* anchor to Apple's certificate chain,
// and (when our own team id is resolvable) restrict to that team's OU. The
// team is read from our running code so it stays in sync with whatever cert
// the parent .app was signed by — no build-time bake-in required.
private func buildCallerRequirement() -> String? {
    let team = ownTeamIdentifier() ?? ""
    if team.isEmpty {
        return nil
    }
    return "identifier \"\(kDacxBundleIdentifier)\" and anchor apple generic " +
           "and certificate leaf[subject.OU] = \"\(team)\""
}

private func ownTeamIdentifier() -> String? {
    var dyn: SecCode?
    guard SecCodeCopySelf([], &dyn) == errSecSuccess, let dyn = dyn else { return nil }
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(dyn, [], &staticCode) == errSecSuccess,
          let staticCode = staticCode else { return nil }
    var infoCF: CFDictionary?
    let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
    guard SecCodeCopySigningInformation(staticCode, flags, &infoCF) == errSecSuccess,
          let info = infoCF as? [String: Any] else { return nil }
    return info[kSecCodeInfoTeamIdentifier as String] as? String
}

final class UpdateHelperServiceDelegate: NSObject, NSXPCListenerDelegate {
    private let codeRequirement: String

    init(codeRequirement: String) {
        self.codeRequirement = codeRequirement
        super.init()
    }

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        let callerPID = newConnection.processIdentifier
        if callerPID <= 0 {
            os_log("rejecting XPC connection: invalid caller pid",
                   log: serviceLog, type: .error)
            return false
        }

        // macOS 13+ enforces this kernel-side via the connection's audit
        // token — no PID race. Our deployment floor is macOS 15, so this
        // path is always available.
        newConnection.setCodeSigningRequirement(codeRequirement)

        let iface = NSXPCInterface(with: UpdateHelperProtocol.self)
        newConnection.exportedInterface = iface
        newConnection.exportedObject = UpdateHelperImpl(verifiedCallerPID: callerPID)
        newConnection.resume()
        return true
    }
}

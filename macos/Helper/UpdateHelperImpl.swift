import Foundation
import Darwin
import os.log

let kDacxBundleIdentifier = "run.rosie.dacx"

private let helperLog = OSLog(subsystem: "run.rosie.dacx", category: "update-helper")

func dacxLog(_ s: String) {
    // Detached workers close stdio to /dev/null, so route through unified
    // logging — events show up in Console.app and `log show`.
    os_log("%{public}@", log: helperLog, type: .info, s)
}

// MARK: - Validation primitives (ported from DacxUpdateHelper.swift)

@discardableResult
func runCommand(_ executable: String, _ args: [String]) -> (Int32, String) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: executable)
    task.arguments = args
    let outPipe = Pipe()
    let errPipe = Pipe()
    task.standardOutput = outPipe
    task.standardError = errPipe
    do {
        try task.run()
        task.waitUntilExit()
    } catch {
        return (-1, "spawn failed: \(error)")
    }
    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
    let combined = (String(data: outData, encoding: .utf8) ?? "")
        + (String(data: errData, encoding: .utf8) ?? "")
    return (task.terminationStatus, combined)
}

func codesignDetails(of appPath: String) -> [String: String]? {
    let (code, output) = runCommand("/usr/bin/codesign", ["-dv", "--verbose=4", appPath])
    if code != 0 { return nil }
    var result: [String: String] = [:]
    for line in output.split(separator: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if let idx = trimmed.firstIndex(of: "="), idx != trimmed.startIndex {
            let key = String(trimmed[..<idx])
            let value = String(trimmed[trimmed.index(after: idx)...])
            if !value.isEmpty {
                result[key] = value
            }
        }
    }
    return result
}

struct DacxBundleVersion {
    let value: String
    let source: String
}

func releaseVersion(of appPath: String) -> DacxBundleVersion? {
    let infoPath = appPath + "/Contents/Info.plist"
    guard let plist = NSDictionary(contentsOfFile: infoPath) else { return nil }
    if let version = plist["DacxReleaseVersion"] as? String, !version.isEmpty {
        return DacxBundleVersion(value: version, source: "DacxReleaseVersion")
    }
    if let version = plist["CFBundleShortVersionString"] as? String, !version.isEmpty {
        return DacxBundleVersion(value: version, source: "CFBundleShortVersionString")
    }
    return nil
}

enum ValidationFailure: Error, CustomStringConvertible {
    case codesign(String)
    case bundleIdentifierMismatch(String)
    case teamMismatch(String)
    case versionMismatch(String)
    case spctl(String)

    var description: String {
        switch self {
        case .codesign(let m): return "codesign: \(m)"
        case .bundleIdentifierMismatch(let m): return "bundle id mismatch: \(m)"
        case .teamMismatch(let m): return "team id mismatch: \(m)"
        case .versionMismatch(let m): return "version mismatch: \(m)"
        case .spctl(let m): return "spctl: \(m)"
        }
    }
}

func validateBundle(_ appPath: String, expectedTeamId: String, expectedVersion: String) -> ValidationFailure? {
    let verify = runCommand("/usr/bin/codesign", [
        "--verify", "--deep", "--strict", "--verbose=2", appPath,
    ])
    if verify.0 != 0 {
        return .codesign(verify.1)
    }
    guard let details = codesignDetails(of: appPath) else {
        return .codesign("could not read codesign details")
    }
    let actualIdentifier = details["Identifier"] ?? ""
    if actualIdentifier != kDacxBundleIdentifier {
        return .bundleIdentifierMismatch("expected \(kDacxBundleIdentifier), got \(actualIdentifier)")
    }
    guard let actual = details["TeamIdentifier"] else {
        return .teamMismatch("could not read team id")
    }
    if actual != expectedTeamId {
        return .teamMismatch("expected \(expectedTeamId), got \(actual)")
    }
    guard let actualVersion = releaseVersion(of: appPath) else {
        return .versionMismatch("could not read DacxReleaseVersion")
    }
    if expectedVersion.contains("-") && actualVersion.source != "DacxReleaseVersion" {
        return .versionMismatch("prerelease bundle is missing DacxReleaseVersion")
    }
    if actualVersion.value != expectedVersion {
        return .versionMismatch("expected \(expectedVersion), got \(actualVersion.value)")
    }
    let spctl = runCommand("/usr/sbin/spctl", [
        "--assess", "--type", "execute", "--verbose=2", appPath,
    ])
    if spctl.0 != 0 {
        return .spctl(spctl.1)
    }
    return nil
}

func validateInstalledBundle(_ appPath: String, expectedTeamId: String) -> ValidationFailure? {
    let verify = runCommand("/usr/bin/codesign", [
        "--verify", "--deep", "--strict", "--verbose=2", appPath,
    ])
    if verify.0 != 0 {
        return .codesign(verify.1)
    }
    guard let details = codesignDetails(of: appPath) else {
        return .codesign("could not read codesign details")
    }
    let actualIdentifier = details["Identifier"] ?? ""
    if actualIdentifier != kDacxBundleIdentifier {
        return .bundleIdentifierMismatch("expected \(kDacxBundleIdentifier), got \(actualIdentifier)")
    }
    guard let actual = details["TeamIdentifier"] else {
        return .teamMismatch("could not read team id")
    }
    if actual != expectedTeamId {
        return .teamMismatch("expected \(expectedTeamId), got \(actual)")
    }
    return nil
}

func bundleExists(_ path: String) -> Bool {
    var isDir: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
}

// MARK: - kqueue parent-exit wait

/// Blocks until the supplied PID exits or `timeoutSeconds` elapses. Returns
/// `true` if the process has exited (either kevent reported NOTE_EXIT or the
/// PID was already gone at registration), `false` if we timed out / errored
/// out with the parent still alive — callers MUST treat `false` as "do not
/// proceed with the swap; the parent is still running."
func waitForPidExit(_ pid: pid_t, timeoutSeconds: Int = 120) -> Bool {
    let kq = kqueue()
    if kq == -1 {
        dacxLog("kqueue() failed (errno=\(errno))")
        return false
    }
    defer { close(kq) }

    var event = kevent()
    event.ident = UInt(pid)
    event.filter = Int16(EVFILT_PROC)
    event.flags = UInt16(EV_ADD | EV_ENABLE | EV_ONESHOT)
    event.fflags = UInt32(NOTE_EXIT)
    event.data = 0
    event.udata = nil

    let regResult = withUnsafePointer(to: &event) { ptr in
        kevent(kq, ptr, 1, nil, 0, nil)
    }
    if regResult == -1 {
        // EV_ADD on an unknown PID returns ESRCH — the parent is already gone,
        // which is exactly what we were waiting for.
        if errno == ESRCH {
            dacxLog("parent pid \(pid) already gone")
            return true
        }
        dacxLog("kevent register failed (errno=\(errno))")
        return false
    }

    var triggered = kevent()
    var timeout = timespec(tv_sec: timeoutSeconds, tv_nsec: 0)
    let waitResult = withUnsafeMutablePointer(to: &triggered) { tPtr in
        kevent(kq, nil, 0, tPtr, 1, &timeout)
    }
    if waitResult > 0 {
        return true
    }
    if waitResult == 0 {
        // Final probe before declaring timeout — the parent may have exited
        // between registration and now without firing the event for some
        // reason (signal interruption, etc.).
        if kill(pid, 0) != 0 && errno == ESRCH {
            return true
        }
        dacxLog("timed out waiting for parent pid \(pid)")
        return false
    }
    dacxLog("kevent wait failed (errno=\(errno))")
    return false
}

// MARK: - Swap

enum SwapStatus {
    case ok
    case failed(String)
}

func performSwap(newAppPath: String,
                 installedAppPath: String,
                 expectedTeamId: String,
                 expectedVersion: String) -> SwapStatus {
    let fm = FileManager.default

    guard bundleExists(installedAppPath) else {
        return .failed("install-path \(installedAppPath) is missing")
    }
    if let failure = validateInstalledBundle(installedAppPath, expectedTeamId: expectedTeamId) {
        return .failed("installed app validation failed: \(failure)")
    }
    guard bundleExists(newAppPath) else {
        return .failed("new-app \(newAppPath) is missing")
    }
    if let failure = validateBundle(newAppPath, expectedTeamId: expectedTeamId, expectedVersion: expectedVersion) {
        return .failed("pre-move validation failed: \(failure)")
    }

    let backupPath = installedAppPath + ".bak"
    if fm.fileExists(atPath: backupPath) {
        try? fm.removeItem(atPath: backupPath)
    }
    do {
        try fm.moveItem(atPath: installedAppPath, toPath: backupPath)
    } catch {
        return .failed("rename to .bak failed: \(error)")
    }

    func restoreBackup() {
        try? fm.removeItem(atPath: installedAppPath)
        do {
            try fm.moveItem(atPath: backupPath, toPath: installedAppPath)
        } catch {
            dacxLog("rollback failed: \(error)")
        }
    }

    do {
        try fm.moveItem(atPath: newAppPath, toPath: installedAppPath)
    } catch {
        restoreBackup()
        return .failed("move new app to install-path failed: \(error)")
    }

    if let failure = validateBundle(installedAppPath, expectedTeamId: expectedTeamId, expectedVersion: expectedVersion) {
        restoreBackup()
        return .failed("post-move validation failed: \(failure)")
    }

    try? fm.removeItem(atPath: backupPath)
    return .ok
}

// MARK: - Worker / root re-exec plumbing

struct WorkerArgs {
    let newAppPath: String
    let installedAppPath: String
    let expectedTeamId: String
    let expectedVersion: String
    let parentPID: pid_t
    let relaunch: Bool
}

func readWorkerArgsFromEnv() -> WorkerArgs? {
    let env = ProcessInfo.processInfo.environment
    guard
        let newApp = env["DACX_NEW_APP"], !newApp.isEmpty,
        let installed = env["DACX_INSTALLED_APP"], !installed.isEmpty,
        let team = env["DACX_TEAM_ID"], !team.isEmpty,
        let version = env["DACX_VERSION"], !version.isEmpty,
        let pidStr = env["DACX_PARENT_PID"], let pidVal = pid_t(pidStr)
    else { return nil }
    let relaunch = (env["DACX_RELAUNCH"] ?? "0") == "1"
    return WorkerArgs(newAppPath: newApp,
                      installedAppPath: installed,
                      expectedTeamId: team,
                      expectedVersion: version,
                      parentPID: pidVal,
                      relaunch: relaunch)
}

func shellQuoteSingle(_ s: String) -> String {
    return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

func appleScriptQuote(_ s: String) -> String {
    return "\"" + s
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"") + "\""
}

/// Re-exec self via osascript admin-prompt, passing the same args via env and
/// `DACX_UPDATE_ROOT=1` so the root copy goes straight to the swap path.
func runRootInstallViaOSAScript(selfPath: String, args: WorkerArgs) -> Int32 {
    let envParts: [String] = [
        "DACX_UPDATE_ROOT=1",
        "DACX_NEW_APP=\(shellQuoteSingle(args.newAppPath))",
        "DACX_INSTALLED_APP=\(shellQuoteSingle(args.installedAppPath))",
        "DACX_TEAM_ID=\(shellQuoteSingle(args.expectedTeamId))",
        "DACX_VERSION=\(shellQuoteSingle(args.expectedVersion))",
        "DACX_PARENT_PID=\(args.parentPID)",
        "DACX_RELAUNCH=0",
    ]
    let shellCmd = envParts.joined(separator: " ") + " " + shellQuoteSingle(selfPath)
    let script = "do shell script \(appleScriptQuote(shellCmd)) with administrator privileges"
    let (code, output) = runCommand("/usr/bin/osascript", ["-e", script])
    if code != 0 {
        dacxLog("osascript root re-exec failed (\(code)): \(output)")
    }
    return code
}

// MARK: - Worker entry points

/// Runs the install flow as the original user (post-parent-exit). May escalate
/// to a root osascript re-exec when the destination isn't writable.
func runWorkerInstall() -> Int32 {
    guard let args = readWorkerArgsFromEnv() else {
        dacxLog("worker: missing required env vars")
        return 2
    }

    dacxLog("worker: waiting for parent pid \(args.parentPID) to exit")
    let parentExited = waitForPidExit(args.parentPID)
    if !parentExited {
        dacxLog("worker: parent did not exit; aborting before swap")
        return 4
    }
    dacxLog("worker: parent exited, beginning install")

    let needsRoot: Bool = {
        if getuid() == 0 { return false }
        return access(args.installedAppPath, W_OK) != 0
    }()

    if needsRoot {
        let selfPath = Bundle.main.executablePath
            ?? CommandLine.arguments.first
            ?? "/usr/bin/false"
        dacxLog("worker: install path not writable, escalating via osascript")
        let code = runRootInstallViaOSAScript(selfPath: selfPath, args: args)
        if code != 0 {
            return 7
        }
    } else {
        let status = performSwap(newAppPath: args.newAppPath,
                                 installedAppPath: args.installedAppPath,
                                 expectedTeamId: args.expectedTeamId,
                                 expectedVersion: args.expectedVersion)
        switch status {
        case .ok:
            break
        case .failed(let message):
            dacxLog("worker: swap failed: \(message)")
            return 6
        }
    }

    if args.relaunch {
        let openResult = runCommand("/usr/bin/open", [args.installedAppPath])
        if openResult.0 != 0 {
            dacxLog("worker: relaunch failed (\(openResult.0)): \(openResult.1)")
        }
    }

    return 0
}

/// Runs the install flow as root (re-exec'd via osascript). Skips the parent
/// wait and the relaunch — the user-side worker handles those.
func runRootInstall() -> Int32 {
    guard let args = readWorkerArgsFromEnv() else {
        dacxLog("root: missing required env vars")
        return 2
    }
    dacxLog("root: running install as uid \(getuid())")
    let status = performSwap(newAppPath: args.newAppPath,
                             installedAppPath: args.installedAppPath,
                             expectedTeamId: args.expectedTeamId,
                             expectedVersion: args.expectedVersion)
    switch status {
    case .ok:
        return 0
    case .failed(let message):
        dacxLog("root: swap failed: \(message)")
        return 6
    }
}

// MARK: - XPC service implementation

@objc final class UpdateHelperImpl: NSObject, UpdateHelperProtocol {
    func install(newAppPath: String,
                 installedAppPath: String,
                 expectedTeamId: String,
                 expectedVersion: String,
                 parentPID: Int32,
                 relaunch: Bool,
                 reply: @escaping (Bool, String?) -> Void) {

        if newAppPath.isEmpty || installedAppPath.isEmpty
            || expectedTeamId.isEmpty || expectedVersion.isEmpty
            || parentPID <= 0 {
            reply(false, "missing required arguments")
            return
        }
        if !bundleExists(newAppPath) {
            reply(false, "new app bundle not found at \(newAppPath)")
            return
        }

        guard let selfPath = Bundle.main.executablePath else {
            reply(false, "could not resolve XPC executable path")
            return
        }

        let env: [String: String] = [
            "DACX_UPDATE_WORKER": "1",
            "DACX_NEW_APP": newAppPath,
            "DACX_INSTALLED_APP": installedAppPath,
            "DACX_TEAM_ID": expectedTeamId,
            "DACX_VERSION": expectedVersion,
            "DACX_PARENT_PID": String(parentPID),
            "DACX_RELAUNCH": relaunch ? "1" : "0",
        ]

        let spawnResult = spawnDetachedWorker(executablePath: selfPath, env: env)
        if let err = spawnResult {
            reply(false, "posix_spawn failed: \(err)")
            return
        }
        reply(true, nil)
    }
}

/// Spawns the worker via `posix_spawn` with a new session, env-vars, and
/// std-fds redirected to /dev/null so it survives the XPC service being reaped
/// once the connecting app quits.
func spawnDetachedWorker(executablePath: String, env: [String: String]) -> String? {
    var fileActions: posix_spawn_file_actions_t? = nil
    posix_spawn_file_actions_init(&fileActions)
    defer { posix_spawn_file_actions_destroy(&fileActions) }

    let devNull = "/dev/null"
    posix_spawn_file_actions_addopen(&fileActions, 0, devNull, O_RDONLY, 0)
    posix_spawn_file_actions_addopen(&fileActions, 1, devNull, O_WRONLY, 0)
    posix_spawn_file_actions_addopen(&fileActions, 2, devNull, O_WRONLY, 0)

    var attrs: posix_spawnattr_t? = nil
    posix_spawnattr_init(&attrs)
    defer { posix_spawnattr_destroy(&attrs) }
    // SETSID: new session, detaches from any controlling terminal so the
    //   worker survives parent reap.
    // CLOEXEC_DEFAULT (Darwin-only, 0x4000): close every inherited fd EXCEPT
    //   the ones explicitly listed in file_actions (we open 0/1/2 to
    //   /dev/null below). Stops the worker from holding on to the XPC
    //   service's listener / connection fds after we detach.
    let flags = Int16(POSIX_SPAWN_SETSID) | Int16(0x4000)
    posix_spawnattr_setflags(&attrs, flags)

    // Build argv. Single arg: argv[0] = executable path.
    let argv: [UnsafeMutablePointer<CChar>?] = [
        strdup(executablePath),
        nil,
    ]
    defer { for ptr in argv { if ptr != nil { free(ptr) } } }

    // Build envp from the supplied env (worker process inherits nothing else).
    let envpStrings: [String] = env.map { "\($0.key)=\($0.value)" }
    let envp: [UnsafeMutablePointer<CChar>?] = envpStrings.map { strdup($0) } + [nil]
    defer { for ptr in envp { if ptr != nil { free(ptr) } } }

    var pid: pid_t = 0
    let rc = posix_spawn(&pid, executablePath, &fileActions, &attrs, argv, envp)
    if rc != 0 {
        return "rc=\(rc) (\(String(cString: strerror(rc))))"
    }
    return nil
}

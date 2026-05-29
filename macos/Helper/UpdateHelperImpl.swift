import Foundation
import Darwin
import CryptoKit
import os.log

let kDacxBundleIdentifier = "run.rosie.dacx"

private let helperLog = OSLog(subsystem: "run.rosie.dacx", category: "update-helper")

func dacxLog(_ s: String) {
    os_log("%{public}@", log: helperLog, type: .info, s)
}

// MARK: - Shell helpers

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
        let group = DispatchGroup()
        var outData = Data()
        var errData = Data()

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        task.waitUntilExit()
        group.wait()
        let combined = (String(data: outData, encoding: .utf8) ?? "")
            + (String(data: errData, encoding: .utf8) ?? "")
        return (task.terminationStatus, combined)
    } catch {
        return (-1, "spawn failed: \(error)")
    }
}

// MARK: - Codesign helpers

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

// MARK: - Validation

enum ValidationFailure: Error, CustomStringConvertible {
    case codesign(String)
    case gatekeeper(String)
    case bundleIdentifierMismatch(String)
    case teamMismatch(String)
    case versionMismatch(String)

    var description: String {
        switch self {
        case .codesign(let m): return "codesign: \(m)"
        case .gatekeeper(let m): return "gatekeeper: \(m)"
        case .bundleIdentifierMismatch(let m): return "bundle id mismatch: \(m)"
        case .teamMismatch(let m): return "team id mismatch: \(m)"
        case .versionMismatch(let m): return "version mismatch: \(m)"
        }
    }
}

func gatekeeperAssessment(of appPath: String) -> ValidationFailure? {
    if FileManager.default.isExecutableFile(atPath: "/usr/bin/syspolicy_check") {
        let assess = runCommand("/usr/bin/syspolicy_check", [
            "distribution", appPath, "--verbose",
        ])
        if assess.0 != 0 {
            return .gatekeeper(assess.1)
        }
        return nil
    }

    let assess = runCommand("/usr/sbin/spctl", [
        "--assess", "--type", "execute", "--verbose=2", appPath,
    ])
    if assess.0 != 0 {
        return .gatekeeper(assess.1)
    }
    return nil
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
    return gatekeeperAssessment(of: appPath)
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

// MARK: - Install lock / cleanup

private let updateInstallLockPath = NSTemporaryDirectory() + "run.rosie.dacx.update.lock"

// Do not unlink the lockfile on release. flock() locks the open inode, so
// deleting the path can let a third process create and lock a different inode
// while another updater still holds the original lock.
struct UpdateInstallLock {
    let fd: Int32

    func closeForInheritedWorker() {
        close(fd)
    }

    func release() {
        flock(fd, LOCK_UN)
        close(fd)
    }
}

struct UpdateInstallLockFailure: Error, CustomStringConvertible {
    let description: String
}

func acquireUpdateInstallLock() -> Result<UpdateInstallLock, UpdateInstallLockFailure> {
    let fd = open(updateInstallLockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    if fd == -1 {
        return .failure(UpdateInstallLockFailure(description: "could not open update lock: \(String(cString: strerror(errno)))"))
    }
    if flock(fd, LOCK_EX | LOCK_NB) != 0 {
        let message = errno == EWOULDBLOCK
            ? "another update is already being prepared"
            : "could not acquire update lock: \(String(cString: strerror(errno)))"
        close(fd)
        return .failure(UpdateInstallLockFailure(description: message))
    }

    ftruncate(fd, 0)
    let metadata = "pid=\(getpid()) started=\(Date().timeIntervalSince1970)\n"
    metadata.withCString { ptr in
        _ = write(fd, ptr, strlen(ptr))
    }
    return .success(UpdateInstallLock(fd: fd))
}

func releaseInheritedUpdateLock(fd: Int32?) {
    guard let fd = fd, fd >= 0 else { return }
    flock(fd, LOCK_UN)
    close(fd)
}

func cleanupPath(_ path: String?) {
    guard let path = path, !path.isEmpty else { return }
    do {
        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
        }
    } catch {
        dacxLog("cleanup failed for \(path): \(error)")
    }
}

// MARK: - Download

/// Downloads [url] synchronously to a stable temp path.
struct DownloadFailure: Error, CustomStringConvertible {
    let description: String
}

func downloadToTemp(_ url: URL) -> Result<URL, DownloadFailure> {
    let destDir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("dacx-update-\(UUID().uuidString)", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
    } catch {
        return .failure(DownloadFailure(description: "could not create temp dir: \(error)"))
    }
    let destFile = destDir.appendingPathComponent(url.lastPathComponent)

    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<URL, DownloadFailure> = .failure(DownloadFailure(description: "download did not complete"))

    var request = URLRequest(url: url)
    request.timeoutInterval = 600
    let task = URLSession.shared.downloadTask(with: request) { tmpUrl, response, error in
        defer { semaphore.signal() }
        if let error = error {
            result = .failure(DownloadFailure(description: "download error: \(error.localizedDescription)"))
            return
        }
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            result = .failure(DownloadFailure(description: "HTTP \(code) from \(url)"))
            return
        }
        guard let tmpUrl = tmpUrl else {
            result = .failure(DownloadFailure(description: "no temp file from URLSession"))
            return
        }
        do {
            if FileManager.default.fileExists(atPath: destFile.path) {
                try FileManager.default.removeItem(at: destFile)
            }
            try FileManager.default.moveItem(at: tmpUrl, to: destFile)
            result = .success(destFile)
        } catch {
            result = .failure(DownloadFailure(description: "could not move download to stable path: \(error)"))
        }
    }
    task.resume()
    semaphore.wait()
    return result
}

// MARK: - SHA256

/// Streams [fileUrl] through CryptoKit SHA256 and returns the lowercase hex digest.
func sha256Hex(of fileUrl: URL) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: fileUrl) else { return nil }
    defer { try? handle.close() }
    var hasher = SHA256()
    while true {
        let chunk = handle.readData(ofLength: 65536)
        if chunk.isEmpty { break }
        hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02hhx", $0) }.joined()
}

// MARK: - Quarantine / provenance cleanup

/// Recursively removes `com.apple.quarantine` and `com.apple.provenance`
/// from [path]. Since the helper is un-sandboxed, files it extracts do NOT
/// receive these xattrs — this is a belt-and-suspenders strip for any residual
/// xattrs picked up during intermediate steps.
func stripSandboxOriginXattrs(_ path: String) {
    for attr in ["com.apple.quarantine", "com.apple.provenance"] {
        let (code, output) = runCommand("/usr/bin/xattr", ["-dr", attr, path])
        if code != 0 {
            dacxLog("xattr -dr \(attr) \(path) exit=\(code): \(output)")
        }
    }
}

// MARK: - kqueue parent-exit wait

func waitForPidExit(_ pid: pid_t, timeoutSeconds: Int = 45) -> Bool {
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
    if waitResult > 0 { return true }
    if waitResult == 0 {
        if kill(pid, 0) != 0 && errno == ESRCH { return true }
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

    dacxLog("performSwap begin: new=\(newAppPath) installed=\(installedAppPath) team=\(expectedTeamId) version=\(expectedVersion)")

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
    dacxLog("pre-move validation passed; proceeding with swap")

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

    // Strip any residual sandbox-origin xattrs. Files downloaded + extracted
    // by the un-sandboxed helper should already be clean, but strip anyway.
    stripSandboxOriginXattrs(installedAppPath)

    if let failure = validateBundle(installedAppPath, expectedTeamId: expectedTeamId, expectedVersion: expectedVersion) {
        dacxLog("post-move validation failed: \(failure); rolling back")
        restoreBackup()
        return .failed("post-move validation failed: \(failure)")
    }

    try? fm.removeItem(atPath: backupPath)
    dacxLog("swap complete; new bundle installed at \(installedAppPath)")
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
    let cleanupDir: String?
    let updateLockFD: Int32?
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
    let lockFD = env["DACX_UPDATE_LOCK_FD"].flatMap { Int32($0) }
    return WorkerArgs(newAppPath: newApp,
                      installedAppPath: installed,
                      expectedTeamId: team,
                      expectedVersion: version,
                      parentPID: pidVal,
                      relaunch: relaunch,
                      cleanupDir: env["DACX_CLEANUP_DIR"],
                      updateLockFD: lockFD)
}

func shellQuoteSingle(_ s: String) -> String {
    return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

func appleScriptQuote(_ s: String) -> String {
    return "\"" + s
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"") + "\""
}

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

func runWorkerInstall() -> Int32 {
    guard let args = readWorkerArgsFromEnv() else {
        dacxLog("worker: missing required env vars")
        return 2
    }
    defer {
        cleanupPath(args.cleanupDir)
        releaseInheritedUpdateLock(fd: args.updateLockFD)
    }

    dacxLog("worker: waiting for parent pid \(args.parentPID) to exit")
    let parentExited = waitForPidExit(args.parentPID)
    if !parentExited {
        dacxLog("worker: parent did not exit; aborting before swap")
        return 4
    }
    dacxLog("worker: parent exited, beginning install")

    let needsRoot = installNeedsRoot(installedAppPath: args.installedAppPath)

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
        // Detached worker has no WindowServer session; `launchctl asuser` re-enters
        // the user's GUI bootstrap so `open` can resolve the bundle (-10810 fix).
        let uid = getuid()
        let openResult = runCommand("/bin/launchctl", [
            "asuser", String(uid),
            "/usr/bin/open", args.installedAppPath,
        ])
        if openResult.0 != 0 {
            dacxLog("worker: launchctl-asuser relaunch failed (\(openResult.0)): \(openResult.1); trying direct open")
            let fallback = runCommand("/usr/bin/open", [args.installedAppPath])
            if fallback.0 != 0 {
                dacxLog("worker: direct-open relaunch also failed (\(fallback.0)): \(fallback.1)")
            }
        }
    }

    return 0
}

func installNeedsRoot(installedAppPath: String) -> Bool {
    if getuid() == 0 { return false }

    let installDir = URL(fileURLWithPath: installedAppPath)
        .deletingLastPathComponent()
        .path
    if access(installDir, W_OK) != 0 {
        dacxLog("worker: install directory \(installDir) is not writable without elevation")
        return true
    }

    let backupPath = installedAppPath + ".bak"
    if FileManager.default.fileExists(atPath: backupPath),
       access(backupPath, W_OK) != 0 {
        dacxLog("worker: existing backup \(backupPath) is not writable without elevation")
        return true
    }

    return false
}

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

// MARK: - Spawn detached worker

func spawnDetachedWorker(executablePath: String, env: [String: String], inheritedFD: Int32? = nil) -> String? {
    var fileActions: posix_spawn_file_actions_t? = nil
    posix_spawn_file_actions_init(&fileActions)
    defer { posix_spawn_file_actions_destroy(&fileActions) }

    let devNull = "/dev/null"
    posix_spawn_file_actions_addopen(&fileActions, 0, devNull, O_RDONLY, 0)
    posix_spawn_file_actions_addopen(&fileActions, 1, devNull, O_WRONLY, 0)
    posix_spawn_file_actions_addopen(&fileActions, 2, devNull, O_WRONLY, 0)
    if let inheritedFD = inheritedFD, inheritedFD >= 0 {
        posix_spawn_file_actions_addinherit_np(&fileActions, inheritedFD)
    }

    var attrs: posix_spawnattr_t? = nil
    posix_spawnattr_init(&attrs)
    defer { posix_spawnattr_destroy(&attrs) }
    let flags = Int16(POSIX_SPAWN_SETSID) | Int16(0x4000)
    posix_spawnattr_setflags(&attrs, flags)

    let argv: [UnsafeMutablePointer<CChar>?] = [
        strdup(executablePath),
        nil,
    ]
    defer { for ptr in argv { if ptr != nil { free(ptr) } } }

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

// MARK: - Allowed hosts

private let allowedHosts: Set<String> = [
    "github.com",
    "www.github.com",
    "objects.githubusercontent.com",
]

private let helperOperationDeadlineSeconds: TimeInterval = 840

// MARK: - XPC service implementation

@objc final class UpdateHelperImpl: NSObject, UpdateHelperProtocol {
    let verifiedCallerPID: Int32

    @objc init(verifiedCallerPID: Int32) {
        self.verifiedCallerPID = verifiedCallerPID
        super.init()
    }

    @objc override convenience init() {
        self.init(verifiedCallerPID: 0)
    }

    func installFromUrl(zipUrl: String,
                        checksumHex: String,
                        installedAppPath: String,
                        expectedTeamId: String,
                        expectedVersion: String,
                        parentPID: Int32,
                        relaunch: Bool,
                        reply: @escaping (Bool, String?) -> Void) {

        guard verifiedCallerPID > 0 else {
            reply(false, "caller PID not verified by XPC layer")
            return
        }
        guard !zipUrl.isEmpty, !checksumHex.isEmpty,
              !installedAppPath.isEmpty, !expectedTeamId.isEmpty,
              !expectedVersion.isEmpty else {
            reply(false, "missing required arguments")
            return
        }
        guard installedAppPath == "/Applications/Dacx.app" else {
            reply(false, "installed path must be /Applications/Dacx.app")
            return
        }
        guard let parsedUrl = URL(string: zipUrl),
              parsedUrl.scheme == "https",
              allowedHosts.contains(parsedUrl.host ?? "") else {
            reply(false, "zipUrl must be https and on an allowed host (github.com / objects.githubusercontent.com)")
            return
        }
        guard checksumHex.count == 64,
              checksumHex.allSatisfy({ $0.isHexDigit }) else {
            reply(false, "checksumHex must be 64 hex characters")
            return
        }

        let effectivePID = verifiedCallerPID

        guard let selfPath = Bundle.main.executablePath else {
            reply(false, "could not resolve XPC executable path")
            return
        }
        let installLock: UpdateInstallLock
        switch acquireUpdateInstallLock() {
        case .failure(let error):
            reply(false, error.description)
            return
        case .success(let lock):
            installLock = lock
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let startedAt = Date()
            var workerAccepted = false
            var downloadDirPath: String?
            var preSpawnCleanupPaths: [String] = []

            defer {
                if workerAccepted {
                    cleanupPath(downloadDirPath)
                    installLock.closeForInheritedWorker()
                } else {
                    for path in preSpawnCleanupPaths.reversed() {
                        cleanupPath(path)
                    }
                    installLock.release()
                }
            }

            func abortIfExpired(_ phase: String) -> Bool {
                let elapsed = Date().timeIntervalSince(startedAt)
                if elapsed <= helperOperationDeadlineSeconds { return false }
                let seconds = Int(helperOperationDeadlineSeconds)
                dacxLog("installFromUrl: timed out during \(phase) after \(Int(elapsed))s")
                reply(false, "update helper timed out during \(phase) after \(seconds)s")
                return true
            }

            dacxLog("installFromUrl: downloading \(zipUrl)")

            // 1. Download
            let downloadResult = downloadToTemp(parsedUrl)
            let zipFileUrl: URL
            switch downloadResult {
            case .failure(let err):
                dacxLog("installFromUrl: download failed: \(err)")
                reply(false, "download failed: \(err)")
                return
            case .success(let url):
                zipFileUrl = url
            }
            downloadDirPath = zipFileUrl.deletingLastPathComponent().path
            preSpawnCleanupPaths.append(zipFileUrl.deletingLastPathComponent().path)
            if abortIfExpired("download") { return }
            dacxLog("installFromUrl: download complete, verifying SHA256")

            // 2. SHA256 verify
            guard let actualHex = sha256Hex(of: zipFileUrl) else {
                reply(false, "could not compute SHA256 of downloaded file")
                return
            }
            if abortIfExpired("checksum verification") { return }
            if actualHex.lowercased() != checksumHex.lowercased() {
                dacxLog("installFromUrl: SHA256 mismatch expected=\(checksumHex) actual=\(actualHex)")
                reply(false, "SHA256 mismatch: expected \(checksumHex), got \(actualHex)")
                return
            }
            dacxLog("installFromUrl: SHA256 verified; extracting")

            // 3. Extract with ditto (un-sandboxed — no com.apple.provenance stamped)
            let extractDir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("dacx-extract-\(UUID().uuidString)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: extractDir,
                                                        withIntermediateDirectories: true)
                preSpawnCleanupPaths.append(extractDir.path)
            } catch {
                reply(false, "could not create extraction directory: \(error)")
                return
            }
            let (dittoCode, dittoOutput) = runCommand("/usr/bin/ditto", [
                "-x", "-k", "--sequesterRsrc",
                zipFileUrl.path,
                extractDir.path,
            ])
            if dittoCode != 0 {
                reply(false, "ditto extraction failed: \(dittoOutput)")
                return
            }
            if abortIfExpired("extraction") { return }

            let extractedAppPath = extractDir.appendingPathComponent("Dacx.app").path
            guard bundleExists(extractedAppPath) else {
                reply(false, "Dacx.app not found inside extracted zip")
                return
            }
            dacxLog("installFromUrl: extracted to \(extractedAppPath); validating bundle")

            // 4. Validate extracted bundle before spawning worker
            if let failure = validateBundle(extractedAppPath,
                                            expectedTeamId: expectedTeamId,
                                            expectedVersion: expectedVersion) {
                dacxLog("installFromUrl: bundle validation failed: \(failure)")
                reply(false, "bundle validation failed: \(failure)")
                return
            }
            if abortIfExpired("bundle validation") { return }
            dacxLog("installFromUrl: bundle valid; spawning worker")

            // 5. Spawn detached worker — it waits for parent PID exit, then swaps
            let env: [String: String] = [
                "DACX_UPDATE_WORKER": "1",
                "DACX_NEW_APP": extractedAppPath,
                "DACX_INSTALLED_APP": installedAppPath,
                "DACX_TEAM_ID": expectedTeamId,
                "DACX_VERSION": expectedVersion,
                "DACX_PARENT_PID": String(effectivePID),
                "DACX_RELAUNCH": relaunch ? "1" : "0",
                "DACX_CLEANUP_DIR": extractDir.path,
                "DACX_UPDATE_LOCK_FD": String(installLock.fd),
            ]
            if let err = spawnDetachedWorker(executablePath: selfPath,
                                             env: env,
                                             inheritedFD: installLock.fd) {
                reply(false, "posix_spawn failed: \(err)")
                return
            }

            workerAccepted = true
            dacxLog("installFromUrl: worker spawned; replying accepted=true")
            reply(true, nil)
        }
    }
}

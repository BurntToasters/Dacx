import Foundation
import Darwin

// Bundled signed update helper for Dacx.
// Waits for the parent (Dacx) process to exit, validates the new .app bundle
// against Gatekeeper, atomically swaps it into /Applications/Dacx.app with a
// rollback path, then relaunches Dacx.

struct Args {
    var waitPid: pid_t = 0
    var newApp: String = ""
    var installPath: String = ""
    var expectedTeamId: String = ""
    var relaunch: Bool = false
}

func parseArgs() -> Args? {
    var a = Args()
    var i = 1
    let argv = CommandLine.arguments
    while i < argv.count {
        let key = argv[i]
        let value = (i + 1 < argv.count) ? argv[i + 1] : ""
        switch key {
        case "--wait-pid":
            a.waitPid = pid_t(value) ?? 0
            i += 2
        case "--new-app":
            a.newApp = value
            i += 2
        case "--install-path":
            a.installPath = value
            i += 2
        case "--expected-team-id":
            a.expectedTeamId = value
            i += 2
        case "--relaunch":
            a.relaunch = true
            i += 1
        default:
            FileHandle.standardError.write("unknown arg \(key)\n".data(using: .utf8)!)
            return nil
        }
    }
    if a.waitPid == 0 || a.newApp.isEmpty || a.installPath.isEmpty || a.expectedTeamId.isEmpty {
        FileHandle.standardError.write("missing required args\n".data(using: .utf8)!)
        return nil
    }
    return a
}

func logLine(_ s: String) {
    FileHandle.standardError.write("dacx-update-helper: \(s)\n".data(using: .utf8)!)
}

func waitForPidExit(_ pid: pid_t, timeoutSeconds: Int = 120) {
    let kq = kqueue()
    if kq == -1 {
        logLine("kqueue() failed")
        return
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
        logLine("parent pid \(pid) already gone (kevent register errno=\(errno))")
        return
    }

    var triggered = kevent()
    var timeout = timespec(tv_sec: timeoutSeconds, tv_nsec: 0)
    _ = withUnsafeMutablePointer(to: &triggered) { tPtr in
        kevent(kq, nil, 0, tPtr, 1, &timeout)
    }
}

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

func teamId(of appPath: String) -> String? {
    let (code, output) = runCommand("/usr/bin/codesign", ["-dv", "--verbose=4", appPath])
    if code != 0 { return nil }
    for line in output.split(separator: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("TeamIdentifier=") {
            return String(trimmed.dropFirst("TeamIdentifier=".count))
        }
    }
    return nil
}

enum ValidationFailure: Error {
    case stapler(String)
    case codesign(String)
    case teamMismatch(String)
    case spctl(String)
}

func validateBundle(_ appPath: String, expectedTeamId: String) -> ValidationFailure? {
    let stapler = runCommand("/usr/bin/xcrun", ["stapler", "validate", appPath])
    if stapler.0 != 0 {
        return .stapler(stapler.1)
    }
    let verify = runCommand("/usr/bin/codesign", [
        "--verify", "--deep", "--strict", "--verbose=2", appPath,
    ])
    if verify.0 != 0 {
        return .codesign(verify.1)
    }
    guard let actual = teamId(of: appPath) else {
        return .teamMismatch("could not read team id")
    }
    if actual != expectedTeamId {
        return .teamMismatch("expected \(expectedTeamId), got \(actual)")
    }
    let spctl = runCommand("/usr/sbin/spctl", [
        "--assess", "--type", "execute", "--verbose=2", appPath,
    ])
    if spctl.0 != 0 {
        return .spctl(spctl.1)
    }
    return nil
}

let fm = FileManager.default

func bundleExists(_ path: String) -> Bool {
    var isDir: ObjCBool = false
    return fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
}

guard let args = parseArgs() else {
    exit(2)
}

logLine("waiting for parent pid \(args.waitPid) to exit")
waitForPidExit(args.waitPid)
logLine("parent exited, beginning swap")

// Pre-swap sanity: install path must exist and be a Dacx app signed by us.
// (This catches "user uninstalled Dacx mid-update" and anti-swap.)
guard bundleExists(args.installPath) else {
    logLine("install-path \(args.installPath) is missing; refusing to swap")
    exit(3)
}
if let installedTeam = teamId(of: args.installPath) {
    if installedTeam != args.expectedTeamId {
        logLine("install-path team \(installedTeam) != expected \(args.expectedTeamId); refusing")
        exit(4)
    }
} else {
    logLine("could not read team id of currently-installed bundle; refusing")
    exit(5)
}

// Swap with rollback
let backupPath = args.installPath + ".bak"
if fm.fileExists(atPath: backupPath) {
    try? fm.removeItem(atPath: backupPath)
}
do {
    try fm.moveItem(atPath: args.installPath, toPath: backupPath)
} catch {
    logLine("rename to .bak failed: \(error)")
    exit(6)
}

func restoreBackup() {
    try? fm.removeItem(atPath: args.installPath)
    do {
        try fm.moveItem(atPath: backupPath, toPath: args.installPath)
    } catch {
        logLine("rollback failed: \(error)")
    }
}

do {
    try fm.moveItem(atPath: args.newApp, toPath: args.installPath)
} catch {
    logLine("move new app to install-path failed: \(error)")
    restoreBackup()
    exit(7)
}

// Post-swap validation at install-path. If any check fails, roll back.
if let failure = validateBundle(args.installPath, expectedTeamId: args.expectedTeamId) {
    logLine("post-move validation failed: \(failure)")
    restoreBackup()
    exit(8)
}

// Success: drop the .bak, optionally relaunch Dacx
try? fm.removeItem(atPath: backupPath)

if args.relaunch {
    let openResult = runCommand("/usr/bin/open", [args.installPath])
    if openResult.0 != 0 {
        logLine("open failed (\(openResult.0)): \(openResult.1)")
    }
}

exit(0)

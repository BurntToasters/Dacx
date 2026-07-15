import Foundation

@objc public protocol UpdateHelperProtocol {
    /// Download, verify, extract, validate, and install an update; all in the
    /// unsandboxed helper so no files carry `com.apple.provenance` from the
    /// sandboxed main app.
    func installFromUrl(zipUrl: String,
                        checksumHex: String,
                        installedAppPath: String,
                        expectedTeamId: String,
                        expectedVersion: String,
                        parentPID: Int32,
                        relaunch: Bool,
                        reply: @escaping (Bool, String?) -> Void)
}

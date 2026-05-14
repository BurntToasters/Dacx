import Foundation

@objc public protocol UpdateHelperProtocol {
    func install(newAppPath: String,
                 installedAppPath: String,
                 expectedTeamId: String,
                 expectedVersion: String,
                 parentPID: Int32,
                 relaunch: Bool,
                 reply: @escaping (Bool, String?) -> Void)
}

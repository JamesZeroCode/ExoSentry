import Foundation

@objc public protocol ExoSentryHelperXPCProtocol {
    func setDisableSleep(_ disabled: Bool, withReply reply: @escaping (NSError?) -> Void)
    func restartWiFi(withReply reply: @escaping (NSError?) -> Void)
    func repairPrivileges(withReply reply: @escaping (NSError?) -> Void)
    func currentPrivilegeState(withReply reply: @escaping (NSString) -> Void)
}

enum PrivilegeState: String {
    case healthy
    case lost
}

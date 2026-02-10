import Foundation

@objc public protocol ExoSentryHelperXPCProtocol {
    func setDisableSleep(_ disabled: Bool, withReply reply: @escaping (NSError?) -> Void)
    func restartWiFi(withReply reply: @escaping (NSError?) -> Void)
    func repairPrivileges(withReply reply: @escaping (NSError?) -> Void)
    func currentPrivilegeState(withReply reply: @escaping (NSString) -> Void)
}

public enum PrivilegedClientError: Error, Equatable {
    case connectionUnavailable
    case operationFailed(String)
    case timeout
}

extension PrivilegedClientError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .connectionUnavailable:
            return "XPC connection unavailable"
        case .operationFailed(let message):
            return message
        case .timeout:
            return "XPC operation timed out"
        }
    }
}

import Foundation

@objc public protocol ExoSentryHelperXPCProtocol {
    func setDisableSleep(_ disabled: Bool, withReply reply: @escaping (NSString?) -> Void)
    func restartWiFi(withReply reply: @escaping (NSString?) -> Void)
    func repairPrivileges(withReply reply: @escaping (NSString?) -> Void)
    func currentPrivilegeState(withReply reply: @escaping (NSString) -> Void)
    func currentSOCTemperature(withReply reply: @escaping (NSNumber?, NSString?) -> Void)
    func setStaticIP(_ service: NSString, ip: NSString, subnet: NSString, router: NSString, withReply reply: @escaping (NSString?) -> Void)
    func setV6LinkLocal(_ service: NSString, withReply reply: @escaping (NSString?) -> Void)
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

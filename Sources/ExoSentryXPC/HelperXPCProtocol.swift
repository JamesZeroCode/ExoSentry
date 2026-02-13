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

public enum ExoSentryXPCInterfaceFactory {
    /// Creates a properly configured NSXPCInterface with explicit allowedClasses
    /// to avoid NSSecureCoding warnings about NSObject being too broad.
    public static func makeInterface() -> NSXPCInterface {
        let iface = NSXPCInterface(with: ExoSentryHelperXPCProtocol.self)
        let stringClasses = NSSet(array: [NSString.self]) as! Set<AnyHashable>
        let numberStringClasses = NSSet(array: [NSNumber.self, NSString.self]) as! Set<AnyHashable>

        // currentSOCTemperature reply: (NSNumber?, NSString?)
        let tempSel = #selector(ExoSentryHelperXPCProtocol.currentSOCTemperature(withReply:))
        iface.setClasses(numberStringClasses, for: tempSel, argumentIndex: 0, ofReply: true)
        iface.setClasses(numberStringClasses, for: tempSel, argumentIndex: 1, ofReply: true)

        // setStaticIP arguments: (NSString, NSString, NSString, NSString, reply)
        let staticIPSel = #selector(ExoSentryHelperXPCProtocol.setStaticIP(_:ip:subnet:router:withReply:))
        for i in 0..<4 {
            iface.setClasses(stringClasses, for: staticIPSel, argumentIndex: i, ofReply: false)
        }

        // setV6LinkLocal argument: (NSString, reply)
        let v6Sel = #selector(ExoSentryHelperXPCProtocol.setV6LinkLocal(_:withReply:))
        iface.setClasses(stringClasses, for: v6Sel, argumentIndex: 0, ofReply: false)

        return iface
    }
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

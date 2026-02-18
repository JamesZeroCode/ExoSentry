import Foundation

@objc public protocol ExoSentryHelperXPCProtocol {
    func setDisableSleep(_ disabled: Bool, withReply reply: @escaping (NSString?) -> Void)
    func restartWiFi(withReply reply: @escaping (NSString?) -> Void)
    func repairPrivileges(withReply reply: @escaping (NSString?) -> Void)
    func currentPrivilegeState(withReply reply: @escaping (NSString) -> Void)
    func currentSOCTemperature(withReply reply: @escaping (NSNumber?, NSString?) -> Void)
    func setStaticIP(_ service: NSString, ip: NSString, subnet: NSString, router: NSString, withReply reply: @escaping (NSString?) -> Void)
    func setV6LinkLocal(_ service: NSString, withReply reply: @escaping (NSString?) -> Void)
    func currentServiceIPv4Snapshot(_ service: NSString, withReply reply: @escaping (NSString, NSString?) -> Void)
}

enum HelperXPCInterfaceFactory {
    static func makeInterface() -> NSXPCInterface {
        let iface = NSXPCInterface(with: ExoSentryHelperXPCProtocol.self)
        let stringClasses = NSSet(array: [NSString.self]) as! Set<AnyHashable>
        let numberStringClasses = NSSet(array: [NSNumber.self, NSString.self]) as! Set<AnyHashable>

        // setDisableSleep reply: (NSString?)
        let sleepSel = #selector(ExoSentryHelperXPCProtocol.setDisableSleep(_:withReply:))
        iface.setClasses(stringClasses, for: sleepSel, argumentIndex: 0, ofReply: true)

        // restartWiFi reply: (NSString?)
        let wifiSel = #selector(ExoSentryHelperXPCProtocol.restartWiFi(withReply:))
        iface.setClasses(stringClasses, for: wifiSel, argumentIndex: 0, ofReply: true)

        // repairPrivileges reply: (NSString?)
        let repairSel = #selector(ExoSentryHelperXPCProtocol.repairPrivileges(withReply:))
        iface.setClasses(stringClasses, for: repairSel, argumentIndex: 0, ofReply: true)

        // currentPrivilegeState reply: (NSString)
        let stateSel = #selector(ExoSentryHelperXPCProtocol.currentPrivilegeState(withReply:))
        iface.setClasses(stringClasses, for: stateSel, argumentIndex: 0, ofReply: true)

        // currentSOCTemperature reply: (NSNumber?, NSString?)
        let tempSel = #selector(ExoSentryHelperXPCProtocol.currentSOCTemperature(withReply:))
        iface.setClasses(numberStringClasses, for: tempSel, argumentIndex: 0, ofReply: true)
        iface.setClasses(numberStringClasses, for: tempSel, argumentIndex: 1, ofReply: true)

        // setStaticIP arguments + reply: (NSString?)
        let staticIPSel = #selector(ExoSentryHelperXPCProtocol.setStaticIP(_:ip:subnet:router:withReply:))
        for i in 0..<4 {
            iface.setClasses(stringClasses, for: staticIPSel, argumentIndex: i, ofReply: false)
        }
        iface.setClasses(stringClasses, for: staticIPSel, argumentIndex: 0, ofReply: true)

        // setV6LinkLocal argument + reply: (NSString?)
        let v6Sel = #selector(ExoSentryHelperXPCProtocol.setV6LinkLocal(_:withReply:))
        iface.setClasses(stringClasses, for: v6Sel, argumentIndex: 0, ofReply: false)
        iface.setClasses(stringClasses, for: v6Sel, argumentIndex: 0, ofReply: true)

        let ipv4Sel = #selector(ExoSentryHelperXPCProtocol.currentServiceIPv4Snapshot(_:withReply:))
        iface.setClasses(stringClasses, for: ipv4Sel, argumentIndex: 0, ofReply: false)
        iface.setClasses(stringClasses, for: ipv4Sel, argumentIndex: 0, ofReply: true)
        iface.setClasses(stringClasses, for: ipv4Sel, argumentIndex: 1, ofReply: true)

        return iface
    }
}

enum PrivilegeState: String, Sendable {
    case healthy
    case lost
}

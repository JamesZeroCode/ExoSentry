import Foundation

public struct ServiceIPv4Snapshot: Equatable, Sendable {
    public let configuration: String
    public let ipAddress: String?

    public init(configuration: String, ipAddress: String?) {
        self.configuration = configuration
        self.ipAddress = ipAddress
    }
}

public protocol PrivilegedCommanding: Sendable {
    func setDisableSleep(_ disabled: Bool) throws
    func restartWiFi() throws
    func repairPrivileges() throws
    func currentPrivilegeState() -> PrivilegeState
    func currentSOCTemperature() -> Double?
    func setStaticIP(service: String, ip: String, subnet: String, router: String) throws
    func setV6LinkLocal(service: String) throws
    func currentServiceIPv4Snapshot(service: String) -> ServiceIPv4Snapshot?
}

public extension PrivilegedCommanding {
    func currentServiceIPv4Snapshot(service: String) -> ServiceIPv4Snapshot? {
        nil
    }
}

public enum PrivilegeState: String, Sendable {
    case healthy
    case lost
}

public struct HelperPermissionSnapshot: Equatable, Sendable {
    public let state: PrivilegeState
    public let repairHint: String

    public init(state: PrivilegeState, repairHint: String) {
        self.state = state
        self.repairHint = repairHint
    }
}

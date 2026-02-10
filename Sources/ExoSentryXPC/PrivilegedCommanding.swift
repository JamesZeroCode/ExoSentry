import Foundation

public protocol PrivilegedCommanding: Sendable {
    func setDisableSleep(_ disabled: Bool) throws
    func restartWiFi() throws
    func repairPrivileges() throws
    func currentPrivilegeState() -> PrivilegeState
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

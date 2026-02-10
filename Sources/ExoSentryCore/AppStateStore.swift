import Foundation

public enum PermissionWarningState: String, Sendable {
    case none
    case warning
}

public actor AppStateStore {
    private var status: GuardStatus = .paused
    private var mode: OperatingMode
    private var tempC: Double?
    private var isCharging = false
    private var lidClosed = false
    private var targetProcess: String
    private var targetProcessRunning = false
    private var networkState: NetworkState = .ok
    private var permissionWarning: PermissionWarningState = .none

    public init(initialMode: OperatingMode, targetProcess: String) {
        self.mode = initialMode
        self.targetProcess = targetProcess
    }

    public func updateMode(_ mode: OperatingMode) {
        self.mode = mode
    }

    public func updateGuardStatus(_ status: GuardStatus) {
        self.status = status
    }

    public func updateTargetProcess(_ name: String, running: Bool) {
        self.targetProcess = name
        self.targetProcessRunning = running
    }

    public func updateNetworkState(_ state: NetworkState) {
        self.networkState = state
    }

    public func updateTemperature(_ value: Double?) {
        self.tempC = value
    }

    public func updateCharging(_ charging: Bool) {
        self.isCharging = charging
    }

    public func updateLidClosed(_ closed: Bool) {
        self.lidClosed = closed
    }

    public func updatePermissionWarning(_ warning: PermissionWarningState) {
        self.permissionWarning = warning
    }

    public func permissionWarningState() -> PermissionWarningState {
        permissionWarning
    }

    public func snapshotStatus(lastUpdated: String) -> StatusPayload {
        let effectiveStatus: GuardStatus = permissionWarning == .warning ? .degraded : status
        return StatusPayload(
            status: effectiveStatus,
            mode: mode,
            tempC: tempC,
            isCharging: isCharging,
            lidClosed: lidClosed,
            targetProcess: targetProcess,
            targetProcessRunning: targetProcessRunning,
            networkState: networkState,
            lastUpdated: lastUpdated
        )
    }
}

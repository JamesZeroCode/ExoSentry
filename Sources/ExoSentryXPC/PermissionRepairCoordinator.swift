import ExoSentryCore
import Foundation

public final class PermissionRepairCoordinator: @unchecked Sendable {
    private let privilegedClient: PrivilegedCommanding
    private let stateStore: AppStateStore

    public init(privilegedClient: PrivilegedCommanding, stateStore: AppStateStore) {
        self.privilegedClient = privilegedClient
        self.stateStore = stateStore
    }

    public func refreshWarningState() async {
        let state = privilegedClient.currentPrivilegeState()
        if state == .lost {
            await stateStore.updatePermissionWarning(.warning)
        } else {
            await stateStore.updatePermissionWarning(.none)
        }
    }

    public func repairIfNeeded() async throws {
        let state = privilegedClient.currentPrivilegeState()
        guard state == .lost else {
            return
        }
        try privilegedClient.repairPrivileges()
        await stateStore.updatePermissionWarning(.none)
    }
}

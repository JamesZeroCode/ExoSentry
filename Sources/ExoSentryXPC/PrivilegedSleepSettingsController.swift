import ExoSentryCore
import Foundation

public struct PrivilegedSleepSettingsController: SleepSettingsControlling {
    private let privilegedClient: PrivilegedCommanding

    public init(privilegedClient: PrivilegedCommanding) {
        self.privilegedClient = privilegedClient
    }

    public func setDisableSleep(_ disabled: Bool) throws {
        try privilegedClient.setDisableSleep(disabled)
    }
}

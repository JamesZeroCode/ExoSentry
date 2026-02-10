import Foundation

final class HelperService: NSObject, ExoSentryHelperXPCProtocol, @unchecked Sendable {
    private let sleepController: SleepSettingsControlling
    private let wifiController: WiFiControlling
    private var state: PrivilegeState
    private let stateLock = NSLock()

    init(
        sleepController: SleepSettingsControlling,
        wifiController: WiFiControlling = SystemWiFiController(),
        initialState: PrivilegeState = .healthy
    ) {
        self.sleepController = sleepController
        self.wifiController = wifiController
        self.state = initialState
    }

    private func setDisableSleepInternal(_ disabled: Bool) throws {
        try sleepController.setDisableSleep(disabled)
    }

    private func repairPrivilegesInternal() {
        stateLock.lock()
        defer { stateLock.unlock() }
        state = .healthy
    }

    private func restartWiFiInternal() throws {
        try wifiController.restartWiFi()
    }

    private func currentPrivilegeStateInternal() -> PrivilegeState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return state
    }

    func setDisableSleep(_ disabled: Bool, withReply reply: @escaping (NSError?) -> Void) {
        do {
            try setDisableSleepInternal(disabled)
            reply(nil)
        } catch {
            reply(error as NSError)
        }
    }

    func repairPrivileges(withReply reply: @escaping (NSError?) -> Void) {
        repairPrivilegesInternal()
        reply(nil)
    }

    func restartWiFi(withReply reply: @escaping (NSError?) -> Void) {
        do {
            try restartWiFiInternal()
            reply(nil)
        } catch {
            reply(error as NSError)
        }
    }

    func currentPrivilegeState(withReply reply: @escaping (NSString) -> Void) {
        reply(currentPrivilegeStateInternal().rawValue as NSString)
    }
}

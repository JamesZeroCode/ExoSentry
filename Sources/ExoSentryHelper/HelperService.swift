import Foundation

final class HelperService: NSObject, ExoSentryHelperXPCProtocol, @unchecked Sendable {
    private let sleepController: SleepSettingsControlling
    private let wifiController: WiFiControlling
    private let networkIPController: NetworkIPControlling
    private let socTemperatureProvider: SOCTemperatureProviding
    private var state: PrivilegeState
    private let stateLock = NSLock()

    init(
        sleepController: SleepSettingsControlling,
        wifiController: WiFiControlling = SystemWiFiController(),
        networkIPController: NetworkIPControlling = SystemNetworkIPController(),
        socTemperatureProvider: SOCTemperatureProviding = PowermetricsSOCTemperatureProvider(),
        initialState: PrivilegeState = .healthy
    ) {
        self.sleepController = sleepController
        self.wifiController = wifiController
        self.networkIPController = networkIPController
        self.socTemperatureProvider = socTemperatureProvider
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

    private func markPrivilegeState(_ newState: PrivilegeState) {
        stateLock.lock()
        defer { stateLock.unlock() }
        state = newState
    }

    private func restartWiFiInternal() throws {
        try wifiController.restartWiFi()
    }

    private func currentPrivilegeStateInternal() -> PrivilegeState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return state
    }

    func setDisableSleep(_ disabled: Bool, withReply reply: @escaping (NSString?) -> Void) {
        do {
            try setDisableSleepInternal(disabled)
            markPrivilegeState(.healthy)
            reply(nil)
        } catch {
            markPrivilegeState(.lost)
            reply(error.localizedDescription as NSString)
        }
    }

    func repairPrivileges(withReply reply: @escaping (NSString?) -> Void) {
        repairPrivilegesInternal()
        reply(nil)
    }

    func restartWiFi(withReply reply: @escaping (NSString?) -> Void) {
        do {
            try restartWiFiInternal()
            markPrivilegeState(.healthy)
            reply(nil)
        } catch {
            markPrivilegeState(.lost)
            reply(error.localizedDescription as NSString)
        }
    }

    func currentPrivilegeState(withReply reply: @escaping (NSString) -> Void) {
        reply(currentPrivilegeStateInternal().rawValue as NSString)
    }

    func currentSOCTemperature(withReply reply: @escaping (NSNumber?, NSString?) -> Void) {
        do {
            let value = try socTemperatureProvider.currentTemperatureC()
            reply(NSNumber(value: value), nil)
        } catch {
            reply(nil, error.localizedDescription as NSString)
        }
    }

    func setStaticIP(_ service: NSString, ip: NSString, subnet: NSString, router: NSString, withReply reply: @escaping (NSString?) -> Void) {
        do {
            try networkIPController.setStaticIP(service: service as String, ip: ip as String, subnet: subnet as String, router: router as String)
            markPrivilegeState(.healthy)
            reply(nil)
        } catch {
            markPrivilegeState(.lost)
            reply(error.localizedDescription as NSString)
        }
    }

    func setV6LinkLocal(_ service: NSString, withReply reply: @escaping (NSString?) -> Void) {
        do {
            try networkIPController.setV6LinkLocal(service: service as String)
            markPrivilegeState(.healthy)
            reply(nil)
        } catch {
            markPrivilegeState(.lost)
            reply(error.localizedDescription as NSString)
        }
    }
}

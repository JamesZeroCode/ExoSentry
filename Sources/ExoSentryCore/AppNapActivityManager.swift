import Foundation

public protocol AppNapActivityManaging: Sendable {
    func beginActivity(reason: String)
    func endActivity()
}

public final class ProcessInfoAppNapActivityManager: @unchecked Sendable, AppNapActivityManaging {
    private var token: NSObjectProtocol?

    public init() {}

    public func beginActivity(reason: String) {
        guard token == nil else {
            return
        }
        token = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: reason
        )
    }

    public func endActivity() {
        guard let token else {
            return
        }
        ProcessInfo.processInfo.endActivity(token)
        self.token = nil
    }
}

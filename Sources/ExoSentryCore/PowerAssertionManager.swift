import Foundation
import IOKit.pwr_mgt

public protocol PowerAssertionManaging: Sendable {
    var isActive: Bool { get }
    func activate() throws
    func deactivate()
}

public enum PowerAssertionError: Error, Equatable {
    case unableToCreateAssertion
}

public protocol PowerAssertionSystem: Sendable {
    func createAssertion(type: CFString, name: CFString) -> IOPMAssertionID?
    func releaseAssertion(id: IOPMAssertionID)
}

public struct IOKitPowerAssertionSystem: PowerAssertionSystem {
    public init() {}

    public func createAssertion(type: CFString, name: CFString) -> IOPMAssertionID? {
        var assertionID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(type, IOPMAssertionLevel(kIOPMAssertionLevelOn), name, &assertionID)
        guard result == kIOReturnSuccess else {
            return nil
        }
        return assertionID
    }

    public func releaseAssertion(id: IOPMAssertionID) {
        _ = IOPMAssertionRelease(id)
    }
}

public final class PowerAssertionManager: PowerAssertionManaging, @unchecked Sendable {
    private let system: PowerAssertionSystem
    private let lock = NSLock()
    private var noIdleSleepID: IOPMAssertionID?
    private var noDisplaySleepID: IOPMAssertionID?

    public init(system: PowerAssertionSystem = IOKitPowerAssertionSystem()) {
        self.system = system
    }

    public var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return noIdleSleepID != nil && noDisplaySleepID != nil
    }

    public func activate() throws {
        lock.lock()
        defer { lock.unlock() }
        
        if noIdleSleepID != nil && noDisplaySleepID != nil {
            return
        }
        guard let idleID = system.createAssertion(type: kIOPMAssertionTypeNoIdleSleep as CFString, name: "ExoSentry.NoIdleSleep" as CFString) else {
            throw PowerAssertionError.unableToCreateAssertion
        }
        guard let displayID = system.createAssertion(type: kIOPMAssertionTypeNoDisplaySleep as CFString, name: "ExoSentry.NoDisplaySleep" as CFString) else {
            system.releaseAssertion(id: idleID)
            throw PowerAssertionError.unableToCreateAssertion
        }
        noIdleSleepID = idleID
        noDisplaySleepID = displayID
    }

    public func deactivate() {
        lock.lock()
        defer { lock.unlock() }
        
        if let idleID = noIdleSleepID {
            system.releaseAssertion(id: idleID)
            noIdleSleepID = nil
        }
        if let displayID = noDisplaySleepID {
            system.releaseAssertion(id: displayID)
            noDisplaySleepID = nil
        }
    }
}

import Foundation
#if canImport(ServiceManagement)
import ServiceManagement
#endif

public protocol LoginItemManaging: Sendable {
    func setLaunchAtLogin(enabled: Bool) throws
}

public enum LoginItemManagerError: Error {
    case unsupportedPlatform
}

public struct LoginItemManager: LoginItemManaging {
    public init() {}

    public func setLaunchAtLogin(enabled: Bool) throws {
        #if canImport(ServiceManagement)
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        #else
        throw LoginItemManagerError.unsupportedPlatform
        #endif
    }
}

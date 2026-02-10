import Foundation

public struct ModeBehavior: Equatable, Sendable {
    public let preventSystemSleep: Bool
    public let preventDisplaySleep: Bool
    public let allowClamshell: Bool
    public let networkGuardEnabled: Bool

    public init(
        preventSystemSleep: Bool,
        preventDisplaySleep: Bool,
        allowClamshell: Bool,
        networkGuardEnabled: Bool
    ) {
        self.preventSystemSleep = preventSystemSleep
        self.preventDisplaySleep = preventDisplaySleep
        self.allowClamshell = allowClamshell
        self.networkGuardEnabled = networkGuardEnabled
    }

    public static func forMode(_ mode: OperatingMode) -> ModeBehavior {
        switch mode {
        case .cluster:
            return ModeBehavior(
                preventSystemSleep: true,
                preventDisplaySleep: true,
                allowClamshell: true,
                networkGuardEnabled: true
            )
        case .standard:
            return ModeBehavior(
                preventSystemSleep: true,
                preventDisplaySleep: false,
                allowClamshell: false,
                networkGuardEnabled: false
            )
        }
    }
}

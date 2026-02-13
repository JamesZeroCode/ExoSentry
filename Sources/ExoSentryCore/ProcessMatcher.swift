import Foundation

public struct ProcessMatcher: Sendable {
    public init() {}

    public func shouldActivateGuard(
        configuredTargets: [String],
        runningProcessNames: [String]
    ) -> Bool {
        let targets = configuredTargets
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !targets.isEmpty else {
            return false
        }

        let runningLower = Set(runningProcessNames.map { $0.lowercased() })
        return targets.contains { runningLower.contains($0.lowercased()) }
    }

    public func matchedTarget(
        configuredTargets: [String],
        runningProcessNames: [String]
    ) -> String? {
        let runningLower = Set(runningProcessNames.map { $0.lowercased() })
        return configuredTargets
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .first { runningLower.contains($0.lowercased()) }
    }
}

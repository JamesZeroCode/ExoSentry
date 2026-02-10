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

        let runningSet = Set(runningProcessNames)
        return targets.contains { runningSet.contains($0) }
    }
}

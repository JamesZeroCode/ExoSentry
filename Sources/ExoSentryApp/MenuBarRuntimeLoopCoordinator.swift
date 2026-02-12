import Foundation

@MainActor
final class MenuBarRuntimeLoopCoordinator {
    private var task: Task<Void, Never>?
    private let intervalNanoseconds: UInt64

    init(intervalNanoseconds: UInt64 = 5_000_000_000) {
        self.intervalNanoseconds = intervalNanoseconds
    }

    func start(_ tick: @escaping @MainActor () async -> Void) {
        stop()
        task = Task {
            while !Task.isCancelled {
                await tick()
                try? await Task.sleep(nanoseconds: intervalNanoseconds)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

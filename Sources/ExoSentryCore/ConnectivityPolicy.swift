import Foundation

public struct ProbeSnapshot: Equatable, Sendable {
    public let gatewayReachable: Bool
    public let internetReachable: Bool

    public init(gatewayReachable: Bool, internetReachable: Bool) {
        self.gatewayReachable = gatewayReachable
        self.internetReachable = internetReachable
    }

    public var networkState: NetworkState {
        if gatewayReachable && internetReachable {
            return .ok
        }
        if !gatewayReachable && !internetReachable {
            return .offline
        }
        if !gatewayReachable {
            return .lanLost
        }
        return .wanLost
    }
}

public enum ConnectivityAction: Equatable, Sendable {
    case healthy
    case retry(NetworkState, Int)
    case alert(NetworkState)
}

public struct ConnectivityPolicy: Equatable, Sendable {
    public let failureThreshold: Int
    public let maxRetries: Int

    public init(failureThreshold: Int = 3, maxRetries: Int = 3) {
        self.failureThreshold = failureThreshold
        self.maxRetries = maxRetries
    }
}

public final class ConnectivityPolicyTracker: @unchecked Sendable {
    private let policy: ConnectivityPolicy
    private let lock = NSLock()
    private var consecutiveFailures = 0
    private var retriesUsed = 0

    public init(policy: ConnectivityPolicy = ConnectivityPolicy()) {
        self.policy = policy
    }

    public func evaluate(_ snapshot: ProbeSnapshot) -> ConnectivityAction {
        lock.lock()
        defer { lock.unlock() }
        
        if snapshot.networkState == .ok {
            consecutiveFailures = 0
            retriesUsed = 0
            return .healthy
        }

        consecutiveFailures += 1
        if consecutiveFailures < policy.failureThreshold {
            return .healthy
        }

        if retriesUsed < policy.maxRetries {
            retriesUsed += 1
            return .retry(snapshot.networkState, retriesUsed)
        }

        return .alert(snapshot.networkState)
    }
}

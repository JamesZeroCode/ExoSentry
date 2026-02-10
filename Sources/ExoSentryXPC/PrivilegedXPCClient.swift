import Foundation

public final class PrivilegedXPCClient: PrivilegedCommanding, @unchecked Sendable {
    private let machServiceName: String
    private let timeoutSeconds: TimeInterval
    private let maxAttempts: Int
    private let retryBackoffSeconds: TimeInterval

    public init(
        machServiceName: String = "com.exosentry.helper",
        timeoutSeconds: TimeInterval = 5,
        maxAttempts: Int = 3,
        retryBackoffSeconds: TimeInterval = 0.2
    ) {
        self.machServiceName = machServiceName
        self.timeoutSeconds = timeoutSeconds
        self.maxAttempts = max(1, maxAttempts)
        self.retryBackoffSeconds = max(0, retryBackoffSeconds)
    }

    public func setDisableSleep(_ disabled: Bool) throws {
        try performVoidOperation(operationName: "setDisableSleep") { proxy, completion in
            proxy.setDisableSleep(disabled, withReply: completion)
        }
    }

    public func restartWiFi() throws {
        try performVoidOperation(operationName: "restartWiFi") { proxy, completion in
            proxy.restartWiFi(withReply: completion)
        }
    }

    public func repairPrivileges() throws {
        try performVoidOperation(operationName: "repairPrivileges") { proxy, completion in
            proxy.repairPrivileges(withReply: completion)
        }
    }

    public func currentPrivilegeState() -> PrivilegeState {
        do {
            let value: String = try performValueOperation(operationName: "currentPrivilegeState") { proxy, completion in
                proxy.currentPrivilegeState { state in
                    completion(String(state))
                }
            }
            return PrivilegeState(rawValue: value) ?? .lost
        } catch {
            return .lost
        }
    }

    private func createConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: ExoSentryHelperXPCProtocol.self)
        connection.resume()
        return connection
    }

    private func performVoidOperation(
        operationName: String,
        _ operation: (ExoSentryHelperXPCProtocol, @escaping (NSError?) -> Void) -> Void
    ) throws {
        let _: Bool = try performValueOperation(operationName: operationName) { proxy, completion in
            operation(proxy) { error in
                if let error {
                    completion(error)
                    return
                }
                completion(true)
            }
        }
    }

    private func performValueOperation<T>(
        operationName: String,
        _ operation: (ExoSentryHelperXPCProtocol, @escaping (Any) -> Void) -> Void
    ) throws -> T {
        var lastError: Error = PrivilegedClientError.timeout
        for attempt in 1...maxAttempts {
            do {
                return try performValueOperationOnce(operationName: operationName, attempt: attempt, operation)
            } catch let error as PrivilegedClientError {
                lastError = error
                let isRetryable = error == .timeout || error == .connectionUnavailable
                if isRetryable, attempt < maxAttempts {
                    let delay = retryBackoffSeconds * Double(attempt)
                    if delay > 0 {
                        Thread.sleep(forTimeInterval: delay)
                    }
                    continue
                }
                throw error
            } catch {
                throw error
            }
        }
        throw lastError
    }

    private func performValueOperationOnce<T>(
        operationName: String,
        attempt: Int,
        _ operation: (ExoSentryHelperXPCProtocol, @escaping (Any) -> Void) -> Void
    ) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<T, Error> = .failure(PrivilegedClientError.timeout)
        let connection = createConnection()
        connection.interruptionHandler = {
            result = .failure(PrivilegedClientError.operationFailed("\(operationName) interrupted (attempt \(attempt))"))
            semaphore.signal()
        }

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            result = .failure(PrivilegedClientError.operationFailed("\(operationName) remote error (attempt \(attempt)): \(error.localizedDescription)"))
            semaphore.signal()
        }) as? ExoSentryHelperXPCProtocol else {
            connection.invalidate()
            throw PrivilegedClientError.connectionUnavailable
        }

        operation(proxy) { value in
            if let error = value as? NSError {
                result = .failure(PrivilegedClientError.operationFailed("\(operationName) failed (attempt \(attempt)): \(error.localizedDescription)"))
            } else if let typed = value as? T {
                result = .success(typed)
            } else {
                result = .failure(PrivilegedClientError.operationFailed("\(operationName) unexpected response type (attempt \(attempt))"))
            }
            semaphore.signal()
        }

        let waitResult = semaphore.wait(timeout: .now() + timeoutSeconds)
        connection.invalidate()
        if waitResult == .timedOut {
            throw PrivilegedClientError.timeout
        }
        return try result.get()
    }
}

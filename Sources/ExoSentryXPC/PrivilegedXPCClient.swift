import Foundation

/// Thread-safe, write-once result container for XPC callbacks.
/// Multiple XPC handlers (error, interruption, reply) may fire concurrently;
/// only the first completion is accepted, preventing data races on the result.
private final class OnceResult<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Result<T, Error>
    private var _completed = false

    init(default defaultValue: Result<T, Error>) {
        _value = defaultValue
    }

    /// Attempts to set the result. Returns `true` if this was the first completion.
    func complete(_ result: Result<T, Error>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !_completed else { return false }
        _completed = true
        _value = result
        return true
    }

    var value: Result<T, Error> {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
}

public final class PrivilegedXPCClient: PrivilegedCommanding, @unchecked Sendable {
    private let machServiceName: String
    private let timeoutSeconds: TimeInterval
    private let maxAttempts: Int

    public init(
        machServiceName: String = "com.exosentry.helper",
        timeoutSeconds: TimeInterval = 5,
        maxAttempts: Int = 3
    ) {
        self.machServiceName = machServiceName
        self.timeoutSeconds = timeoutSeconds
        self.maxAttempts = max(1, maxAttempts)
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

    public func setStaticIP(service: String, ip: String, subnet: String, router: String) throws {
        try performVoidOperation(operationName: "setStaticIP") { proxy, completion in
            proxy.setStaticIP(service as NSString, ip: ip as NSString, subnet: subnet as NSString, router: router as NSString, withReply: completion)
        }
    }

    public func setV6LinkLocal(service: String) throws {
        try performVoidOperation(operationName: "setV6LinkLocal") { proxy, completion in
            proxy.setV6LinkLocal(service as NSString, withReply: completion)
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
        let box = OnceResult<T>(default: .failure(PrivilegedClientError.timeout))
        let connection = createConnection()
        connection.interruptionHandler = { [box] in
            if box.complete(.failure(PrivilegedClientError.operationFailed("\(operationName) interrupted (attempt \(attempt))"))) {
                semaphore.signal()
            }
        }

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ [box] error in
            if box.complete(.failure(PrivilegedClientError.operationFailed("\(operationName) remote error (attempt \(attempt)): \(error.localizedDescription)"))) {
                semaphore.signal()
            }
        }) as? ExoSentryHelperXPCProtocol else {
            connection.invalidate()
            throw PrivilegedClientError.connectionUnavailable
        }

        operation(proxy) { [box] value in
            let outcome: Result<T, Error>
            if let error = value as? NSError {
                outcome = .failure(PrivilegedClientError.operationFailed("\(operationName) failed (attempt \(attempt)): \(error.localizedDescription)"))
            } else if let typed = value as? T {
                outcome = .success(typed)
            } else {
                outcome = .failure(PrivilegedClientError.operationFailed("\(operationName) unexpected response type (attempt \(attempt))"))
            }
            if box.complete(outcome) {
                semaphore.signal()
            }
        }

        let waitResult = semaphore.wait(timeout: .now() + timeoutSeconds)
        connection.invalidate()
        if waitResult == .timedOut {
            throw PrivilegedClientError.timeout
        }
        return try box.value.get()
    }
}

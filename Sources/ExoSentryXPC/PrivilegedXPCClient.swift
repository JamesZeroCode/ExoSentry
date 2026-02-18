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
    private let connectionLock = NSLock()
    private var cachedConnection: NSXPCConnection?

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
        try performVoidOperation(operationName: "setStaticIP", operationTimeout: 15) { proxy, completion in
            proxy.setStaticIP(service as NSString, ip: ip as NSString, subnet: subnet as NSString, router: router as NSString, withReply: completion)
        }
    }

    public func setV6LinkLocal(service: String) throws {
        try performVoidOperation(operationName: "setV6LinkLocal", operationTimeout: 15) { proxy, completion in
            proxy.setV6LinkLocal(service as NSString, withReply: completion)
        }
    }

    public func currentServiceIPv4Snapshot(service: String) -> ServiceIPv4Snapshot? {
        do {
            let value = try performStringPairValueOperation(operationName: "currentServiceIPv4Snapshot") { proxy, completion in
                proxy.currentServiceIPv4Snapshot(service as NSString, withReply: completion)
            }
            let configuration = String(value.0)
            let rawIP = String(value.1)
            let ipAddress = rawIP.isEmpty ? nil : rawIP
            return ServiceIPv4Snapshot(configuration: configuration, ipAddress: ipAddress)
        } catch {
            return nil
        }
    }

    public func currentPrivilegeState() -> PrivilegeState {
        do {
            let value = try performStringValueOperation(operationName: "currentPrivilegeState") { proxy, completion in
                proxy.currentPrivilegeState(withReply: completion)
            }
            return PrivilegeState(rawValue: String(value)) ?? .lost
        } catch {
            return .lost
        }
    }

    public func currentSOCTemperature() -> Double? {
        do {
            let value = try performNumberValueOperation(operationName: "currentSOCTemperature", operationTimeout: 15) { proxy, completion in
                proxy.currentSOCTemperature(withReply: completion)
            }
            return value.doubleValue
        } catch {
            return nil
        }
    }

    private func getOrCreateConnection() -> NSXPCConnection {
        connectionLock.lock()
        defer { connectionLock.unlock() }
        if let existing = cachedConnection {
            return existing
        }
        let connection = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
        connection.remoteObjectInterface = ExoSentryXPCInterfaceFactory.makeInterface()
        connection.invalidationHandler = { [weak self] in
            self?.clearCachedConnection()
        }
        connection.resume()
        cachedConnection = connection
        return connection
    }

    private func clearCachedConnection() {
        connectionLock.lock()
        defer { connectionLock.unlock() }
        cachedConnection = nil
    }

    private func invalidateCachedConnection() {
        connectionLock.lock()
        let conn = cachedConnection
        cachedConnection = nil
        connectionLock.unlock()
        conn?.invalidate()
    }

    private func performVoidOperation(
        operationName: String,
        operationTimeout: TimeInterval? = nil,
        _ operation: (ExoSentryHelperXPCProtocol, @escaping (NSString?) -> Void) -> Void
    ) throws {
        var lastError: Error = PrivilegedClientError.timeout
        for attempt in 1...maxAttempts {
            do {
                try performVoidOperationOnce(operationName: operationName, attempt: attempt, operationTimeout: operationTimeout, operation)
                return
            } catch let error as PrivilegedClientError {
                lastError = error
                if error.isConnectionError, attempt < maxAttempts {
                    invalidateCachedConnection()
                    continue
                }
                throw error
            } catch {
                throw error
            }
        }
        throw lastError
    }

    private func performStringValueOperation(
        operationName: String,
        _ operation: (ExoSentryHelperXPCProtocol, @escaping (NSString) -> Void) -> Void
    ) throws -> NSString {
        var lastError: Error = PrivilegedClientError.timeout
        for attempt in 1...maxAttempts {
            do {
                return try performStringValueOperationOnce(operationName: operationName, attempt: attempt, operation)
            } catch let error as PrivilegedClientError {
                lastError = error
                if error.isConnectionError, attempt < maxAttempts {
                    invalidateCachedConnection()
                    continue
                }
                throw error
            } catch {
                throw error
            }
        }
        throw lastError
    }

    private func performNumberValueOperation(
        operationName: String,
        operationTimeout: TimeInterval? = nil,
        _ operation: (ExoSentryHelperXPCProtocol, @escaping (NSNumber?, NSString?) -> Void) -> Void
    ) throws -> NSNumber {
        var lastError: Error = PrivilegedClientError.timeout
        for attempt in 1...maxAttempts {
            do {
                return try performNumberValueOperationOnce(operationName: operationName, attempt: attempt, operationTimeout: operationTimeout, operation)
            } catch let error as PrivilegedClientError {
                lastError = error
                if error.isConnectionError, attempt < maxAttempts {
                    invalidateCachedConnection()
                    continue
                }
                throw error
            } catch {
                throw error
            }
        }
        throw lastError
    }

    private func performStringPairValueOperation(
        operationName: String,
        _ operation: (ExoSentryHelperXPCProtocol, @escaping (NSString, NSString?) -> Void) -> Void
    ) throws -> (NSString, NSString) {
        var lastError: Error = PrivilegedClientError.timeout
        for attempt in 1...maxAttempts {
            do {
                return try performStringPairValueOperationOnce(operationName: operationName, attempt: attempt, operation)
            } catch let error as PrivilegedClientError {
                lastError = error
                if error.isConnectionError, attempt < maxAttempts {
                    invalidateCachedConnection()
                    continue
                }
                throw error
            } catch {
                throw error
            }
        }
        throw lastError
    }

    private func performVoidOperationOnce(
        operationName: String,
        attempt: Int,
        operationTimeout: TimeInterval? = nil,
        _ operation: (ExoSentryHelperXPCProtocol, @escaping (NSString?) -> Void) -> Void
    ) throws {
        let semaphore = DispatchSemaphore(value: 0)
        let box = OnceResult<Void>(default: .failure(PrivilegedClientError.timeout))
        let connection = getOrCreateConnection()
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
            invalidateCachedConnection()
            throw PrivilegedClientError.connectionUnavailable
        }

        operation(proxy) { [box] errorMessage in
            let outcome: Result<Void, Error>
            if let errorMessage {
                outcome = .failure(PrivilegedClientError.operationFailed("\(operationName) failed (attempt \(attempt)): \(errorMessage)"))
            } else {
                outcome = .success(())
            }
            if box.complete(outcome) {
                semaphore.signal()
            }
        }

        let effectiveTimeout = operationTimeout ?? timeoutSeconds
        let waitResult = semaphore.wait(timeout: .now() + effectiveTimeout)
        if waitResult == .timedOut {
            invalidateCachedConnection()
            throw PrivilegedClientError.timeout
        }
        do {
            _ = try box.value.get()
        } catch {
            invalidateCachedConnection()
            throw error
        }
    }

    private func performStringValueOperationOnce(
        operationName: String,
        attempt: Int,
        _ operation: (ExoSentryHelperXPCProtocol, @escaping (NSString) -> Void) -> Void
    ) throws -> NSString {
        let semaphore = DispatchSemaphore(value: 0)
        let box = OnceResult<NSString>(default: .failure(PrivilegedClientError.timeout))
        let connection = getOrCreateConnection()
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
            invalidateCachedConnection()
            throw PrivilegedClientError.connectionUnavailable
        }

        operation(proxy) { [box] value in
            if box.complete(.success(value)) {
                semaphore.signal()
            }
        }

        let waitResult = semaphore.wait(timeout: .now() + timeoutSeconds)
        if waitResult == .timedOut {
            invalidateCachedConnection()
            throw PrivilegedClientError.timeout
        }
        do {
            return try box.value.get()
        } catch {
            invalidateCachedConnection()
            throw error
        }
    }

    private func performNumberValueOperationOnce(
        operationName: String,
        attempt: Int,
        operationTimeout: TimeInterval? = nil,
        _ operation: (ExoSentryHelperXPCProtocol, @escaping (NSNumber?, NSString?) -> Void) -> Void
    ) throws -> NSNumber {
        let semaphore = DispatchSemaphore(value: 0)
        let box = OnceResult<NSNumber>(default: .failure(PrivilegedClientError.timeout))
        let connection = getOrCreateConnection()
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
            invalidateCachedConnection()
            throw PrivilegedClientError.connectionUnavailable
        }

        operation(proxy) { [box] value, errorMessage in
            let outcome: Result<NSNumber, Error>
            if let errorMessage {
                outcome = .failure(PrivilegedClientError.operationFailed("\(operationName) failed (attempt \(attempt)): \(errorMessage)"))
            } else if let value {
                outcome = .success(value)
            } else {
                outcome = .failure(PrivilegedClientError.operationFailed("\(operationName) missing value (attempt \(attempt))"))
            }
            if box.complete(outcome) {
                semaphore.signal()
            }
        }

        let effectiveTimeout = operationTimeout ?? timeoutSeconds
        let waitResult = semaphore.wait(timeout: .now() + effectiveTimeout)
        if waitResult == .timedOut {
            invalidateCachedConnection()
            throw PrivilegedClientError.timeout
        }
        do {
            return try box.value.get()
        } catch {
            invalidateCachedConnection()
            throw error
        }
    }

    private func performStringPairValueOperationOnce(
        operationName: String,
        attempt: Int,
        _ operation: (ExoSentryHelperXPCProtocol, @escaping (NSString, NSString?) -> Void) -> Void
    ) throws -> (NSString, NSString) {
        let semaphore = DispatchSemaphore(value: 0)
        let box = OnceResult<(NSString, NSString)>(default: .failure(PrivilegedClientError.timeout))
        let connection = getOrCreateConnection()
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
            invalidateCachedConnection()
            throw PrivilegedClientError.connectionUnavailable
        }

        operation(proxy) { [box] value, second in
            if value == "error", let second {
                if box.complete(.failure(PrivilegedClientError.operationFailed("\(operationName) failed (attempt \(attempt)): \(second)"))) {
                    semaphore.signal()
                }
                return
            }

            let other = second ?? ""
            if box.complete(.success((value, other))) {
                semaphore.signal()
            }
        }

        let waitResult = semaphore.wait(timeout: .now() + timeoutSeconds)
        if waitResult == .timedOut {
            invalidateCachedConnection()
            throw PrivilegedClientError.timeout
        }
        do {
            return try box.value.get()
        } catch {
            invalidateCachedConnection()
            throw error
        }
    }
}

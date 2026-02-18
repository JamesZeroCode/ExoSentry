import Foundation
import Network

public enum LocalStatusServerError: Error {
    case failedToStart
}

public final class LocalStatusServer: @unchecked Sendable {
    private let lock = NSLock()
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "ExoSentry.LocalStatusServer")
    private let payloadProvider: @Sendable () async -> StatusPayload

    public init(payloadProvider: @escaping @Sendable () async -> StatusPayload) {
        self.payloadProvider = payloadProvider
    }

    public func start(port: UInt16) throws {
        lock.lock()
        defer { lock.unlock() }
        
        let nwPort = NWEndpoint.Port(rawValue: port) ?? .init(integerLiteral: 1988)
        let newListener = try NWListener(using: .tcp, on: nwPort)
        newListener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        newListener.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                self?.clearListenerThreadSafe()
            } else if case .cancelled = state {
                self?.clearListenerThreadSafe()
            }
        }
        newListener.start(queue: queue)
        self.listener = newListener
    }

    public func stop() {
        lock.lock()
        let currentListener = listener
        listener = nil
        lock.unlock()
        
        currentListener?.cancel()
    }
    
    private func clearListenerThreadSafe() {
        lock.lock()
        listener = nil
        lock.unlock()
    }

    private func handle(connection: NWConnection) {
        if !isLoopback(connection.endpoint) {
            connection.start(queue: queue)
            sendResponse(connection, statusLine: "HTTP/1.1 403 Forbidden", body: Data())
            return
        }

        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }

            let request = String(data: data ?? Data(), encoding: .utf8) ?? ""
            guard let requestLine = request.split(separator: "\n").first else {
                self.sendResponse(connection, statusLine: "HTTP/1.1 400 Bad Request", body: Data())
                return
            }

            let parts = requestLine
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: " ")
            guard parts.count >= 2 else {
                self.sendResponse(connection, statusLine: "HTTP/1.1 400 Bad Request", body: Data())
                return
            }

            let method = String(parts[0])
            let path = String(parts[1])

            guard method == "GET" else {
                self.sendResponse(connection, statusLine: "HTTP/1.1 405 Method Not Allowed", body: Data())
                return
            }

            if path == "/status" {
                Task {
                    let payload = await self.payloadProvider()
                    let encoded = (try? JSONEncoder().encode(payload)) ?? Data("{}".utf8)
                    self.sendResponse(connection, statusLine: "HTTP/1.1 200 OK", body: encoded, contentType: "application/json; charset=utf-8")
                }
                return
            }

            self.sendResponse(connection, statusLine: "HTTP/1.1 404 Not Found", body: Data())
        }
    }

    private func sendResponse(
        _ connection: NWConnection,
        statusLine: String,
        body: Data,
        contentType: String = "text/plain; charset=utf-8"
    ) {
        let headers = "\(statusLine)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var response = Data(headers.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        guard case let .hostPort(host, _) = endpoint else {
            return false
        }
        switch host {
        case .ipv4(let address):
            // IPv4 loopback: entire 127.0.0.0/8 range
            return address.rawValue[address.rawValue.startIndex] == 127
        case .ipv6(let address):
            // IPv6 loopback: ::1
            let raw = address.rawValue
            return raw.count == 16
                && raw[raw.startIndex ..< raw.index(raw.startIndex, offsetBy: 15)].allSatisfy({ $0 == 0 })
                && raw[raw.index(raw.startIndex, offsetBy: 15)] == 1
        case .name(let name, _):
            return name == "localhost"
        @unknown default:
            return false
        }
    }
}

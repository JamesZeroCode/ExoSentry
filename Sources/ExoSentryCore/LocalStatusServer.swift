import Foundation
import Network

public enum LocalStatusServerError: Error {
    case failedToStart
}

public final class LocalStatusServer: @unchecked Sendable {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "ExoSentry.LocalStatusServer")
    private let payloadProvider: @Sendable () async -> StatusPayload

    public init(payloadProvider: @escaping @Sendable () async -> StatusPayload) {
        self.payloadProvider = payloadProvider
    }

    public func start(port: UInt16) throws {
        let nwPort = NWEndpoint.Port(rawValue: port) ?? .init(integerLiteral: 1988)
        let listener = try NWListener(using: .tcp, on: nwPort)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.listener = nil
            default:
                break
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
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
            return address.debugDescription == "127.0.0.1"
        case .ipv6(let address):
            return address.debugDescription == "::1"
        case .name(let name, _):
            return name == "localhost"
        @unknown default:
            return false
        }
    }
}

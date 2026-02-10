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
        listener.stateUpdateHandler = { _ in }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(connection: NWConnection) {
        if !isLoopback(connection.endpoint) {
            let response = Data("HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n".utf8)
            connection.start(queue: queue)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
            return
        }

        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }

            let request = String(data: data ?? Data(), encoding: .utf8) ?? ""
            if request.hasPrefix("GET /status") {
                Task {
                    let payload = await self.payloadProvider()
                    let encoded = (try? JSONEncoder().encode(payload)) ?? Data("{}".utf8)
                    let headers = "HTTP/1.1 200 OK\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(encoded.count)\r\nConnection: close\r\n\r\n"
                    var response = Data(headers.utf8)
                    response.append(encoded)
                    connection.send(content: response, completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }
                return
            }

            let response = Data("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n".utf8)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
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

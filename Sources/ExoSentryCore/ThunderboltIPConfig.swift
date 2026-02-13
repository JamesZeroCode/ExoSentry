import Foundation

public struct ThunderboltIPConfig: Codable, Sendable, Identifiable, Equatable {
    public var id: String { service }
    public var service: String
    public var ip: String
    public var subnet: String
    public var router: String
    public var enabled: Bool

    public init(service: String, ip: String, subnet: String = "255.255.255.0", router: String = "", enabled: Bool = true) {
        self.service = service
        self.ip = ip
        self.subnet = subnet
        self.router = router
        self.enabled = enabled
    }

    public static let defaultConfigs: [ThunderboltIPConfig] = [
        ThunderboltIPConfig(service: "EXO Thunderbolt 1", ip: "10.0.0.1"),
        ThunderboltIPConfig(service: "EXO Thunderbolt 2", ip: "10.0.0.2"),
        ThunderboltIPConfig(service: "EXO Thunderbolt 3", ip: "10.0.0.3"),
        ThunderboltIPConfig(service: "EXO Thunderbolt 4", ip: "10.0.0.4"),
    ]
}

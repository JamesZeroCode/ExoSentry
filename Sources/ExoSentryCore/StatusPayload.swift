import Foundation

public struct StatusPayload: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let status: GuardStatus
    public let mode: OperatingMode
    public let tempC: Double?
    public let isCharging: Bool
    public let lidClosed: Bool
    public let targetProcess: String
    public let targetProcessRunning: Bool
    public let networkState: NetworkState
    public let lastUpdated: String

    public init(
        schemaVersion: String = "1.0",
        status: GuardStatus,
        mode: OperatingMode,
        tempC: Double?,
        isCharging: Bool,
        lidClosed: Bool,
        targetProcess: String,
        targetProcessRunning: Bool,
        networkState: NetworkState,
        lastUpdated: String
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.mode = mode
        self.tempC = tempC
        self.isCharging = isCharging
        self.lidClosed = lidClosed
        self.targetProcess = targetProcess
        self.targetProcessRunning = targetProcessRunning
        self.networkState = networkState
        self.lastUpdated = lastUpdated
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case status
        case mode
        case tempC = "temp_c"
        case isCharging = "is_charging"
        case lidClosed = "lid_closed"
        case targetProcess = "target_process"
        case targetProcessRunning = "target_process_running"
        case networkState = "network_state"
        case lastUpdated = "last_updated"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(status, forKey: .status)
        try container.encode(mode, forKey: .mode)
        try container.encode(tempC, forKey: .tempC)
        try container.encode(isCharging, forKey: .isCharging)
        try container.encode(lidClosed, forKey: .lidClosed)
        try container.encode(targetProcess, forKey: .targetProcess)
        try container.encode(targetProcessRunning, forKey: .targetProcessRunning)
        try container.encode(networkState, forKey: .networkState)
        try container.encode(lastUpdated, forKey: .lastUpdated)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(String.self, forKey: .schemaVersion)
        status = try container.decode(GuardStatus.self, forKey: .status)
        mode = try container.decode(OperatingMode.self, forKey: .mode)
        tempC = try container.decodeIfPresent(Double.self, forKey: .tempC)
        isCharging = try container.decode(Bool.self, forKey: .isCharging)
        lidClosed = try container.decode(Bool.self, forKey: .lidClosed)
        targetProcess = try container.decode(String.self, forKey: .targetProcess)
        targetProcessRunning = try container.decode(Bool.self, forKey: .targetProcessRunning)
        networkState = try container.decode(NetworkState.self, forKey: .networkState)
        lastUpdated = try container.decode(String.self, forKey: .lastUpdated)
    }
}

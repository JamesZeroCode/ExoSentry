import Foundation

public enum NetworkState: String, Codable, Sendable {
    case ok
    case lanLost = "lan_lost"
    case wanLost = "wan_lost"
    case offline
}

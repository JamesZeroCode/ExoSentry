import Foundation

public enum GuardStatus: String, Codable, Sendable {
    case active
    case paused
    case degraded
    case overheatTrip = "overheat_trip"
}

import Foundation

public enum ISO8601Timestamp {
    private static let formatter: ISO8601DateFormatter = {
        ISO8601DateFormatter()
    }()

    public static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}

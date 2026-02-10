import Foundation
import XCTest
@testable import ExoSentryCore

final class SecureLoggerTests: XCTestCase {
    func testRedactsSensitiveMetadataBeforeWriting() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("log")
        let logger = SecureLogger(fileURL: tempURL)

        logger.log(.error, operation: "auth", message: "failed", metadata: ["token": "abcdef123456"])

        let content = try String(contentsOf: tempURL)
        XCTAssertTrue(content.contains("ab***56"))
        XCTAssertFalse(content.contains("abcdef123456"))
    }
}

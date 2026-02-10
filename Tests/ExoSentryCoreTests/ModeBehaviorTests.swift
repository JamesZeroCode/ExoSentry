import XCTest
@testable import ExoSentryCore

final class ModeBehaviorTests: XCTestCase {
    func testClusterModeBehaviorMatrix() {
        let behavior = ModeBehavior.forMode(.cluster)

        XCTAssertTrue(behavior.preventSystemSleep)
        XCTAssertTrue(behavior.preventDisplaySleep)
        XCTAssertTrue(behavior.allowClamshell)
        XCTAssertTrue(behavior.networkGuardEnabled)
    }

    func testStandardModeBehaviorMatrix() {
        let behavior = ModeBehavior.forMode(.standard)

        XCTAssertTrue(behavior.preventSystemSleep)
        XCTAssertFalse(behavior.preventDisplaySleep)
        XCTAssertFalse(behavior.allowClamshell)
        XCTAssertFalse(behavior.networkGuardEnabled)
    }
}

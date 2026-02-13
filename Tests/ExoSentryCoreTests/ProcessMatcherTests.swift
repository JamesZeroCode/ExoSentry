import XCTest
@testable import ExoSentryCore

final class ProcessMatcherTests: XCTestCase {
    func testReturnsFalseWhenNoConfiguredTargets() {
        let matcher = ProcessMatcher()

        let result = matcher.shouldActivateGuard(
            configuredTargets: [],
            runningProcessNames: ["exo"]
        )

        XCTAssertFalse(result)
    }

    func testReturnsTrueWhenAnyConfiguredTargetMatchesRunningProcess() {
        let matcher = ProcessMatcher()

        let result = matcher.shouldActivateGuard(
            configuredTargets: ["python3", "exo"],
            runningProcessNames: ["WindowServer", "exo"]
        )

        XCTAssertTrue(result)
    }

    func testUsesExactMatchNotPrefix() {
        let matcher = ProcessMatcher()

        let result = matcher.shouldActivateGuard(
            configuredTargets: ["exo"],
            runningProcessNames: ["exo-node"]
        )

        XCTAssertFalse(result)
    }

    func testCaseInsensitiveMatching() {
        let matcher = ProcessMatcher()

        XCTAssertTrue(matcher.shouldActivateGuard(
            configuredTargets: ["exo"],
            runningProcessNames: ["EXO"]
        ))
        XCTAssertTrue(matcher.shouldActivateGuard(
            configuredTargets: ["EXO"],
            runningProcessNames: ["exo"]
        ))
        XCTAssertTrue(matcher.shouldActivateGuard(
            configuredTargets: ["Exo"],
            runningProcessNames: ["EXO"]
        ))
    }

    func testMatchedTargetCaseInsensitive() {
        let matcher = ProcessMatcher()

        let result = matcher.matchedTarget(
            configuredTargets: ["exo"],
            runningProcessNames: ["EXO"]
        )
        XCTAssertEqual(result, "exo")
    }
}

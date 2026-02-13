import XCTest
@testable import ExoSentryCore

final class ProcessControllerTests: XCTestCase {

    // MARK: - ProcessControlError Equatable

    func testCommandFailedEqualWithSameCode() {
        XCTAssertEqual(
            ProcessControlError.commandFailed(1),
            ProcessControlError.commandFailed(1)
        )
    }

    func testCommandFailedNotEqualWithDifferentCode() {
        XCTAssertNotEqual(
            ProcessControlError.commandFailed(1),
            ProcessControlError.commandFailed(2)
        )
    }

    func testLaunchFailedEqualToItself() {
        XCTAssertEqual(
            ProcessControlError.launchFailed,
            ProcessControlError.launchFailed
        )
    }

    func testCommandFailedNotEqualToLaunchFailed() {
        XCTAssertNotEqual(
            ProcessControlError.commandFailed(1),
            ProcessControlError.launchFailed
        )
    }

    // MARK: - Empty string handling

    func testTerminateProcessWithEmptyStringDoesNotThrow() throws {
        let controller = SystemProcessController()
        XCTAssertNoThrow(try controller.terminateProcess(named: ""))
    }

    func testTerminateProcessWithWhitespaceDoesNotThrow() throws {
        let controller = SystemProcessController()
        XCTAssertNoThrow(try controller.terminateProcess(named: "   "))
    }

    func testForceTerminateProcessWithEmptyStringDoesNotThrow() throws {
        let controller = SystemProcessController()
        XCTAssertNoThrow(try controller.forceTerminateProcess(named: ""))
    }

    func testForceTerminateProcessWithWhitespaceDoesNotThrow() throws {
        let controller = SystemProcessController()
        XCTAssertNoThrow(try controller.forceTerminateProcess(named: "  \t "))
    }

    func testLaunchProcessWithEmptyStringDoesNotThrow() throws {
        let controller = SystemProcessController()
        XCTAssertNoThrow(try controller.launchProcess(named: ""))
    }

    func testLaunchProcessWithWhitespaceDoesNotThrow() throws {
        let controller = SystemProcessController()
        XCTAssertNoThrow(try controller.launchProcess(named: " \n "))
    }

    func testLaunchCommandWithEmptyStringDoesNotThrow() throws {
        let controller = SystemProcessController()
        XCTAssertNoThrow(try controller.launchCommand(""))
    }

    func testLaunchCommandWithWhitespaceDoesNotThrow() throws {
        let controller = SystemProcessController()
        XCTAssertNoThrow(try controller.launchCommand("   "))
    }

    // MARK: - terminateProcess tolerates non-existent process

    func testTerminateNonExistentProcessDoesNotThrow() throws {
        let controller = SystemProcessController()
        // pkill returns 1 when no matching process is found; this should not throw.
        XCTAssertNoThrow(
            try controller.terminateProcess(named: "ExoSentry_NoSuchProcess_\(UUID().uuidString.prefix(8))")
        )
    }

    // MARK: - launchCommand succeeds with simple command

    func testLaunchCommandEchoDoesNotThrow() throws {
        let controller = SystemProcessController()
        XCTAssertNoThrow(try controller.launchCommand("echo test"))
    }
}

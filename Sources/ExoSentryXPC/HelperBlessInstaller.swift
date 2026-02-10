import Foundation
import ServiceManagement

public protocol HelperBlessInstalling: Sendable {
    func installPrivilegedHelper() throws
}

public enum HelperBlessError: Error, Equatable {
    case registrationFailed(String)
}

extension HelperBlessError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .registrationFailed(let message):
            return "Helper 注册失败：\(message)"
        }
    }
}

public struct HelperBlessInstaller: HelperBlessInstalling {
    private let plistName: String

    public init(plistName: String = "com.exosentry.helper.plist") {
        self.plistName = plistName
    }

    public func installPrivilegedHelper() throws {
        let service = SMAppService.daemon(plistName: plistName)
        do {
            try service.register()
        } catch {
            throw HelperBlessError.registrationFailed(error.localizedDescription)
        }
    }
}

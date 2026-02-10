import Foundation

protocol WiFiControlling {
    func restartWiFi() throws
}

enum WiFiControlError: Error, Equatable {
    case interfaceNotFound
    case commandFailed(Int32)
}

struct SystemWiFiController: WiFiControlling {
    func restartWiFi() throws {
        let interface = try wifiInterfaceName()
        try setPower(interface: interface, on: false)
        try setPower(interface: interface, on: true)
    }

    private func wifiInterfaceName() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = ["-listallhardwareports"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw WiFiControlError.commandFailed(process.terminationStatus)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""

        let lines = text.split(separator: "\n").map(String.init)
        for index in lines.indices {
            if lines[index].contains("Hardware Port: Wi-Fi") || lines[index].contains("Hardware Port: AirPort") {
                let next = lines.dropFirst(index + 1).first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("Device:") }
                if let next {
                    return next.replacingOccurrences(of: "Device:", with: "").trimmingCharacters(in: .whitespaces)
                }
            }
        }
        throw WiFiControlError.interfaceNotFound
    }

    private func setPower(interface: String, on: Bool) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = ["-setairportpower", interface, on ? "on" : "off"]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw WiFiControlError.commandFailed(process.terminationStatus)
        }
    }
}

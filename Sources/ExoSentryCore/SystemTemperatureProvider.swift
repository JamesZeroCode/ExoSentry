import Foundation

public protocol TemperatureProviding: Sendable {
    func currentTemperatureC() -> Double?
}

public struct PowermetricsTemperatureProvider: TemperatureProviding {
    public init() {}

    public func currentTemperatureC() -> Double? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/powermetrics")
        process.arguments = ["-n", "1", "-s", "smc"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            // Read stdout BEFORE waitUntilExit to avoid pipe buffer deadlock.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return nil
            }
            guard let output = String(data: data, encoding: .utf8) else {
                return nil
            }
            return parseTemperature(from: output)
        } catch {
            return nil
        }
    }

    private func parseTemperature(from text: String) -> Double? {
        for line in text.split(separator: "\n") {
            let row = String(line)
            if row.localizedCaseInsensitiveContains("temperature"), row.contains("C") {
                let matches = row
                    .components(separatedBy: CharacterSet(charactersIn: "0123456789." ).inverted)
                    .filter { !$0.isEmpty }
                if let number = matches.first, let value = Double(number) {
                    return value
                }
            }
        }
        return nil
    }
}

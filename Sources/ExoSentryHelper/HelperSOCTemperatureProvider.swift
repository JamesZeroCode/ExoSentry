import Foundation

protocol SOCTemperatureProviding {
    func currentTemperatureC() throws -> Double
}

enum SOCTemperatureError: Error, Equatable {
    case commandFailed(Int32)
    case parseFailed
}

struct PowermetricsSOCTemperatureProvider: SOCTemperatureProviding {
    func currentTemperatureC() throws -> Double {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/powermetrics")
        process.arguments = ["-n", "1", "-s", "cpu_power"]
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw SOCTemperatureError.commandFailed(process.terminationStatus)
        }

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8),
              let temperature = parseTemperature(output) else {
            throw SOCTemperatureError.parseFailed
        }

        return temperature
    }

    private func parseTemperature(_ text: String) -> Double? {
        let lines = text.split(separator: "\n").map(String.init)
        let primary = lines.first { line in
            let lower = line.lowercased()
            return lower.contains("die temperature") || lower.contains("cpu temperature") || lower.contains("soc temperature")
        }
        if let primary, let value = extractCelsius(primary) {
            return value
        }

        for line in lines {
            if let value = extractCelsius(line) {
                return value
            }
        }
        return nil
    }

    private func extractCelsius(_ line: String) -> Double? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        let regex = try? NSRegularExpression(pattern: "([0-9]+(?:\\.[0-9]+)?)\\s*C", options: [])
        guard let match = regex?.firstMatch(in: line, options: [], range: range),
              let valueRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return Double(line[valueRange])
    }
}

import Foundation

public struct LiveVPNStatusProvider: VPNStatusProvider {
    private let statusSource: any VPNServiceStatusSource

    public init() {
        self.init(statusSource: ScutilVPNServiceStatusSource())
    }

    init(statusSource: any VPNServiceStatusSource) {
        self.statusSource = statusSource
    }

    public func currentStatus() async -> VPNStatusSnapshot {
        let output = (try? statusSource.connectionListOutput()) ?? ""
        let serviceNames = Self.connectedServiceNames(from: output)

        return VPNStatusSnapshot(
            isActive: serviceNames.isEmpty == false,
            interfaceNames: [],
            serviceNames: serviceNames
        )
    }

    static func connectedServiceNames(from output: String) -> [String] {
        let names = output
            .split(whereSeparator: \.isNewline)
            .compactMap { connectedServiceName(from: String($0)) }

        return Array(Set(names)).sorted()
    }

    private static func connectedServiceName(from line: String) -> String? {
        guard line.contains("(Connected)") else {
            return nil
        }

        guard let firstQuote = line.firstIndex(of: "\"") else {
            return nil
        }

        let remainder = line[line.index(after: firstQuote)...]
        guard let secondQuote = remainder.firstIndex(of: "\"") else {
            return nil
        }

        let name = String(remainder[..<secondQuote]).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}

protocol VPNServiceStatusSource: Sendable {
    func connectionListOutput() throws -> String
}

private struct ScutilVPNServiceStatusSource: VPNServiceStatusSource {
    func connectionListOutput() throws -> String {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
        process.arguments = ["--nc", "list"]
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8) ?? "scutil --nc list failed"
            throw VPNServiceStatusSourceError.commandFailed(message)
        }

        return String(data: outputData, encoding: .utf8) ?? ""
    }
}

private enum VPNServiceStatusSourceError: Error {
    case commandFailed(String)
}

import Foundation

/// Reads and writes `SleepDisabled` through `/usr/bin/pmset`, by absolute path and without a shell.
/// Only the privileged helper uses this; it needs root to write.
public struct PmsetSleepDisabledSetting: SleepDisabledSetting {
    public static let pmsetPath = "/usr/bin/pmset"

    public struct CommandError: Error, LocalizedError {
        public let status: Int32

        public var errorDescription: String? {
            "pmset exited with status \(status)."
        }
    }

    public init() {}

    public func isSleepDisabled() throws -> Bool {
        try Self.parseSleepDisabled(Self.run(["-g"]))
    }

    public func setSleepDisabled(_ isDisabled: Bool) throws {
        _ = try Self.run(["-a", "disablesleep", isDisabled ? "1" : "0"])
    }

    /// Finds the `SleepDisabled` line of `pmset -g`. A missing line means the setting is off.
    static func parseSleepDisabled(_ output: String) -> Bool {
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            if fields.count >= 2, fields[0] == "SleepDisabled" {
                return fields[1] == "1"
            }
        }
        return false
    }

    private static func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pmsetPath)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        // Read before waiting, so a full pipe cannot block pmset.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CommandError(status: process.terminationStatus)
        }
        return String(decoding: data, as: UTF8.self)
    }
}

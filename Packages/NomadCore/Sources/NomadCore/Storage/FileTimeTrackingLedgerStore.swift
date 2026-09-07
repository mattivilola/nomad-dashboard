import Foundation

public actor FileTimeTrackingLedgerStore: TimeTrackingLedgerStore, TimeTrackingHeartbeatStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() async throws -> TimeTrackingLedger {
        try ensureDirectory()

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .empty
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let ledger = try decoder.decode(TimeTrackingLedger.self, from: data)
            var normalizedLedger = TimeTrackingLedger(
                entries: TimeTrackingLedger.normalizedEntries(ledger.entries),
                interruptions: TimeTrackingLedger.normalizedInterruptions(ledger.interruptions),
                runtimeState: ledger.runtimeState
            )
            if let heartbeat = try? await loadHeartbeat(), heartbeat.openEntryID == normalizedLedger.runtimeState.openEntryID {
                normalizedLedger.runtimeState.lastHeartbeatAt = max(
                    normalizedLedger.runtimeState.lastHeartbeatAt ?? .distantPast,
                    heartbeat.recordedAt
                )
            }
            return normalizedLedger
        } catch {
            let backupURL = try recoveredLedgerBackupURL()
            try FileManager.default.moveItem(at: fileURL, to: backupURL)
            throw FileTimeTrackingLedgerStoreError.recoveredCorruptLedger(
                sourceURL: fileURL,
                backupURL: backupURL,
                underlyingError: error
            )
        }
    }

    public func save(_ ledger: TimeTrackingLedger) async throws {
        try ensureDirectory()
        let normalizedLedger = TimeTrackingLedger(
            entries: TimeTrackingLedger.normalizedEntries(ledger.entries),
            interruptions: TimeTrackingLedger.normalizedInterruptions(ledger.interruptions),
            runtimeState: ledger.runtimeState
        )
        do {
            let data = try encoder.encode(normalizedLedger)
            try data.write(to: fileURL, options: [.atomic])
            try await clearHeartbeat()
        } catch {
            throw FileTimeTrackingLedgerStoreError.saveFailed(
                fileURL: fileURL,
                underlyingError: error
            )
        }
    }

    public func reset() async throws {
        try ensureDirectory()
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try await clearHeartbeat()
    }

    public func loadHeartbeat() async throws -> TimeTrackingHeartbeat? {
        let heartbeatURL = heartbeatURL
        guard FileManager.default.fileExists(atPath: heartbeatURL.path) else { return nil }
        return try decoder.decode(TimeTrackingHeartbeat.self, from: Data(contentsOf: heartbeatURL))
    }

    public func saveHeartbeat(_ heartbeat: TimeTrackingHeartbeat) async throws {
        try ensureDirectory()
        do {
            try encoder.encode(heartbeat).write(to: heartbeatURL, options: [.atomic])
        } catch {
            throw FileTimeTrackingLedgerStoreError.saveFailed(fileURL: heartbeatURL, underlyingError: error)
        }
    }

    public func clearHeartbeat() async throws {
        let heartbeatURL = heartbeatURL
        if FileManager.default.fileExists(atPath: heartbeatURL.path) {
            try FileManager.default.removeItem(at: heartbeatURL)
        }
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private var heartbeatURL: URL {
        fileURL.deletingPathExtension().appendingPathExtension("heartbeat.json")
    }

    private func recoveredLedgerBackupURL() throws -> URL {
        let timestamp = Self.recoveryTimestampFormatter.string(from: .now)
        let recoveredFilename = "\(fileURL.deletingPathExtension().lastPathComponent).recovered-\(timestamp).\(fileURL.pathExtension)"
        return fileURL.deletingLastPathComponent().appendingPathComponent(recoveredFilename)
    }

    private static let recoveryTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }()
}

public enum FileTimeTrackingLedgerStoreError: LocalizedError {
    case recoveredCorruptLedger(sourceURL: URL, backupURL: URL, underlyingError: Error)
    case saveFailed(fileURL: URL, underlyingError: Error)

    public var errorDescription: String? {
        switch self {
        case let .recoveredCorruptLedger(_, backupURL, underlyingError):
            "Recovered unreadable time tracking data and backed it up as \(backupURL.lastPathComponent). \(underlyingError.localizedDescription)"
        case let .saveFailed(fileURL, underlyingError):
            "Failed to save time tracking data to \(fileURL.lastPathComponent). \(underlyingError.localizedDescription)"
        }
    }
}

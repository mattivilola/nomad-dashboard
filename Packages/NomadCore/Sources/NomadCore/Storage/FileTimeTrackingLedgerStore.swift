import Foundation

public actor FileTimeTrackingLedgerStore: TimeTrackingLedgerStore {
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

        let data = try Data(contentsOf: fileURL)
        let ledger = try decoder.decode(TimeTrackingLedger.self, from: data)
        return TimeTrackingLedger(
            entries: TimeTrackingLedger.normalizedEntries(ledger.entries),
            runtimeState: ledger.runtimeState
        )
    }

    public func save(_ ledger: TimeTrackingLedger) async throws {
        try ensureDirectory()
        let normalizedLedger = TimeTrackingLedger(
            entries: TimeTrackingLedger.normalizedEntries(ledger.entries),
            runtimeState: ledger.runtimeState
        )
        let data = try encoder.encode(normalizedLedger)
        try data.write(to: fileURL, options: [.atomic])
    }

    public func reset() async throws {
        try ensureDirectory()
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
}

import Foundation

/// Keeps the last `maximumRecords` changes of the Mac's local time zone in one small JSON file in the app's
/// support directory. Local only: it is never sent anywhere and is cleared with the visited places.
public actor FileTimeZoneShiftStore: TimeZoneShiftStore {
    /// Enough to see a trip with stopovers; older records are dropped.
    public static let maximumRecords = 10

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func loadAll() async throws -> [TimeZoneShiftRecord] {
        try loadPersistedRecords()
    }

    public func record(_ record: TimeZoneShiftRecord) async throws {
        var records = try loadPersistedRecords()
        if let latest = records.last, latest.identifier == record.identifier, latest.offsetSeconds == record.offsetSeconds {
            return
        }

        records.append(record)
        records.sort { $0.date < $1.date }
        try persist(Array(records.suffix(Self.maximumRecords)))
    }

    public func reset() async throws {
        try ensureDirectory()
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private func persist(_ records: [TimeZoneShiftRecord]) throws {
        try ensureDirectory()
        try encoder.encode(records).write(to: fileURL, options: [.atomic])
    }

    private func loadPersistedRecords() throws -> [TimeZoneShiftRecord] {
        try ensureDirectory()

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let records = try decoder.decode([TimeZoneShiftRecord].self, from: Data(contentsOf: fileURL))
        return records.sorted { $0.date < $1.date }
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
}

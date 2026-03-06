import Foundation

public actor FileMetricHistoryStore: MetricHistoryStore {
    private let fileURL: URL
    private let retentionHours: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL, retentionHours: Int) {
        self.fileURL = fileURL
        self.retentionHours = retentionHours
    }

    public func loadAll() async throws -> [MetricSeriesKind: [MetricPoint]] {
        try ensureDirectory()

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }

        let data = try Data(contentsOf: fileURL)
        let decoded = try decoder.decode([MetricSeriesKind: [MetricPoint]].self, from: data)
        return trim(decoded)
    }

    public func append(_ point: MetricPoint, to series: MetricSeriesKind) async throws {
        var history = try await loadAll()
        history[series, default: []].append(point)
        history = trim(history)
        try persist(history)
    }

    public func reset() async throws {
        try ensureDirectory()
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private func trim(_ history: [MetricSeriesKind: [MetricPoint]]) -> [MetricSeriesKind: [MetricPoint]] {
        let earliestTimestamp = Date().addingTimeInterval(TimeInterval(-retentionHours * 3_600))
        return history.mapValues { points in
            points
                .filter { $0.timestamp >= earliestTimestamp }
                .sorted { $0.timestamp < $1.timestamp }
        }
    }

    private func persist(_ history: [MetricSeriesKind: [MetricPoint]]) throws {
        try ensureDirectory()
        let data = try encoder.encode(history)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
}


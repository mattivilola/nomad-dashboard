import Foundation

public actor FileMetricHistoryStore: MetricHistoryStore, MetricHistoryFlushable {
    private let fileURL: URL
    private var retentionHours: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var cachedHistory: [MetricSeriesKind: [MetricPoint]]?
    private var flushTask: Task<Void, Never>?
    private var isDirty = false
    private let flushDelay: Duration

    public init(fileURL: URL, retentionHours: Int, flushDelay: Duration = .seconds(5)) {
        self.fileURL = fileURL
        self.retentionHours = retentionHours
        self.flushDelay = flushDelay
    }

    public func loadAll() async throws -> [MetricSeriesKind: [MetricPoint]] {
        try loadHistoryIfNeeded()
        return cachedHistory ?? [:]
    }

    public func append(_ point: MetricPoint, to series: MetricSeriesKind) async throws {
        try loadHistoryIfNeeded()
        var history = cachedHistory ?? [:]
        history[series, default: []].append(point)
        history = trim(history)
        cachedHistory = history
        isDirty = true
        scheduleFlush()
    }

    public func flush() async throws {
        flushTask?.cancel()
        flushTask = nil
        guard isDirty else { return }
        try persist(cachedHistory ?? [:])
        isDirty = false
    }

    public func reset() async throws {
        flushTask?.cancel()
        flushTask = nil
        cachedHistory = [:]
        isDirty = false
        try ensureDirectory()
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    public func setRetentionHours(_ retentionHours: Int) async throws {
        self.retentionHours = retentionHours
        try loadHistoryIfNeeded()
        cachedHistory = trim(cachedHistory ?? [:])
        isDirty = true
        try await flush()
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

    private func loadPersistedHistory() throws -> [MetricSeriesKind: [MetricPoint]] {
        try ensureDirectory()

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([MetricSeriesKind: [MetricPoint]].self, from: data)
    }

    private func loadHistoryIfNeeded() throws {
        guard cachedHistory == nil else { return }
        cachedHistory = try trim(loadPersistedHistory())
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        let delay = flushDelay
        flushTask = Task { [weak self, delay] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            try? await self?.flush()
        }
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
}

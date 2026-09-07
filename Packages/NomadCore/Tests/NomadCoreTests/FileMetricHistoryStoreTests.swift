import Foundation
import NomadCore
import Testing

struct FileMetricHistoryStoreTests {
    @Test
    func persistsAndLoadsHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = FileMetricHistoryStore(fileURL: directory.appendingPathComponent("history.json"), retentionHours: 24)

        try await store.append(MetricPoint(timestamp: .now, value: 12), to: .downloadMbps)

        let history = try await store.loadAll()
        #expect(history[.downloadMbps]?.count == 1)
    }

    @Test
    func updatingRetentionPrunesPersistedHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = FileMetricHistoryStore(fileURL: directory.appendingPathComponent("history.json"), retentionHours: 24)

        try await store.append(
            MetricPoint(timestamp: .now.addingTimeInterval(-12 * 3_600), value: 8),
            to: .downloadMbps
        )
        try await store.append(MetricPoint(timestamp: .now, value: 12), to: .downloadMbps)

        try await store.setRetentionHours(6)

        let history = try await store.loadAll()
        #expect(history[.downloadMbps]?.count == 1)
        #expect(history[.downloadMbps]?.first?.value == 12)
    }

    @Test
    func appendUsesLoadedCacheUntilExplicitFlush() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("history.json")
        let store = FileMetricHistoryStore(fileURL: fileURL, retentionHours: 24, flushDelay: .seconds(60))

        try await store.append(MetricPoint(timestamp: .now, value: 8), to: .downloadMbps)
        try await store.append(MetricPoint(timestamp: .now, value: 12), to: .downloadMbps)

        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
        let cached = try await store.loadAll()
        #expect(cached[.downloadMbps]?.map(\.value) == [8, 12])

        try await store.flush()
        let reloaded = FileMetricHistoryStore(fileURL: fileURL, retentionHours: 24)
        let persisted = try await reloaded.loadAll()
        #expect(persisted[.downloadMbps]?.map(\.value) == [8, 12])
    }
}

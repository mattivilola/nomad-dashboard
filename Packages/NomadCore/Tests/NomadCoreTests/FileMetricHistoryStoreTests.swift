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
}


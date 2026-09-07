import Foundation
import NomadCore
import Testing

struct FileTimeTrackingLedgerStoreTests {
    @Test
    func corruptLedgerIsBackedUpAndSubsequentLoadStartsFresh() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("time-tracking-ledger.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not valid json".utf8).write(to: fileURL)

        let store = FileTimeTrackingLedgerStore(fileURL: fileURL)

        await #expect(throws: Error.self) {
            _ = try await store.load()
        }

        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)

        let recoveredFiles = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("time-tracking-ledger.recovered-") }
        #expect(recoveredFiles.count == 1)

        let loaded = try await store.load()
        #expect(loaded == .empty)
    }

    @Test
    func heartbeatUpdatesRecoveryTimestampWithoutRewritingLedger() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("time-tracking-ledger.json")
        let entry = TimeTrackingEntry(startAt: .now.addingTimeInterval(-30), endAt: nil, bucket: .unallocated)
        let store = FileTimeTrackingLedgerStore(fileURL: fileURL)
        try await store.save(TimeTrackingLedger(
            entries: [entry],
            runtimeState: TimeTrackingRuntimeState(activityState: .running, openEntryID: entry.id)
        ))

        let recordedAt = Date.now
        try await store.saveHeartbeat(TimeTrackingHeartbeat(openEntryID: entry.id, recordedAt: recordedAt))
        let loaded = try await store.load()

        #expect(loaded.runtimeState.lastHeartbeatAt == recordedAt)
        try await store.save(loaded)
        let heartbeatAfterSave = try await store.loadHeartbeat()
        #expect(heartbeatAfterSave == nil)
    }
}

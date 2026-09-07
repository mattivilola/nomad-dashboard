import Foundation
import NomadCore
import Testing

struct OfflineDashboardCacheTests {
    @Test
    func roundTripRestoresCachedEssentialsButKeepsLiveNetworkAndPower() async throws {
        let fileURL = temporaryCacheURL()
        let savedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let content = OfflineDashboardContent(snapshot: .preview, savedAt: savedAt, locationKey: "ES:Valencia")
        let cache = OfflineDashboardCache(fileURL: fileURL)

        try await cache.save(content)
        let maybeLoaded = try await cache.load()
        let loaded = try #require(maybeLoaded)
        let liveSnapshot = DashboardSnapshot.placeholder
        let applied = loaded.applying(to: liveSnapshot)

        #expect(loaded.savedAt == savedAt)
        #expect(loaded.locationKey == "ES:Valencia")
        #expect(applied.weather == content.weather)
        #expect(applied.localInfo == content.localInfo)
        #expect(applied.fuelPrices == content.fuelPrices)
        #expect(applied.emergencyCare == content.emergencyCare)
        #expect(applied.marine == content.marine)
        #expect(applied.travelAlerts == content.travelAlerts)
        #expect(applied.network == liveSnapshot.network)
        #expect(applied.power == liveSnapshot.power)
        #expect(applied.fuelDiagnostics == liveSnapshot.fuelDiagnostics)
    }

    @Test
    func unsupportedVersionIsIgnored() async throws {
        let fileURL = temporaryCacheURL()
        let cache = OfflineDashboardCache(fileURL: fileURL)
        try await cache.save(OfflineDashboardContent(snapshot: .preview, savedAt: .now, locationKey: nil))

        var payload = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any])
        payload["version"] = 999
        try JSONSerialization.data(withJSONObject: payload).write(to: fileURL, options: [.atomic])

        let loaded = try await cache.load()
        #expect(loaded == nil)
    }

    @Test
    func corruptCacheReportsErrorWithoutDeletingFile() async throws {
        let fileURL = temporaryCacheURL()
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not valid json".utf8).write(to: fileURL)
        let cache = OfflineDashboardCache(fileURL: fileURL)

        await #expect(throws: OfflineDashboardCacheError.self) {
            _ = try await cache.load()
        }
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    private func temporaryCacheURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("offline-dashboard.json")
    }
}

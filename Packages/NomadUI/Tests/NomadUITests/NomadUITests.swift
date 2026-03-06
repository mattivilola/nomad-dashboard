import NomadCore
import NomadUI
import Testing

struct NomadUITests {
    @Test
    func previewFixtureExposesDashboardSnapshot() {
        #expect(PreviewFixtures.snapshot.network.downloadHistory.isEmpty == false)
    }

    @Test
    func negativeMinutesFormatAsUnavailable() {
        #expect(NomadFormatters.minutes(-1) == "n/a")
    }
}

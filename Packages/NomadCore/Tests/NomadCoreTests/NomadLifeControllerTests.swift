import Foundation
@testable import NomadCore
import Testing

@Suite("Nomad Life")
@MainActor
struct NomadLifeControllerTests {
    @Test func samplingDeduplicatesPartialSnapshotsAndCachedLatency() {
        var state = NomadLifeSamplingState()
        let connectivity = Date(timeIntervalSince1970: 10)
        let latency = Date(timeIntervalSince1970: 11)
        #expect(state.accept(connectivity: connectivity, latency: latency).accepted)
        #expect(!state.accept(connectivity: connectivity, latency: latency).accepted)
        let refreshedConnectivity = Date(timeIntervalSince1970: 12)
        let partial = state.accept(connectivity: refreshedConnectivity, latency: latency)
        #expect(partial.accepted)
        #expect(!partial.hasNewLatency)
    }

    @Test func timezonePresentationRecognizesDateLineDifference() {
        let date = Date(timeIntervalSince1970: 1_704_067_200)
        let presentation = NomadLifeTimeZonePresentation(homeTimeZoneIdentifier: "Pacific/Honolulu", currentTimeZoneIdentifier: "Pacific/Kiritimati", date: date)
        #expect(!presentation.relativeDayDescription.isEmpty)
        #expect(presentation.homeLabel.contains("Home"))
    }

    @Test func preferencesAndDiaryPersistLocally() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("nomad-life.json")
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let key = "nomad-life-preferences"
        let controller = NomadLifeController(storageURL: url, preferencesKey: key, defaults: defaults)
        controller.preferences.homeTimeZoneIdentifier = "Europe/Helsinki"
        let entry = NomadLifeConnectionDiaryEntry(startedAt: .now, endedAt: .now, latitude: 1, longitude: 1, suggestedName: "Near test", sampleCount: 3, averageLatencyMilliseconds: 20, disconnectCount: 0)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode([entry]).write(to: url)
        let reloaded = NomadLifeController(storageURL: url, preferencesKey: key, defaults: defaults)
        try await Task.sleep(for: .milliseconds(80))
        #expect(reloaded.preferences.homeTimeZoneIdentifier == "Europe/Helsinki")
        #expect(reloaded.entries.first?.displayName == "Near test")
    }

    @Test func editingANoteDoesNotConfirmASuggestedVenue() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("nomad-life.json")
        let entry = NomadLifeConnectionDiaryEntry(startedAt: .now, endedAt: .now, latitude: 1, longitude: 1, suggestedName: "Near test", sampleCount: 3, averageLatencyMilliseconds: nil, disconnectCount: 0)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode([entry]).write(to: url)
        let controller = try NomadLifeController(storageURL: url, preferencesKey: UUID().uuidString, defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        try await Task.sleep(for: .milliseconds(80))
        controller.updateEntry(id: entry.id, name: "Near test", note: "Good desk", confirmVenue: false)
        #expect(controller.entries.first?.confidence == .suggested)
        #expect(controller.entries.first?.note == "Good desk")
    }
}

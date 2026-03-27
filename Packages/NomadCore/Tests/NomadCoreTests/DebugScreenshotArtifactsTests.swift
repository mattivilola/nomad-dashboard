import Foundation
import NomadCore
import Testing

struct DebugScreenshotArtifactsTests {
    @Test
    func screenshotsDirectoryResolvesFromDebugBundlePath() throws {
        let fileManager = FileManager.default
        let repositoryURL = try makeRepository(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: repositoryURL) }

        let bundleURL = repositoryURL
            .appendingPathComponent("DerivedData", isDirectory: true)
            .appendingPathComponent("Build", isDirectory: true)
            .appendingPathComponent("Products", isDirectory: true)
            .appendingPathComponent("Debug", isDirectory: true)
            .appendingPathComponent("Nomad Dashboard Dev.app", isDirectory: true)
        try fileManager.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let screenshotsURL = try DebugScreenshotArtifacts.screenshotsDirectory(
            bundleURL: bundleURL,
            fileManager: fileManager
        )
        let expectedURL = repositoryURL
            .appendingPathComponent("output", isDirectory: true)
            .appendingPathComponent("screenshots", isDirectory: true)

        #expect(screenshotsURL.standardizedFileURL == expectedURL.standardizedFileURL)
    }

    @Test
    func screenshotsDirectoryUsesRepositorySearchHintWhenBundleLivesOutsideRepository() throws {
        let fileManager = FileManager.default
        let repositoryURL = try makeRepository(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: repositoryURL) }

        let derivedDataRootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let derivedDataURL = derivedDataRootURL
            .appendingPathComponent("Build", isDirectory: true)
            .appendingPathComponent("Products", isDirectory: true)
            .appendingPathComponent("Debug", isDirectory: true)
            .appendingPathComponent("Nomad Dashboard Dev.app", isDirectory: true)
        try fileManager.createDirectory(at: derivedDataURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: derivedDataRootURL) }

        let screenshotsURL = try DebugScreenshotArtifacts.screenshotsDirectory(
            bundleURL: derivedDataURL,
            repositorySearchHint: repositoryURL.appendingPathComponent("App", isDirectory: true),
            fileManager: fileManager
        )
        let expectedURL = repositoryURL
            .appendingPathComponent("output", isDirectory: true)
            .appendingPathComponent("screenshots", isDirectory: true)

        #expect(screenshotsURL.standardizedFileURL == expectedURL.standardizedFileURL)
    }

    @Test
    func screenshotFileURLCreatesDirectoryAndSanitizesWindowTitle() throws {
        let fileManager = FileManager.default
        let repositoryURL = try makeRepository(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: repositoryURL) }

        let bundleURL = repositoryURL
            .appendingPathComponent("DerivedData", isDirectory: true)
            .appendingPathComponent("Build", isDirectory: true)
            .appendingPathComponent("Products", isDirectory: true)
            .appendingPathComponent("Debug", isDirectory: true)
            .appendingPathComponent("Nomad Dashboard Dev.app", isDirectory: true)
        try fileManager.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let timestamp = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 3,
            day: 24,
            hour: 15,
            minute: 42,
            second: 18,
            nanosecond: 123_000_000
        ).date!

        let fileURL = try DebugScreenshotArtifacts.screenshotFileURL(
            windowTitle: "Visited Map / QA #1",
            bundleURL: bundleURL,
            date: timestamp,
            timeZone: TimeZone(secondsFromGMT: 0)!,
            fileManager: fileManager
        )

        #expect(fileURL.lastPathComponent == "2026-03-24_15-42-18-123-visited-map-qa-1.png")

        var isDirectory: ObjCBool = false
        #expect(fileManager.fileExists(atPath: fileURL.deletingLastPathComponent().path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    @Test
    func screenshotFileURLAppendsCounterWhenFilenameAlreadyExists() throws {
        let fileManager = FileManager.default
        let repositoryURL = try makeRepository(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: repositoryURL) }

        let bundleURL = repositoryURL
            .appendingPathComponent("DerivedData", isDirectory: true)
            .appendingPathComponent("Build", isDirectory: true)
            .appendingPathComponent("Products", isDirectory: true)
            .appendingPathComponent("Debug", isDirectory: true)
            .appendingPathComponent("Nomad Dashboard Dev.app", isDirectory: true)
        try fileManager.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let timestamp = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 3,
            day: 24,
            hour: 15,
            minute: 42,
            second: 18,
            nanosecond: 123_000_000
        ).date!

        let firstURL = try DebugScreenshotArtifacts.screenshotFileURL(
            windowTitle: "Dashboard",
            bundleURL: bundleURL,
            date: timestamp,
            timeZone: TimeZone(secondsFromGMT: 0)!,
            fileManager: fileManager
        )
        try Data("first".utf8).write(to: firstURL)

        let secondURL = try DebugScreenshotArtifacts.screenshotFileURL(
            windowTitle: "Dashboard",
            bundleURL: bundleURL,
            date: timestamp,
            timeZone: TimeZone(secondsFromGMT: 0)!,
            fileManager: fileManager
        )

        #expect(firstURL.lastPathComponent == "2026-03-24_15-42-18-123-dashboard.png")
        #expect(secondURL.lastPathComponent == "2026-03-24_15-42-18-123-dashboard-2.png")
    }

    private func makeRepository(fileManager: FileManager) throws -> URL {
        let repositoryURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        let projectURL = repositoryURL.appendingPathComponent("project.yml", isDirectory: false)
        try Data("name: NomadDashboard\n".utf8).write(to: projectURL)
        return repositoryURL
    }
}

import Foundation

public enum DebugScreenshotArtifacts {
    public enum ResolutionError: Error, Equatable {
        case repositoryRootNotFound(bundleURL: URL)
    }

    public static func screenshotsDirectory(
        bundleURL: URL = Bundle.main.bundleURL,
        repositorySearchHint: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let repositoryRoot = try repositoryRoot(
            from: bundleURL,
            repositorySearchHint: repositorySearchHint,
            fileManager: fileManager
        )
        let screenshotsURL = repositoryRoot
            .appendingPathComponent("output", isDirectory: true)
            .appendingPathComponent("screenshots", isDirectory: true)
        try fileManager.createDirectory(at: screenshotsURL, withIntermediateDirectories: true)
        return screenshotsURL
    }

    public static func screenshotFileURL(
        windowTitle: String,
        bundleURL: URL = Bundle.main.bundleURL,
        repositorySearchHint: URL? = nil,
        date: Date = Date(),
        timeZone: TimeZone = .current,
        fileManager: FileManager = .default
    ) throws -> URL {
        let screenshotsURL = try screenshotsDirectory(
            bundleURL: bundleURL,
            repositorySearchHint: repositorySearchHint,
            fileManager: fileManager
        )
        let baseFilename = "\(timestampString(from: date, timeZone: timeZone))-\(sanitizedWindowSlug(from: windowTitle)).png"
        var candidateURL = screenshotsURL.appendingPathComponent(baseFilename, isDirectory: false)

        guard fileManager.fileExists(atPath: candidateURL.path) else {
            return candidateURL
        }

        let baseName = candidateURL.deletingPathExtension().lastPathComponent
        var collisionIndex = 2

        while fileManager.fileExists(atPath: candidateURL.path) {
            candidateURL = screenshotsURL.appendingPathComponent("\(baseName)-\(collisionIndex).png", isDirectory: false)
            collisionIndex += 1
        }

        return candidateURL
    }

    private static func repositoryRoot(
        from bundleURL: URL,
        repositorySearchHint: URL?,
        fileManager: FileManager
    ) throws -> URL {
        for searchStartURL in repositorySearchStartURLs(bundleURL: bundleURL, repositorySearchHint: repositorySearchHint) {
            if let repositoryRoot = repositoryRoot(startingAt: searchStartURL, fileManager: fileManager) {
                return repositoryRoot
            }
        }

        throw ResolutionError.repositoryRootNotFound(bundleURL: bundleURL)
    }

    private static func repositorySearchStartURLs(bundleURL: URL, repositorySearchHint: URL?) -> [URL] {
        var searchStartURLs: [URL] = []
        var seenPaths: Set<String> = []

        for url in [repositorySearchHint, bundleURL] {
            guard let url else {
                continue
            }

            let normalizedURL = (url.hasDirectoryPath ? url : url.deletingLastPathComponent()).standardizedFileURL
            guard seenPaths.insert(normalizedURL.path).inserted else {
                continue
            }
            searchStartURLs.append(normalizedURL)
        }

        return searchStartURLs
    }

    private static func repositoryRoot(startingAt startURL: URL, fileManager: FileManager) -> URL? {
        var currentURL = startURL

        while true {
            if isRepositoryRoot(currentURL, fileManager: fileManager) {
                return currentURL
            }

            let parentURL = currentURL.deletingLastPathComponent()
            guard parentURL.path != currentURL.path else {
                return nil
            }

            currentURL = parentURL
        }
    }

    private static func isRepositoryRoot(_ directoryURL: URL, fileManager: FileManager) -> Bool {
        let projectURL = directoryURL.appendingPathComponent("project.yml", isDirectory: false)
        if fileManager.fileExists(atPath: projectURL.path) {
            return true
        }

        let gitURL = directoryURL.appendingPathComponent(".git", isDirectory: true)
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: gitURL.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func timestampString(from date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        return formatter.string(from: date)
    }

    private static func sanitizedWindowSlug(from windowTitle: String) -> String {
        let components = windowTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.isEmpty == false }

        let slug = components.joined(separator: "-")
        return slug.isEmpty ? "window" : slug
    }
}

import Foundation

public struct NomadStorageNamespace: Equatable, Sendable {
    public let applicationSupportFolderName: String
    public let settingsKey: String

    public init(applicationSupportFolderName: String, settingsKey: String) {
        self.applicationSupportFolderName = applicationSupportFolderName
        self.settingsKey = settingsKey
    }

    public static let production = NomadStorageNamespace(
        applicationSupportFolderName: "Nomad Dashboard",
        settingsKey: "NomadDashboard.AppSettings"
    )

    public static let development = NomadStorageNamespace(
        applicationSupportFolderName: "Nomad Dashboard Dev",
        settingsKey: "NomadDashboard.Dev.AppSettings"
    )
}

public extension FileManager {
    func nomadApplicationSupportDirectory(
        namespace: NomadStorageNamespace = .production,
        baseURL: URL? = nil
    ) throws -> URL {
        let resolvedBaseURL: URL
        if let baseURL {
            resolvedBaseURL = baseURL
        } else if let applicationSupportURL = urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            resolvedBaseURL = applicationSupportURL
        } else {
            throw CocoaError(.fileNoSuchFile)
        }

        let targetURL = resolvedBaseURL.appendingPathComponent(namespace.applicationSupportFolderName, isDirectory: true)
        try createDirectory(at: targetURL, withIntermediateDirectories: true)
        return targetURL
    }
}

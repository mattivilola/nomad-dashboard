import Foundation

public extension FileManager {
    func nomadApplicationSupportDirectory() throws -> URL {
        guard let baseURL = urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        let targetURL = baseURL.appendingPathComponent("Nomad Dashboard", isDirectory: true)
        try createDirectory(at: targetURL, withIntermediateDirectories: true)
        return targetURL
    }
}


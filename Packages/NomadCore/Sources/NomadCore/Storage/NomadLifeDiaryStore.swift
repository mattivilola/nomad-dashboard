import Foundation

actor NomadLifeDiaryStore {
    private let url: URL
    init(url: URL) {
        self.url = url
    }

    func load() throws -> [NomadLifeConnectionDiaryEntry] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([NomadLifeConnectionDiaryEntry].self, from: Data(contentsOf: url))
    }

    func save(_ entries: [NomadLifeConnectionDiaryEntry]) throws {
        let data = try JSONEncoder().encode(entries)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

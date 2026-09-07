import Foundation

actor NomadLifeDiaryStore {
    private let url: URL
    init(url: URL) {
        self.url = url
    }

    func load() -> [NomadLifeConnectionDiaryEntry] {
        guard let data = try? Data(contentsOf: url), let entries = try? JSONDecoder().decode([NomadLifeConnectionDiaryEntry].self, from: data) else { return [] }
        return entries
    }

    func save(_ entries: [NomadLifeConnectionDiaryEntry]) throws {
        let data = try JSONEncoder().encode(entries)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

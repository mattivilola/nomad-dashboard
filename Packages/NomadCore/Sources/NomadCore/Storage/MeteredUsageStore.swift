import Foundation

public actor MeteredUsageStore {
    private let url: URL
    private var state: MeteredPersistentState

    public init(url: URL) {
        self.url = url
        state = Self.load(from: url) ?? MeteredPersistentState()
    }

    public func currentState() -> MeteredPersistentState {
        state
    }

    public func save() throws {
        let data = try JSONEncoder().encode(state)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    public func update(_ mutation: (inout MeteredPersistentState) -> Void) throws {
        mutation(&state)
        try save()
    }

    private static func load(from url: URL) -> MeteredPersistentState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? JSONDecoder().decode(MeteredPersistentState.self, from: Data(contentsOf: url))
    }
}

import Foundation

public actor FileVisitedPlaceEventsStore: VisitedPlaceEventsStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func loadAll() async throws -> [VisitedPlaceEvent] {
        try loadPersistedEvents()
            .sorted { lhs, rhs in
                if lhs.firstObservedAt == rhs.firstObservedAt {
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }

                return lhs.firstObservedAt < rhs.firstObservedAt
            }
    }

    public func record(_ input: VisitedPlaceEventInput) async throws {
        guard let event = VisitedPlaceEvent.from(input) else {
            return
        }

        var events = try loadPersistedEvents()
        let key = event.coalescingKey

        if let index = events.indices.last, events[index].coalescingKey == key {
            events[index] = events[index].merging(input: input)
        } else {
            events.append(event)
        }

        try persist(events)
    }

    public func reset() async throws {
        try ensureDirectory()
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private func persist(_ events: [VisitedPlaceEvent]) throws {
        try ensureDirectory()
        let data = try encoder.encode(events)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func loadPersistedEvents() throws -> [VisitedPlaceEvent] {
        try ensureDirectory()

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([VisitedPlaceEvent].self, from: data)
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
}

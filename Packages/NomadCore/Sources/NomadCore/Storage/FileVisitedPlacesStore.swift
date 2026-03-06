import Foundation

public actor FileVisitedPlacesStore: VisitedPlacesStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func loadAll() async throws -> [VisitedPlace] {
        try loadPersistedPlaces()
            .sorted { lhs, rhs in
                if lhs.lastVisitedAt == rhs.lastVisitedAt {
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }

                return lhs.lastVisitedAt > rhs.lastVisitedAt
            }
    }

    public func record(_ input: VisitedPlaceInput) async throws {
        guard let place = VisitedPlace.from(input) else {
            return
        }

        var places = try loadPersistedPlaces()
        let key = place.id

        if let index = places.firstIndex(where: { $0.id == key }) {
            places[index] = places[index].merging(input: input)
        } else {
            places.append(place)
        }

        try persist(places)
    }

    public func reset() async throws {
        try ensureDirectory()
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private func persist(_ places: [VisitedPlace]) throws {
        try ensureDirectory()
        let data = try encoder.encode(places)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func loadPersistedPlaces() throws -> [VisitedPlace] {
        try ensureDirectory()

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([VisitedPlace].self, from: data)
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
}

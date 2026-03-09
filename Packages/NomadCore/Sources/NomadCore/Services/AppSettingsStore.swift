import Combine
import Foundation

@MainActor
public final class AppSettingsStore: ObservableObject {
    @Published public var settings: AppSettings {
        didSet {
            save()
        }
    }

    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard, key: String = "NomadDashboard.AppSettings") {
        self.defaults = defaults
        self.key = key

        if let data = defaults.data(forKey: key),
           let decoded = try? decoder.decode(AppSettings.self, from: data)
        {
            settings = decoded
        } else {
            settings = AppSettings()
        }
    }

    public func reset() {
        settings = AppSettings()
    }

    private func save() {
        guard let data = try? encoder.encode(settings) else {
            return
        }

        defaults.set(data, forKey: key)
    }
}

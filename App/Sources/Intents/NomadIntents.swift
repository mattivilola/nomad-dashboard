import AppIntents
import NomadCore

// Siri and Shortcuts actions. The answers are plain sentences from `QuickAnswers` (NomadCore), so what
// Siri says is what the widgets and cards show.
//
// None of these intents opens a window: they only read the app's live stores (registered with
// `AppDependencyManager` when the app starts), so `openAppWhenRun` is false. When the app is not
// running the system starts it in the background first, and `IntentSnapshotReader` gives a freshly
// started app a few seconds to collect the readings an answer needs.

struct EmergencyNumberIntent: AppIntent {
    static let title: LocalizedStringResource = "Emergency Number"
    static let description = IntentDescription(
        "Tells you the emergency numbers for the country you're in.",
        categoryName: "Safety"
    )
    static let openAppWhenRun = false

    @Dependency private var snapshotStore: DashboardSnapshotStore

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let sentence = await IntentAnswers.emergencyNumber(snapshotStore: snapshotStore)
        return .result(value: sentence, dialog: "\(sentence)")
    }
}

struct DashboardStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Dashboard Status"
    static let description = IntentDescription(
        "Tells you whether your connection and power are ready, plus your top heads-up.",
        categoryName: "Dashboard"
    )
    static let openAppWhenRun = false

    @Dependency private var snapshotStore: DashboardSnapshotStore
    @Dependency private var settingsStore: AppSettingsStore

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let sentence = await IntentAnswers.dashboardStatus(snapshotStore: snapshotStore, settingsStore: settingsStore)
        return .result(value: sentence, dialog: "\(sentence)")
    }
}

struct NearestEmbassyIntent: AppIntent {
    static let title: LocalizedStringResource = "Nearest Embassy"
    static let description = IntentDescription(
        "Tells you where your nearest embassy or consulate is and your foreign ministry's emergency line.",
        categoryName: "Safety"
    )
    static let openAppWhenRun = false

    @Dependency private var snapshotStore: DashboardSnapshotStore
    @Dependency private var settingsStore: AppSettingsStore

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let sentence = await IntentAnswers.nearestEmbassy(snapshotStore: snapshotStore, settingsStore: settingsStore)
        return .result(value: sentence, dialog: "\(sentence)")
    }
}

struct DaylightIntent: AppIntent {
    static let title: LocalizedStringResource = "Daylight"
    static let description = IntentDescription(
        "Tells you when the sun sets and how much daylight is left, or when it gets light again.",
        categoryName: "Weather"
    )
    static let openAppWhenRun = false

    @Dependency private var snapshotStore: DashboardSnapshotStore

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let sentence = await IntentAnswers.daylight(snapshotStore: snapshotStore)
        return .result(value: sentence, dialog: "\(sentence)")
    }
}

struct SetTravelProfileIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Travel Profile"
    static let description = IntentDescription(
        "Switches Nomad Dashboard between the Nomad and Road trip & RV profiles.",
        categoryName: "Dashboard"
    )
    static let openAppWhenRun = false

    static var parameterSummary: some ParameterSummary {
        Summary("Set travel profile to \(\.$profile)")
    }

    @Parameter(title: "Travel Profile")
    var profile: TravelProfileOption

    @Dependency private var settingsStore: AppSettingsStore

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let selected = profile.travelProfile
        let sentence = IntentAnswers.setTravelProfile(selected, settingsStore: settingsStore)
        return .result(value: selected.title, dialog: "\(sentence)")
    }
}

struct NomadShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .teal

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: EmergencyNumberIntent(),
            phrases: [
                "What's the emergency number in \(.applicationName)",
                "Emergency number in \(.applicationName)",
                "Who do I call in an emergency with \(.applicationName)"
            ],
            shortTitle: "Emergency Number",
            systemImageName: "phone.fill"
        )
        AppShortcut(
            intent: DashboardStatusIntent(),
            phrases: [
                "How am I doing in \(.applicationName)",
                "What's my status in \(.applicationName)",
                "Check \(.applicationName)"
            ],
            shortTitle: "Dashboard Status",
            systemImageName: "checkmark.seal.fill"
        )
        AppShortcut(
            intent: NearestEmbassyIntent(),
            phrases: [
                "Where's my nearest embassy in \(.applicationName)",
                "Find my embassy with \(.applicationName)"
            ],
            shortTitle: "Nearest Embassy",
            systemImageName: "building.columns.fill"
        )
        AppShortcut(
            intent: DaylightIntent(),
            phrases: [
                "When is sunset in \(.applicationName)",
                "How much daylight is left in \(.applicationName)"
            ],
            shortTitle: "Daylight",
            systemImageName: "sunset.fill"
        )
        AppShortcut(
            intent: SetTravelProfileIntent(),
            phrases: [
                "Switch \(.applicationName) to \(\.$profile)",
                "Set my \(.applicationName) travel profile to \(\.$profile)"
            ],
            shortTitle: "Set Travel Profile",
            systemImageName: "suitcase.rolling.fill"
        )
    }
}

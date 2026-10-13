import Combine
import Foundation
import NomadCore

/// The state behind the Trip Planner window: the stored trips, the selected one with its preview, the holidays
/// and advisory that load after it, the price comparison with home, and the add/edit sheet.
///
/// Planned trips and the home country are local: every write goes through `AppSettings.sanitizedPlannedTrips`
/// into the settings store, and only the destination country code is ever sent to look up public data.
@MainActor
final class TripPlannerModel: ObservableObject {
    /// What the preview needs from the rest of the app.
    struct Context {
        var countryDays: [VisitedCountryDay]
        var currentCountryCode: String?
        var policy: DashboardResourcePolicy
    }

    /// The network-backed lookups, injected so the model can be tested without a network.
    struct Services {
        /// Holidays and advisory of a trip; the flag forces a refresh.
        var online: @MainActor (PlannedTrip, Bool) async -> TripPreviewOnline?
        /// Eurostat price-level indices of a country; nil when they could not be loaded.
        var priceIndices: @MainActor (String) async -> [LocalPriceIndicatorKind: Double]?
    }

    struct EditorSession: Identifiable, Equatable {
        let id = UUID()
        var draft: TripDraft
    }

    @Published private(set) var settings: AppSettings
    @Published private(set) var selectedTripID: UUID?
    @Published private(set) var preview: TripPreview?
    @Published private(set) var onlineState: TripOnlineState = .loading
    @Published private(set) var priceState: TripPriceState = .unavailable
    /// How many checklist items are done, out of how many, for each trip in the list.
    @Published private(set) var checklistProgress: [UUID: (done: Int, total: Int)] = [:]
    @Published var editor: EditorSession?
    @Published private(set) var context: Context
    @Published var homeTimeZoneIdentifier: String {
        didSet {
            if homeTimeZoneIdentifier != oldValue {
                rebuildPreview()
            }
        }
    }

    let calendar: Calendar
    let locale: Locale

    private let settingsStore: AppSettingsStore
    private let services: Services
    private let now: () -> Date
    private var onlineTask: Task<Void, Never>?
    private var priceTask: Task<Void, Never>?
    private var onlineKey: String?
    /// The holidays and advisory loaded for each trip, so the list can count the items they add. A trip's
    /// entry is dropped while its data loads again.
    private var loadedOnline: [UUID: TripPreviewOnline] = [:]
    private var priceKey: String?
    private var cancellables = Set<AnyCancellable>()

    init(
        settingsStore: AppSettingsStore,
        services: Services,
        context: Context,
        homeTimeZoneIdentifier: String,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) {
        self.settingsStore = settingsStore
        self.services = services
        self.context = context
        self.homeTimeZoneIdentifier = homeTimeZoneIdentifier
        self.now = now
        self.calendar = calendar
        self.locale = locale
        settings = settingsStore.settings
        selectedTripID = TripSelection.initial(among: settingsStore.settings.plannedTrips, now: now(), calendar: calendar)

        settingsStore.$settings
            .dropFirst()
            .sink { [weak self] newSettings in
                self?.settingsDidChange(newSettings)
            }
            .store(in: &cancellables)
        rebuildPreview()
    }

    /// The model for the app: the live services and the stores' own changes.
    static func live(
        settingsStore: AppSettingsStore,
        snapshotStore: DashboardSnapshotStore,
        homeTimeZoneIdentifier: String
    ) -> TripPlannerModel {
        let model = TripPlannerModel(
            settingsStore: settingsStore,
            services: Services(
                online: { trip, forceRefresh in
                    await snapshotStore.tripPreviewOnline(for: trip, forceRefresh: forceRefresh)
                },
                priceIndices: { code in
                    await snapshotStore.priceLevelIndices(forCountryCode: code)
                }
            ),
            context: Context(
                countryDays: snapshotStore.visitedCountryDays,
                currentCountryCode: snapshotStore.snapshot.currentCountryCode,
                policy: snapshotStore.resourcePolicy
            ),
            homeTimeZoneIdentifier: homeTimeZoneIdentifier
        )

        // The publishers emit before the store changes, so the model keeps the emitted values.
        snapshotStore.$visitedCountryDays
            .dropFirst()
            .sink { [weak model] days in
                model?.updateContext { $0.countryDays = days }
            }
            .store(in: &model.cancellables)
        snapshotStore.$snapshot
            .map(\.currentCountryCode)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak model] code in
                model?.updateContext { $0.currentCountryCode = code }
            }
            .store(in: &model.cancellables)
        snapshotStore.$resourcePolicy
            .removeDuplicates()
            .dropFirst()
            .sink { [weak model] policy in
                model?.updateContext { $0.policy = policy }
            }
            .store(in: &model.cancellables)
        return model
    }

    deinit {
        onlineTask?.cancel()
        priceTask?.cancel()
    }

    // MARK: State

    var trips: [PlannedTrip] {
        settings.plannedTrips
    }

    var selectedTrip: PlannedTrip? {
        trips.first { $0.id == selectedTripID }
    }

    var canAddTrip: Bool {
        TripPlannerEditing.canAddTrip(to: trips)
    }

    var listRows: [TripListRow] {
        TripListRow.rows(for: trips, checklists: checklistProgress, now: now(), calendar: calendar, locale: locale)
    }

    /// The preview with whatever has loaded so far; nil without a selected trip.
    var presentation: TripPreviewPresentation? {
        preview.map {
            TripPreviewPresentation(
                preview: $0,
                online: onlineState,
                prices: priceState,
                policy: context.policy,
                settings: settings,
                now: now(),
                calendar: calendar,
                locale: locale
            )
        }
    }

    // MARK: Selection

    func select(_ id: UUID?) {
        guard id != selectedTripID else {
            return
        }

        selectedTripID = id
        rebuildPreview()
    }

    // MARK: Editing

    func beginAdding() {
        guard canAddTrip else {
            return
        }

        editor = EditorSession(draft: .new(now: now(), calendar: calendar))
    }

    func beginEditing(_ id: UUID) {
        guard let trip = trips.first(where: { $0.id == id }) else {
            return
        }

        editor = EditorSession(draft: TripDraft(trip: trip))
    }

    /// Stores the draft as a new trip or in place of the one it edits, and selects it. Does nothing for a
    /// draft that cannot be saved or when the list is full and the draft is new.
    func save(_ draft: TripDraft) {
        guard draft.canSave(now: now(), calendar: calendar),
              let trip = draft.trip(),
              draft.isNew == false || canAddTrip
        else {
            return
        }

        selectedTripID = trip.id
        settingsStore.settings.plannedTrips = TripPlannerEditing.saving(
            trip,
            into: settingsStore.settings.plannedTrips,
            now: now(),
            calendar: calendar
        )
        editor = nil
    }

    func delete(_ id: UUID) {
        settingsStore.settings.plannedTrips = TripPlannerEditing.deleting(
            id,
            from: settingsStore.settings.plannedTrips,
            now: now(),
            calendar: calendar
        )
        editor = nil
    }

    // MARK: Checklist

    /// Ticks or unticks a suggested item of the selected trip.
    func setChecked(_ checked: Bool, itemID: String) {
        updateChecklist { $0.setChecked(checked, itemID: itemID) }
    }

    /// Adds an item of the traveller's own to the selected trip. False, and nothing added, when the title is
    /// empty or the list is full.
    @discardableResult
    func addCustomItem(title: String) -> Bool {
        var added = false
        updateChecklist { added = $0.addCustomItem(title: title) != nil }
        return added
    }

    func setCustomItemChecked(_ checked: Bool, id: UUID) {
        updateChecklist { $0.setCustomItemChecked(checked, id: id) }
    }

    func removeCustomItem(id: UUID) {
        updateChecklist { $0.removeCustomItem(id: id) }
    }

    /// Every checklist write goes through the sanitizer into the settings store, like the other trip edits.
    private func updateChecklist(_ change: (inout TripChecklistState) -> Void) {
        guard let id = selectedTripID else {
            return
        }

        settingsStore.settings.plannedTrips = TripPlannerEditing.updatingChecklist(
            of: id,
            in: settingsStore.settings.plannedTrips,
            now: now(),
            calendar: calendar,
            change: change
        )
    }

    private func rebuildChecklistProgress() {
        let ids = Set(trips.map(\.id))
        loadedOnline = loadedOnline.filter { ids.contains($0.key) }
        checklistProgress = Dictionary(uniqueKeysWithValues: trips.map { trip in
            let tripPreview = preview?.trip.id == trip.id ? preview : nil
            let source = tripPreview ?? TripPreview.make(
                trip: trip,
                settings: settings,
                countryDays: context.countryDays,
                currentCountryCode: context.currentCountryCode,
                homeTimeZoneIdentifier: homeTimeZoneIdentifier,
                now: now(),
                calendar: calendar,
                locale: locale
            )
            let items = TripChecklist.items(
                for: source,
                online: loadedOnline[trip.id],
                settings: settings,
                calendar: calendar,
                locale: locale
            )
            return (trip.id, TripChecklist.progress(items: items, state: trip.checklist))
        })
    }

    // MARK: Loading

    /// Loads the holidays and advisory again, ignoring what is saved.
    func refreshOnline() {
        loadOnline(force: true)
    }

    /// Waits for the lookups that are running; for tests.
    func waitForLoads() async {
        await onlineTask?.value
        await priceTask?.value
    }

    func updateContext(_ change: (inout Context) -> Void) {
        change(&context)
        rebuildPreview()
    }

    private func settingsDidChange(_ newSettings: AppSettings) {
        settings = newSettings
        selectedTripID = TripSelection.reconciled(selectedTripID, among: newSettings.plannedTrips, now: now(), calendar: calendar)
        rebuildPreview()
    }

    private func rebuildPreview() {
        guard let trip = selectedTrip else {
            preview = nil
            cancelLoads()
            loadedOnline = [:]
            checklistProgress = [:]
            return
        }

        preview = TripPreview.make(
            trip: trip,
            settings: settings,
            countryDays: context.countryDays,
            currentCountryCode: context.currentCountryCode,
            homeTimeZoneIdentifier: homeTimeZoneIdentifier,
            now: now(),
            calendar: calendar,
            locale: locale
        )

        let onlineKey = [
            trip.id.uuidString, trip.countryCode,
            String(trip.startDate.timeIntervalSince1970), String(trip.endDate.timeIntervalSince1970),
            String(settings.travelAdvisoryEnabled)
        ].joined(separator: "|")
        if onlineKey != self.onlineKey {
            self.onlineKey = onlineKey
            loadOnline(force: false)
        }

        let priceKey = [trip.countryCode, settings.effectiveHomeCountryCode ?? ""].joined(separator: "|")
        if priceKey != self.priceKey {
            self.priceKey = priceKey
            loadPrices(for: trip)
        }
        rebuildChecklistProgress()
    }

    private func cancelLoads() {
        onlineTask?.cancel()
        priceTask?.cancel()
        onlineKey = nil
        priceKey = nil
    }

    private func loadOnline(force: Bool) {
        onlineTask?.cancel()
        guard let trip = selectedTrip else {
            return
        }

        onlineState = .loading
        loadedOnline[trip.id] = nil
        let key = onlineKey
        let online = services.online
        onlineTask = Task { [weak self] in
            let result = await online(trip, force)
            guard Task.isCancelled == false, let self, onlineKey == key else {
                return
            }

            onlineState = result.map(TripOnlineState.loaded) ?? .unavailable
            loadedOnline[trip.id] = result
            rebuildChecklistProgress()
        }
    }

    private func loadPrices(for trip: PlannedTrip) {
        priceTask?.cancel()
        guard let home = settings.effectiveHomeCountryCode, home != trip.countryCode else {
            priceState = .unavailable
            return
        }

        priceState = .loading
        let key = priceKey
        let indices = services.priceIndices
        let destination = trip.countryCode
        priceTask = Task { [weak self] in
            async let destinationIndices = indices(destination)
            async let homeIndices = indices(home)
            let (destinationResult, homeResult) = await (destinationIndices, homeIndices)
            guard Task.isCancelled == false, let self, priceKey == key else {
                return
            }

            guard let destinationResult, let homeResult else {
                priceState = .unavailable
                return
            }

            let differences = PriceLevelComparison.compare(destination: destinationResult, home: homeResult)
            priceState = differences.isEmpty ? .unavailable : .loaded(differences)
        }
    }
}

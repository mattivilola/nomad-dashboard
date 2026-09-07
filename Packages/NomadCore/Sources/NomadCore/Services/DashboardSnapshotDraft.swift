import Foundation

/// A short-lived value used to update one section without replacing concurrently completed sections.
struct DashboardSnapshotDraft {
    var network: NetworkSectionSnapshot
    var power: PowerSectionSnapshot
    var travelContext: TravelContextSnapshot
    var travelAlerts: TravelAlertsSnapshot?
    var weather: WeatherSnapshot?
    var localInfo: LocalInfoSnapshot?
    var fuelPrices: FuelPriceSnapshot?
    var fuelDiagnostics: FuelDiagnosticsSnapshot?
    var emergencyCare: EmergencyCareSnapshot?
    var marine: MarineSnapshot?
    var appState: AppStatusSnapshot

    init(_ snapshot: DashboardSnapshot) {
        network = snapshot.network
        power = snapshot.power
        travelContext = snapshot.travelContext
        travelAlerts = snapshot.travelAlerts
        weather = snapshot.weather
        localInfo = snapshot.localInfo
        fuelPrices = snapshot.fuelPrices
        fuelDiagnostics = snapshot.fuelDiagnostics
        emergencyCare = snapshot.emergencyCare
        marine = snapshot.marine
        appState = snapshot.appState
    }

    var snapshot: DashboardSnapshot {
        DashboardSnapshot(
            network: network,
            power: power,
            travelContext: travelContext,
            travelAlerts: travelAlerts,
            weather: weather,
            localInfo: localInfo,
            fuelPrices: fuelPrices,
            fuelDiagnostics: fuelDiagnostics,
            emergencyCare: emergencyCare,
            marine: marine,
            appState: appState
        )
    }
}

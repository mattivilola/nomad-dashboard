import NomadCore

/// Which cards take up space in the grid. Cards whose opt-in feature is switched off are not
/// rendered (they would each spend a card of height saying "Off"); one compact row names them
/// instead. While the layout is being customized every card shows so it can still be ordered.
struct DashboardCardVisibility: Equatable {
    let visibleOrder: [DashboardCardID]
    /// Titles of the cards that are turned off, in dashboard order. Empty while customizing.
    let turnedOffTitles: [String]

    init(order: [DashboardCardID], settings: AppSettings, isCustomizingLayout: Bool) {
        if isCustomizingLayout {
            visibleOrder = order
            turnedOffTitles = []
            return
        }

        visibleOrder = order.filter { $0.isFeatureEnabled(in: settings) }
        turnedOffTitles = order
            .filter { $0.isFeatureEnabled(in: settings) == false }
            .map(\.displayTitle)
    }

    /// "Turned off: Data Guard, Local Info, Fuel Prices", or nil when everything is on.
    var turnedOffText: String? {
        turnedOffTitles.isEmpty ? nil : "Turned off: " + turnedOffTitles.joined(separator: ", ")
    }
}

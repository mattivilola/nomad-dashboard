import NomadCore
import SwiftUI

/// Scrolls the dashboard panel to a card. The default does nothing so views embedded
/// outside `DashboardPanelView` (previews, tests) keep working.
struct DashboardScrollToCardAction {
    private let handler: (DashboardCardID) -> Void

    init(_ handler: @escaping (DashboardCardID) -> Void = { _ in }) {
        self.handler = handler
    }

    func callAsFunction(_ cardID: DashboardCardID) {
        handler(cardID)
    }
}

extension EnvironmentValues {
    @Entry var dashboardScrollToCard = DashboardScrollToCardAction()
}

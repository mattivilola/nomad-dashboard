import SwiftUI
import WidgetKit

@main
struct NomadDashboardWidgetsBundle: WidgetBundle {
    var body: some Widget {
        GlanceWidget()
        SafetyWidget()
        DaylightWidget()
    }
}

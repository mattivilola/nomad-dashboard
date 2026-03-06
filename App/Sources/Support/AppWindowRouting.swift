import AppKit
import SwiftUI

enum AppWindowDestination: String {
    case settings
    case about
    case visitedMap = "visited-map"

    var title: String {
        switch self {
        case .settings:
            "Settings"
        case .about:
            "About Nomad Dashboard"
        case .visitedMap:
            "Visited Map"
        }
    }
}

@MainActor
func openAndActivateWindow(_ destination: AppWindowDestination, with openWindow: OpenWindowAction) {
    openWindow(id: destination.rawValue)

    // SwiftUI may create the NSWindow on the next runloop, so retry briefly.
    focusWindow(named: destination.title)
    DispatchQueue.main.async {
        focusWindow(named: destination.title)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
        focusWindow(named: destination.title)
    }
}

@MainActor
private func focusWindow(named title: String) {
    NSApp.activate(ignoringOtherApps: true)

    guard let window = NSApp.windows.last(where: { $0.title == title }) else {
        return
    }

    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
}

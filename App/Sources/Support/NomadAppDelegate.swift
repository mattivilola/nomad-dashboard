import AppKit
import NomadCore

/// Handles the links the widgets open (`nomaddashboard://dashboard`).
///
/// A tap on a widget brings the app to the front. Showing the dashboard popover as well is not possible
/// from here: the `MenuBarExtra` window has no public call to present it on macOS 14, and the status
/// item SwiftUI creates for it has no target, action or accessibility press to trigger (all tried). The
/// link is still routed through `NomadDeepLink`, so presenting the popover only needs to be added here.
final class NomadAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let scheme = NomadDeepLink.scheme(),
              urls.contains(where: { NomadDeepLink(url: $0, scheme: scheme) == .dashboard })
        else {
            return
        }

        NSApp.activate()
    }
}

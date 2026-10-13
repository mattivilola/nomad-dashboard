import AppKit

/// Small system actions shared by the dashboard and the windows.
enum ExternalActions {
    /// Opens a web link from the bundled embassy data (Apple Maps, a mission or ministry website).
    static func openWebURL(_ url: URL) {
        guard url.scheme == "https" || url.scheme == "http" else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    static func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

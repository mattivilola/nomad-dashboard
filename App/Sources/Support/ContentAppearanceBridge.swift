import AppKit
import SwiftUI

struct ContentAppearanceBridge: NSViewRepresentable {
    let appearance: NSAppearance?

    func makeNSView(context: Context) -> BridgeView {
        let view = BridgeView()
        view.appearanceOverride = appearance
        return view
    }

    func updateNSView(_ nsView: BridgeView, context: Context) {
        nsView.appearanceOverride = appearance
    }

    static func dismantleNSView(_ nsView: BridgeView, coordinator: ()) {
        nsView.appearanceOverride = nil
    }
}

extension ContentAppearanceBridge {
    final class BridgeView: NSView {
        var appearanceOverride: NSAppearance? {
            didSet {
                applyAppearanceOverride()
            }
        }

        override var intrinsicContentSize: NSSize {
            .zero
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyAppearanceOverride()
        }

        private func applyAppearanceOverride() {
            // Apply the override to this window's content root only. Setting NSWindow.appearance
            // would also retint MenuBarExtra/titlebar chrome, which must keep following the
            // system appearance to render the native toolbar correctly.
            window?.contentView?.appearance = appearanceOverride
        }
    }
}

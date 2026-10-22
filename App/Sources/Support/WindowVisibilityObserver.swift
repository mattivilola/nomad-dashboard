import AppKit
import SwiftUI

/// SwiftUI can retain MenuBarExtra and Window content after it is ordered out or minimized.
/// Window occlusion, rather than view appearance, controls display-only work.
struct WindowVisibilityObserver: NSViewRepresentable {
    let onChange: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {
        nsView.onChange = onChange
    }

    static func dismantleNSView(_ nsView: ObserverView, coordinator: ()) {
        nsView.stop()
    }

    final class ObserverView: NSView {
        var onChange: (@MainActor (Bool) -> Void)?
        private var lastVisibility: Bool?
        private var updateTask: Task<Void, Never>?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            if let window {
                for name in [
                    NSWindow.didChangeOcclusionStateNotification,
                    NSWindow.didMiniaturizeNotification,
                    NSWindow.didDeminiaturizeNotification,
                    NSWindow.willCloseNotification
                ] {
                    NotificationCenter.default.addObserver(self, selector: #selector(visibilityChanged), name: name, object: window)
                }
            }
            visibilityChanged()
        }

        @objc private func visibilityChanged() {
            updateTask?.cancel()
            updateTask = Task { @MainActor [weak self] in
                guard !Task.isCancelled, let self else { return }
                let visible = window.map { $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) } ?? false
                guard lastVisibility != visible else { return }
                lastVisibility = visible
                onChange?(visible)
            }
        }

        func stop() {
            NotificationCenter.default.removeObserver(self)
            updateTask?.cancel()
            let callback = onChange
            onChange = nil
            Task { @MainActor in callback?(false) }
        }
    }
}

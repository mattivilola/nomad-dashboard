import NomadCore
import NomadUI
import SwiftUI

extension AppSettingsStore {
    /// Two-way binding to one persisted setting.
    func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { self.settings[keyPath: keyPath] = $0 }
        )
    }

    /// Binding for a feature toggle that depends on device location: after saving the value it hands the
    /// current location to the snapshot store and, when any enabled feature uses the device location,
    /// prepares location access.
    func locationAwareBinding(
        _ keyPath: WritableKeyPath<AppSettings, Bool>,
        snapshotStore: DashboardSnapshotStore,
        locationStore: CurrentLocationStore
    ) -> Binding<Bool> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { isEnabled in
                self.settings[keyPath: keyPath] = isEnabled
                snapshotStore.setCurrentLocation(locationStore.currentLocation)

                if self.settings.usesDeviceLocation {
                    locationStore.prepareForWeather()
                }
            }
        )
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

/// The footer text under a Settings group. Grouped forms centre or trail footers by default, so every footer
/// goes through here to read leading-aligned, like the group's own rows.
struct SettingsFooter: View {
    private let text: Text

    init(_ text: String) {
        self.text = Text(text)
    }

    var body: some View {
        text
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Form for one Settings page. It scrolls to a requested group and reports the request as handled.
struct SettingsPageForm<Content: View>: View {
    let page: SettingsPage
    @ObservedObject var navigationController: SettingsNavigationController
    var onFocus: (SettingsFocusTarget) -> Void = { _ in }
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                content()
            }
            .formStyle(.grouped)
            .onReceive(navigationController.$focusRequest.compactMap(\.self)) { request in
                guard request.target.page == page else {
                    return
                }

                Task { @MainActor in
                    // Let a freshly selected page lay out before scrolling to its group.
                    await Task.yield()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(request.target.rawValue, anchor: .top)
                    }
                    onFocus(request.target)
                    navigationController.complete(request)
                }
            }
        }
    }
}

import Foundation
import IOKit.ps

/// IOKit delivers changes on the main run loop, without a polling timer or a power assertion.
@MainActor
final class PowerSourceChangeObserver {
    private var notification: PowerNotificationSource?
    private let onChange: @MainActor () -> Void

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<PowerSourceChangeObserver>.fromOpaque(context).takeUnretainedValue().onChange()
            }
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            notification = PowerNotificationSource(source: source)
        }
    }
}

/// CFRunLoopSourceInvalidate is thread-safe; this owner can clean up from a nonisolated deinit.
private final class PowerNotificationSource: @unchecked Sendable {
    private let source: CFRunLoopSource

    init(source: CFRunLoopSource) {
        self.source = source
    }

    deinit {
        CFRunLoopSourceInvalidate(source)
    }
}

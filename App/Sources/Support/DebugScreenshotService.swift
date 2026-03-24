import AppKit
import Foundation
import NomadCore
import OSLog

@MainActor
final class DebugScreenshotService {
    static let shared = DebugScreenshotService()

    private let fileManager: FileManager
    private let bundleURLProvider: () -> URL
    private let now: () -> Date
    private let logger: Logger

    init(
        fileManager: FileManager = .default,
        bundleURLProvider: @escaping () -> URL = { Bundle.main.bundleURL },
        now: @escaping () -> Date = Date.init,
        logger: Logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "NomadDashboard",
            category: "DebugScreenshot"
        )
    ) {
        self.fileManager = fileManager
        self.bundleURLProvider = bundleURLProvider
        self.now = now
        self.logger = logger
    }

    func saveFrontmostVisibleWindowScreenshot() {
        guard AppRuntimeInfo.isDebugBuild else {
            return
        }

        do {
            let window = try targetWindow()
            let bitmap = try captureBitmap(from: window)
            let screenshotURL = try DebugScreenshotArtifacts.screenshotFileURL(
                windowTitle: windowLabel(for: window),
                bundleURL: bundleURLProvider(),
                date: now(),
                fileManager: fileManager
            )

            guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
                throw CaptureError.pngEncodingFailed
            }

            try pngData.write(to: screenshotURL, options: .atomic)
            logger.info("Saved debug screenshot to \(screenshotURL.path, privacy: .public)")
        } catch {
            logger.error("Failed to save debug screenshot: \(String(describing: error), privacy: .public)")
            NSSound.beep()
        }
    }

    private func targetWindow() throws -> NSWindow {
        if let keyWindow = NSApp.keyWindow, isCapturable(keyWindow) {
            return keyWindow
        }

        if let mainWindow = NSApp.mainWindow, isCapturable(mainWindow) {
            return mainWindow
        }

        if let orderedWindow = NSApp.orderedWindows.first(where: isCapturable) {
            return orderedWindow
        }

        throw CaptureError.noVisibleWindow
    }

    private func captureBitmap(from window: NSWindow) throws -> NSBitmapImageRep {
        guard let contentView = window.contentView else {
            throw CaptureError.missingContentView
        }

        let bounds = contentView.bounds.integral
        guard bounds.isEmpty == false else {
            throw CaptureError.emptyBounds
        }

        window.displayIfNeeded()
        contentView.displayIfNeeded()

        guard let bitmap = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw CaptureError.bitmapCreationFailed
        }

        contentView.cacheDisplay(in: bounds, to: bitmap)
        return bitmap
    }

    private func isCapturable(_ window: NSWindow) -> Bool {
        guard window.isVisible,
              window.isMiniaturized == false,
              window.alphaValue > 0,
              window.contentView != nil
        else {
            return false
        }

        return true
    }

    private func windowLabel(for window: NSWindow) -> String {
        let trimmedTitle = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmedTitle {
        case AppWindowDestination.settings.title:
            return "Settings"
        case AppWindowDestination.about.title:
            return "About"
        case AppWindowDestination.visitedMap.title:
            return "Visited Map"
        case "":
            return "Dashboard"
        default:
            if trimmedTitle == AppRuntimeInfo.appName {
                return "Dashboard"
            }

            return trimmedTitle
        }
    }

    private enum CaptureError: Error {
        case noVisibleWindow
        case missingContentView
        case emptyBounds
        case bitmapCreationFailed
        case pngEncodingFailed
    }
}

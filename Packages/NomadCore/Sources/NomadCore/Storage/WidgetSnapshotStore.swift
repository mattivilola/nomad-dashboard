import Foundation
import Security

/// Reads and writes the `WidgetSnapshot` the app shares with the widget extension.
///
/// The file lives in the App Group container, which only the app and its extension (same team) can
/// open. Writes are atomic so the widget never reads a half-written file.
public struct WidgetSnapshotStore: Sendable {
    public static let fileName = "widget-snapshot.json"
    /// Info.plist key that carries the team-prefixed App Group identifier of this build.
    public static let appGroupInfoKey = "NomadAppGroupIdentifier"

    private let fileURL: URL

    /// A store that keeps its file in `directory`.
    public init(directory: URL) {
        fileURL = directory.appendingPathComponent(Self.fileName, isDirectory: false)
    }

    /// The store in this build's App Group container, nil when the process may not use the group.
    ///
    /// Unsigned builds and builds signed without the entitlement have no group. Asking the system
    /// for a container the process is not entitled to can trigger a privacy prompt, so the
    /// entitlement is checked first.
    public static func appGroup(bundle: Bundle = .main, fileManager: FileManager = .default) -> WidgetSnapshotStore? {
        guard let identifier = appGroupIdentifier(bundle: bundle),
              AppGroupEntitlement.isGranted(identifier),
              let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        else {
            return nil
        }

        return WidgetSnapshotStore(directory: container)
    }

    public static func appGroupIdentifier(bundle: Bundle = .main) -> String? {
        let value = (bundle.object(forInfoDictionaryKey: appGroupInfoKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    /// The saved snapshot, nil when there is none, it cannot be read, or it was written by a newer format.
    public func load() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? Self.decoder.decode(WidgetSnapshot.self, from: data),
              snapshot.version == WidgetSnapshot.schemaVersion
        else {
            return nil
        }

        return snapshot
    }

    public func save(_ snapshot: WidgetSnapshot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

/// Whether this process was signed with a given App Group.
public enum AppGroupEntitlement {
    public static let key = "com.apple.security.application-groups"

    public static func isGranted(_ identifier: String) -> Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, key as CFString, nil) as? [String]
        else {
            return false
        }

        return value.contains(identifier)
    }
}

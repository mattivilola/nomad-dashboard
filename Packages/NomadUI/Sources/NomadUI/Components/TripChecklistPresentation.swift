import Foundation
import NomadCore

/// The "Before you leave" section of a trip: the generated departure checklist grouped for display, the
/// traveller's own items and how far along they are. Ticks and own items are stored locally with the trip
/// and are never part of analytics.
struct TripChecklistPresentation: Equatable {
    struct ItemRow: Identifiable, Equatable {
        /// The id of the suggested item, which is also what a tick is stored under.
        let id: String
        let title: String
        let detail: String?
        /// An official page for the item; the row offers a button for it.
        let link: URL?
        let isChecked: Bool
    }

    struct ItemGroup: Identifiable, Equatable {
        let id: TripChecklistGroup
        let title: String
        let items: [ItemRow]
    }

    struct CustomRow: Identifiable, Equatable {
        let id: UUID
        let title: String
        let isChecked: Bool
    }

    static let title = "Before you leave"
    static let customGroupTitle = "Your own"
    static let addPlaceholder = "Add your own…"
    static let addTitle = "Add"
    static let openLinkTitle = "Open"
    static let removeTitle = "Remove"
    static let localCaption = "Ticks and your own items stay on this Mac."

    /// Groups in display order; a group without items is left out.
    let groups: [ItemGroup]
    let customItems: [CustomRow]
    let done: Int
    let total: Int
    /// Whether another own item can be added.
    let canAddCustomItem: Bool

    init(
        preview: TripPreview,
        online: TripOnlineState,
        settings: AppSettings,
        calendar: Calendar,
        locale: Locale
    ) {
        let items = TripChecklist.items(
            for: preview,
            online: online.loadedData,
            settings: settings,
            calendar: calendar,
            locale: locale
        )
        let state = preview.trip.checklist

        groups = TripChecklistGroup.allCases.compactMap { group in
            let rows = items.filter { $0.group == group }.map {
                ItemRow(
                    id: $0.id,
                    title: $0.title,
                    detail: $0.detail,
                    link: $0.link,
                    isChecked: state.isChecked(itemID: $0.id)
                )
            }
            return rows.isEmpty ? nil : ItemGroup(id: group, title: group.title, items: rows)
        }
        customItems = state.customItems.map { CustomRow(id: $0.id, title: $0.title, isChecked: $0.isChecked) }
        (done, total) = TripChecklist.progress(items: items, state: state)
        canAddCustomItem = state.customItems.count < TripChecklistState.maximumCustomItems
    }

    // MARK: Progress

    /// "3 of 9 done"; "Nothing to check yet" without any item.
    var progressText: String {
        total > 0 ? "\(done) of \(total) done" : "Nothing to check yet"
    }

    /// 0...1 for the bar; nil without any item, when there is nothing to show.
    var progress: Double? {
        total > 0 ? Double(done) / Double(total) : nil
    }

    /// "3/9", the compact form in the trip list; nil without any item.
    static func compactProgressText(done: Int, total: Int) -> String? {
        total > 0 ? "\(done)/\(total)" : nil
    }

    /// Spoken: "3 of 9 checklist items done"; nil without any item.
    static func spokenProgress(done: Int, total: Int) -> String? {
        total > 0 ? "\(done) of \(total) checklist \(total == 1 ? "item" : "items") done" : nil
    }

    // MARK: Adding

    /// The text kept for a new own item: at most `TripChecklistCustomItem.maximumTitleLength` characters.
    static func limitedTitle(_ text: String) -> String {
        String(text.prefix(TripChecklistCustomItem.maximumTitleLength))
    }

    /// Whether `text` can be added: something other than whitespace, and room for one more.
    func canAdd(_ text: String) -> Bool {
        canAddCustomItem && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    /// The note under the add field: the item cap when it is reached, else the title cap when the field is
    /// full. Nil while there is room for both.
    func limitNote(forDraft text: String) -> String? {
        if canAddCustomItem == false {
            return "You can add up to \(TripChecklistState.maximumCustomItems) items of your own."
        }

        if text.count >= TripChecklistCustomItem.maximumTitleLength {
            return "Items are limited to \(TripChecklistCustomItem.maximumTitleLength) characters."
        }

        return nil
    }
}

extension TripOnlineState {
    /// The holidays and advisory once they have loaded.
    var loadedData: TripPreviewOnline? {
        if case let .loaded(online) = self {
            return online
        }

        return nil
    }
}

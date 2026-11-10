import Foundation
import NomadCore
import SwiftUI

/// Everything the travel alert detail sheet shows for one signal, derived from the signal state so the
/// sheet can be rebuilt on every refresh. Status wording, summaries and colors come from
/// `TravelAlertRowModel` and `TravelAlertStatusAppearance`, so the sheet always agrees with the card row.
public struct TravelAlertDetailPresentation: Identifiable, Equatable {
    public struct Item: Identifiable, Equatable {
        public let id: String
        public let title: String
        public let detail: String?
        public let badgeTitle: String
        let severity: TravelAlertSeverity
        public let metadataText: String
        public let url: URL?

        init(item: TravelAlertItem, sheetSourceName: String) {
            id = item.id
            title = item.title
            detail = item.detail?.nilIfEmpty
            badgeTitle = item.severity.badgeTitle
            severity = item.severity
            url = item.url
            metadataText = [
                item.areaName?.nilIfEmpty,
                item.sourceName == sheetSourceName ? nil : item.sourceName.nilIfEmpty,
                item.issuedAt.map { "Issued \(travelAlertDateText($0))" },
                item.expiresAt.map { "Until \(travelAlertDateText($0))" }
            ]
            .compactMap(\.self)
            .joined(separator: " · ")
        }

        var tint: Color {
            severity.tint
        }

        var symbolName: String {
            severity.symbolName
        }
    }

    public let id: TravelAlertKind
    public let title: String
    public let statusLabel: String
    public let summary: String
    public let detailSummary: String?
    /// `nil` when there is nothing to list, so the sheet shows only the summary.
    public let itemsHeading: String?
    public let items: [Item]
    public let sourceName: String
    public let sourceURL: URL?
    public let freshnessText: String
    let tint: Color
    let symbolName: String

    public var sourceButtonTitle: String {
        "Open \(sourceName)"
    }

    public init(state: TravelAlertSignalState) {
        let row = TravelAlertRowModel(state: state)
        let appearance = TravelAlertStatusAppearance(state: state)
        // `resolvedSignal` is nil while checking or unavailable; a stale state keeps its last known items.
        let items = (state.resolvedSignal?.items ?? []).map {
            Item(item: $0, sheetSourceName: row.sourceName)
        }

        id = state.kind
        title = row.title
        statusLabel = appearance.label
        summary = row.summary
        detailSummary = row.detailSummary?.nilIfEmpty
        itemsHeading = Self.itemsHeading(for: state.kind, count: items.count)
        self.items = items
        sourceName = row.sourceName
        sourceURL = row.sourceURL
        freshnessText = row.freshnessText
        tint = appearance.tint
        symbolName = appearance.symbolName
    }

    private static func itemsHeading(for kind: TravelAlertKind, count: Int) -> String? {
        guard count > 0 else {
            return nil
        }

        let isSingular = count == 1
        return switch kind {
        case .advisory:
            "\(count) monitored \(isSingular ? "country" : "countries")"
        case .weather:
            "\(count) active \(isSingular ? "alert" : "alerts")"
        case .security:
            "\(count) recent \(isSingular ? "bulletin" : "bulletins")"
        }
    }
}

/// The detail dialog behind a Travel Alerts card row: the signal's summary and every item behind it,
/// each linking to its own source page.
public struct TravelAlertDetailSheet: View {
    private let presentation: TravelAlertDetailPresentation
    private let openURLAction: (URL) -> Void

    @Environment(\.dismiss) private var dismiss

    public init(presentation: TravelAlertDetailPresentation, openURLAction: @escaping (URL) -> Void) {
        self.presentation = presentation
        self.openURLAction = openURLAction
    }

    public var body: some View {
        DashboardDetailSheet(minWidth: 460, minHeight: 0, maxHeight: 680) {
            DashboardDetailTitleHeader(
                title: presentation.title,
                accessory: {
                    BadgeView(
                        badge: PillBadge(
                            title: presentation.statusLabel,
                            symbolName: presentation.symbolName,
                            tint: presentation.tint
                        )
                    )
                }
            )
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                Text(presentation.summary)
                    .font(.subheadline)
                    .foregroundStyle(NomadTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let detailSummary = presentation.detailSummary {
                    Text(detailSummary)
                        .font(.subheadline)
                        .foregroundStyle(NomadTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let itemsHeading = presentation.itemsHeading {
                    Text(itemsHeading)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NomadTheme.tertiaryText)

                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(presentation.items) { item in
                                TravelAlertDetailItemCard(item: item, openURLAction: openURLAction)
                            }
                        }
                    }
                    .frame(maxHeight: 560)
                }
            }
        } actions: {
            if let sourceURL = presentation.sourceURL {
                Button(presentation.sourceButtonTitle) {
                    openURLAction(sourceURL)
                }
                .buttonStyle(.borderedProminent)
            }

            Button("Close") {
                dismiss()
            }
            .buttonStyle(.bordered)

            Spacer(minLength: 12)

            Text(presentation.freshnessText)
                .font(.caption)
                .foregroundStyle(NomadTheme.tertiaryText)
        }
    }
}

private struct TravelAlertDetailItemCard: View {
    let item: TravelAlertDetailPresentation.Item
    let openURLAction: (URL) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(item.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(NomadTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    BadgeView(
                        badge: PillBadge(title: item.badgeTitle, symbolName: item.symbolName, tint: item.tint)
                    )
                }

                if let detail = item.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(NomadTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if item.metadataText.isEmpty == false {
                    Text(item.metadataText)
                        .font(.caption2)
                        .foregroundStyle(NomadTheme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let url = item.url {
                Button {
                    openURLAction(url)
                } label: {
                    Label("Open", systemImage: "arrow.up.right")
                }
                .buttonStyle(.dashboardInline)
                .help(url.host ?? "")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(item.tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(item.tint.opacity(0.14), lineWidth: 1)
        )
    }
}

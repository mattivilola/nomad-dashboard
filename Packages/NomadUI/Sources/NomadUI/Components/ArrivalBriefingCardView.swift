import NomadCore
import SwiftUI

/// The one-time "Welcome to Morocco" card at the top of the overview. It collapses to one line and is
/// dismissed with "Got it".
struct ArrivalBriefingCardView: View {
    let presentation: ArrivalBriefingPresentation
    let acknowledge: () -> Void
    let startDataGuardMonitoring: () -> Void

    @State private var isCollapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if isCollapsed == false {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(presentation.rows) { row in
                        ArrivalBriefingRowView(row: row, startDataGuardMonitoring: startDataGuardMonitoring)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, isCollapsed ? 8 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(NomadTheme.tileBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(NomadTheme.cardBorder, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                withAnimation(.snappy) { isCollapsed.toggle() }
            } label: {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "airplane.arrival")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(NomadTheme.teal)
                        .frame(width: 20)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(presentation.title)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(NomadTheme.primaryText)
                            .lineLimit(1)

                        if let line = isCollapsed ? collapsedLine : presentation.subtitle {
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(NomadTheme.secondaryText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }

                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(presentation.title)
            .accessibilityHint(isCollapsed ? "Expands the briefing" : "Collapses the briefing")

            Button(ArrivalBriefingPresentation.acknowledgeTitle, action: acknowledge)
                .buttonStyle(.dashboardInline(isCompact: true))
                .help("Hide this briefing until you arrive somewhere else")

            Button {
                withAnimation(.snappy) { isCollapsed.toggle() }
            } label: {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(NomadTheme.tertiaryText)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isCollapsed ? "Expand briefing" : "Collapse briefing")
            .accessibilityLabel(isCollapsed ? "Expand briefing" : "Collapse briefing")
        }
    }

    private var collapsedLine: String? {
        presentation.collapsedSummary.nilIfEmpty
    }
}

private struct ArrivalBriefingRowView: View {
    let row: ArrivalBriefingPresentation.Row
    let startDataGuardMonitoring: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: row.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(row.tone.statusTint(neutral: NomadTheme.tertiaryText))
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 6) {
                    Text(row.title)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(NomadTheme.tertiaryText)
                        .lineLimit(1)

                    if let flag = row.flag {
                        NeutralChip(title: flag)
                            .fixedSize()
                    }
                }

                text(row.text)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(row.tone.statusTint(neutral: NomadTheme.primaryText))
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = row.detail {
                    text(detail)
                        .font(.caption)
                        .foregroundStyle(NomadTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if row.kind == .dataGuard {
                    Button(ArrivalBriefingPresentation.startMonitoringTitle, action: startDataGuardMonitoring)
                        .buttonStyle(.dashboardInline(isCompact: true))
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func text(_ value: String) -> some View {
        if row.isSelectable {
            Text(value).textSelection(.enabled)
        } else {
            Text(value)
        }
    }
}

import NomadCore
import SwiftUI

/// The "Stays & Visas" dashboard card: how long the Mac has been in this country, the user's visa
/// allowance, the Schengen 90/180 counter and this year's days per country for tax residence.
struct StaysSectionView: View {
    let presentation: StaysCardPresentation
    let widthMode: DashboardCardWidthMode
    let accessory: AnyView?
    let collapse: DashboardCardCollapse
    /// Opens Settings on the citizenship group (the Schengen limit depends on it).
    let openCitizenshipSettingsAction: () -> Void
    /// Opens Settings on the Stays & Visas group.
    let openSettingsAction: () -> Void
    /// Opens the Visited Map, where recorded days can be corrected.
    let reviewDaysAction: () -> Void

    private var isCompact: Bool {
        widthMode == .narrow
    }

    var body: some View {
        DashboardCard(
            title: DashboardCardID.stays.displayTitle,
            subtitle: StaysCardPresentation.subtitle,
            badge: presentation.badge,
            accessory: accessory,
            collapse: collapse,
            isCompact: isCompact
        ) {
            if presentation.isEnabled {
                VStack(alignment: .leading, spacing: 10) {
                    currentStayRow
                    allowanceTile
                    schengenTile
                    taxYearTile
                }
            } else {
                WeatherEmptyState(
                    title: StaysCardPresentation.offTitle,
                    systemImage: "calendar.badge.clock",
                    message: StaysCardPresentation.offMessage,
                    actionTitle: "Open Settings",
                    action: openSettingsAction
                )
            }
        }
    }

    // MARK: Current stay

    @ViewBuilder
    private var currentStayRow: some View {
        if let stay = presentation.currentStay {
            VStack(alignment: .leading, spacing: 3) {
                (Text(stay.title)
                    .font(.system(size: isCompact ? 14 : 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(NomadTheme.primaryText)
                    + Text("  \(stay.since)")
                    .font(.caption)
                    .foregroundStyle(NomadTheme.secondaryText))
                    .fixedSize(horizontal: false, vertical: true)

                if let gapNote = stay.gapNote {
                    Text(gapNote)
                        .font(.caption2)
                        .foregroundStyle(NomadTheme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        } else {
            Text(StaysCardPresentation.locationPendingText)
                .font(.caption)
                .foregroundStyle(NomadTheme.secondaryText)
        }
    }

    // MARK: Allowance

    @ViewBuilder
    private var allowanceTile: some View {
        if let allowance = presentation.allowance {
            VStack(alignment: .leading, spacing: 6) {
                Text(allowance.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NomadTheme.tertiaryText)

                UsageProgressBar(progress: allowance.progress, tint: allowance.tone.barTint, height: 4)

                Text(allowance.text)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(allowance.tone.textTint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .staysTile()
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Schengen

    @ViewBuilder
    private var schengenTile: some View {
        if let schengen = presentation.schengen {
            switch schengen.kind {
            case .exempt:
                Label(schengen.line, systemImage: "globe.europe.africa")
                    .font(.caption)
                    .foregroundStyle(NomadTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .staysTile()
            case .counting, .citizenshipUnknown:
                VStack(alignment: .leading, spacing: 6) {
                    Text(schengen.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NomadTheme.tertiaryText)

                    if let progress = schengen.progress {
                        UsageProgressBar(progress: progress, tint: schengen.tone.barTint, height: 4)
                    }

                    Text(schengen.line)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(schengen.tone.textTint)
                        .fixedSize(horizontal: false, vertical: true)

                    if let hint = schengen.hint {
                        HStack(alignment: .center, spacing: 8) {
                            Text(hint)
                                .font(.caption2)
                                .foregroundStyle(NomadTheme.tertiaryText)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 4)

                            Button(StaysCardPresentation.citizenshipActionTitle, action: openCitizenshipSettingsAction)
                                .buttonStyle(.dashboardInline(isCompact: true))
                        }
                    }
                }
                .staysTile()
            }
        }
    }

    // MARK: Tax year

    @ViewBuilder
    private var taxYearTile: some View {
        if let taxYear = presentation.taxYear {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(taxYear.heading)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NomadTheme.tertiaryText)

                    Spacer(minLength: 4)

                    Text(taxYear.thresholdText)
                        .font(.caption2)
                        .foregroundStyle(NomadTheme.tertiaryText)
                }

                if let emptyText = taxYear.emptyText {
                    Text(emptyText)
                        .font(.caption)
                        .foregroundStyle(NomadTheme.secondaryText)
                }

                ForEach(taxYear.countries) { country in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(country.name)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(NomadTheme.primaryText)
                                .lineLimit(1)

                            Spacer(minLength: 4)

                            Text(country.daysText)
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(country.tone.textTint)
                                .lineLimit(1)
                        }

                        UsageProgressBar(progress: country.progress, tint: country.tone.barTint)
                    }
                    .accessibilityElement(children: .combine)
                }

                taxYearFooter(taxYear)
            }
            .staysTile()
        }
    }

    private func taxYearFooter(_ taxYear: StaysCardPresentation.TaxYear) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                if let unrecorded = taxYear.unrecordedText {
                    Text(unrecorded)
                        .font(.caption)
                        .foregroundStyle(NomadTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Button(StaysCardPresentation.reviewDaysTitle, action: reviewDaysAction)
                    .buttonStyle(.dashboardInline(isCompact: true))
                    .help("Open the Visited Map to correct recorded days")
            }

            Text(StaysCardPresentation.taxFooter)
                .font(.caption2)
                .foregroundStyle(NomadTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension SummaryTileTone {
    /// Only sand and coral carry a status; every other tone shows in `neutral`.
    func statusTint(neutral: Color) -> Color {
        switch self {
        case .caution, .attention, .critical: tint
        default: neutral
        }
    }
}

private extension SummaryTileTone {
    var textTint: Color {
        statusTint(neutral: NomadTheme.secondaryText)
    }

    var barTint: Color {
        statusTint(neutral: NomadTheme.teal)
    }
}

private extension View {
    func staysTile() -> some View {
        padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(NomadTheme.chartBackground.opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(NomadTheme.cardBorder.opacity(0.9), lineWidth: 1)
                    )
            )
    }
}

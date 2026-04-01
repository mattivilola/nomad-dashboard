import NomadCore
import SwiftUI

struct TimeTrackingHeaderPillView: View {
    private static let maxProjectCount = 3

    let presentation: TimeTrackingQuickActionsPresentation
    let chipsEnabled: Bool
    let primaryAction: () -> Void
    let stopAction: () -> Void
    let allocateAction: (TimeTrackingBucket) -> Void
    let openAction: () -> Void

    var body: some View {
        let variants = presentation.headerLayoutVariants(maxProjectCount: Self.maxProjectCount)

        ViewThatFits(in: .horizontal) {
            ForEach(variants) { variant in
                headerToolbar(variant)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(NomadTheme.chartBackground.opacity(0.95))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(NomadTheme.cardBorder.opacity(0.92), lineWidth: 1)
                )
        )
    }

    private func headerToolbar(_ variant: TimeTrackingHeaderLayoutVariant) -> some View {
        HStack(spacing: variant.rowSpacing) {
            pendingDurationView(style: variant.pendingLabelStyle)
                .layoutPriority(1)

            ForEach(presentation.visibleHeaderControls, id: \.title) { control in
                headerIconChipButton(
                    title: control.title,
                    systemImage: control.systemImage,
                    chromeDensity: variant.chromeDensity
                ) {
                    switch control.kind {
                    case .primary:
                        primaryAction()
                    case .stop:
                        stopAction()
                    }
                }
            }

            HStack(spacing: variant.chipSpacing) {
                ForEach(variant.configuration.chips) { chip in
                    headerChipButton(
                        chip: chip,
                        density: variant.chipDensity,
                        visibleCharacterCount: variant.visibleChipTitleCharacterCount
                    ) {
                        allocateAction(chip.bucket)
                    }
                }
            }

            headerIconChipButton(
                title: presentation.openControlIcon.title,
                systemImage: presentation.openControlIcon.systemImage,
                chromeDensity: variant.chromeDensity,
                action: openAction
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pendingDurationView(style: TimeTrackingHeaderPendingLabelStyle) -> some View {
        HStack(spacing: style == .full ? 6 : 4) {
            Image(systemName: "clock.badge.checkmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NomadTheme.teal)

            Text(pendingText(for: style))
                .font(.caption.weight(.semibold))
                .foregroundStyle(NomadTheme.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func pendingText(for style: TimeTrackingHeaderPendingLabelStyle) -> String {
        switch style {
        case .full:
            "Pending \(presentation.pendingDurationText)"
        case .durationOnly:
            presentation.pendingDurationText
        }
    }

    private func headerChipButton(
        chip: TimeTrackingQuickBucketChip,
        density: TimeTrackingHeaderChipDensity,
        visibleCharacterCount: Int,
        action: @escaping () -> Void
    ) -> some View {
        let metrics = chipMetrics(for: chip, density: density)

        return Button(action: action) {
            Text(
                TimeTrackingQuickActionsPresentation.headerCompactChipTitle(
                    chip.title,
                    visibleCharacterCount: visibleCharacterCount
                )
            )
                .font(.caption.weight(.semibold))
                .foregroundStyle(chipsEnabled ? NomadTheme.primaryText : NomadTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.vertical, metrics.verticalPadding)
                .frame(
                    minWidth: metrics.minimumWidth,
                    idealWidth: metrics.idealWidth,
                    maxWidth: metrics.maximumWidth,
                    alignment: .center
                )
                .background(
                    Capsule(style: .continuous)
                        .fill(NomadTheme.inlineButtonBackground.opacity(chipsEnabled ? 1 : 0.72))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(NomadTheme.cardBorder.opacity(chipsEnabled ? 1 : 0.72), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(chipsEnabled == false)
        .help(chip.title)
        .accessibilityLabel(chip.title)
    }

    private func headerIconChipButton(
        title: String,
        systemImage: String,
        chromeDensity: TimeTrackingHeaderChromeDensity,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NomadTheme.primaryText)
                .frame(width: chromeDensity.iconButtonSize, height: chromeDensity.iconButtonSize)
                .background(
                    Capsule(style: .continuous)
                        .fill(NomadTheme.inlineButtonBackground.opacity(0.95))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(NomadTheme.cardBorder.opacity(0.92), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }

    private func chipMetrics(
        for chip: TimeTrackingQuickBucketChip,
        density: TimeTrackingHeaderChipDensity
    ) -> TimeTrackingHeaderChipMetrics {
        let isOtherChip = chip.bucket == .other

        switch (density, isOtherChip) {
        case (.regular, false):
            return TimeTrackingHeaderChipMetrics(
                horizontalPadding: 8,
                verticalPadding: 6,
                minimumWidth: 34,
                idealWidth: 48,
                maximumWidth: 56
            )
        case (.regular, true):
            return TimeTrackingHeaderChipMetrics(
                horizontalPadding: 7,
                verticalPadding: 6,
                minimumWidth: 32,
                idealWidth: 44,
                maximumWidth: 50
            )
        case (.compact, false):
            return TimeTrackingHeaderChipMetrics(
                horizontalPadding: 5,
                verticalPadding: 5,
                minimumWidth: 30,
                idealWidth: 42,
                maximumWidth: 50
            )
        case (.compact, true):
            return TimeTrackingHeaderChipMetrics(
                horizontalPadding: 5,
                verticalPadding: 5,
                minimumWidth: 28,
                idealWidth: 38,
                maximumWidth: 46
            )
        }
    }
}

private struct TimeTrackingHeaderChipMetrics {
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let minimumWidth: CGFloat
    let idealWidth: CGFloat
    let maximumWidth: CGFloat
}

private extension TimeTrackingHeaderLayoutVariant {
    var rowSpacing: CGFloat {
        switch chromeDensity {
        case .regular:
            6
        case .compact:
            4
        }
    }

    var chipSpacing: CGFloat {
        switch chromeDensity {
        case .regular:
            chipDensity == .compact ? 4 : 6
        case .compact:
            4
        }
    }
}

private extension TimeTrackingHeaderChromeDensity {
    var iconButtonSize: CGFloat {
        switch self {
        case .regular:
            28
        case .compact:
            26
        }
    }
}

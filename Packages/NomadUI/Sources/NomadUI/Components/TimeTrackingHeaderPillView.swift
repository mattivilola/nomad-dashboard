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
            headerVariant(variants, index: 0)
            headerVariant(variants, index: 1)
            headerVariant(variants, index: 2)
            headerVariant(variants, index: 3)
            headerVariant(variants, index: 4)
            headerVariant(variants, index: 5)
            headerVariant(variants, index: 6)
            headerVariant(variants, index: 7)
            headerVariant(variants, index: 8)
            headerVariant(variants, index: 9)
            headerVariant(variants, index: 10)
            headerVariant(variants, index: 11)
            headerVariant(variants, index: 12)
            headerVariant(variants, index: 13)
            headerVariant(variants, index: 14)
            headerVariant(variants, index: 15)
            headerVariant(variants, index: 16)
            headerVariant(variants, index: 17)
            headerVariant(variants, index: 18)
            headerVariant(variants, index: 19)
            headerVariant(variants, index: 20)
            headerVariant(variants, index: 21)
            headerVariant(variants, index: 22)
            headerVariant(variants, index: 23)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
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

    @ViewBuilder
    private func headerVariant(_ variants: [TimeTrackingHeaderLayoutVariant], index: Int) -> some View {
        if variants.indices.contains(index) {
            headerToolbar(variants[index])
        }
    }

    private func headerToolbar(_ variant: TimeTrackingHeaderLayoutVariant) -> some View {
        HStack(spacing: 6) {
            pendingDurationView(style: variant.pendingLabelStyle)
                .layoutPriority(1)

            ForEach(presentation.visibleHeaderControls, id: \.title) { control in
                headerIconChipButton(
                    title: control.title,
                    systemImage: control.systemImage
                ) {
                    switch control.kind {
                    case .primary:
                        primaryAction()
                    case .stop:
                        stopAction()
                    }
                }
            }

            HStack(spacing: variant.chipDensity == .compact ? 4 : 6) {
                ForEach(variant.configuration.chips) { chip in
                    headerChipButton(
                        chip: chip,
                        density: variant.chipDensity
                    ) {
                        allocateAction(chip.bucket)
                    }
                }
            }

            headerIconChipButton(
                title: presentation.openControlIcon.title,
                systemImage: presentation.openControlIcon.systemImage,
                action: openAction
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pendingDurationView(style: TimeTrackingHeaderPendingLabelStyle) -> some View {
        HStack(spacing: style == .full ? 7 : 5) {
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
        action: @escaping () -> Void
    ) -> some View {
        let metrics = chipMetrics(for: chip, density: density)

        return Button(action: action) {
            Text(TimeTrackingQuickActionsPresentation.headerCompactChipTitle(chip.title))
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

    private func headerIconChipButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NomadTheme.primaryText)
                .frame(width: 28, height: 28)
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
                minimumWidth: 40,
                idealWidth: 50,
                maximumWidth: 58
            )
        case (.regular, true):
            return TimeTrackingHeaderChipMetrics(
                horizontalPadding: 8,
                verticalPadding: 6,
                minimumWidth: 40,
                idealWidth: 48,
                maximumWidth: 54
            )
        case (.compact, false):
            return TimeTrackingHeaderChipMetrics(
                horizontalPadding: 6,
                verticalPadding: 5,
                minimumWidth: 36,
                idealWidth: 46,
                maximumWidth: 52
            )
        case (.compact, true):
            return TimeTrackingHeaderChipMetrics(
                horizontalPadding: 6,
                verticalPadding: 5,
                minimumWidth: 34,
                idealWidth: 42,
                maximumWidth: 48
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

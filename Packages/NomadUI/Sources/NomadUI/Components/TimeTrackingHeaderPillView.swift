import AppKit
import NomadCore
import SwiftUI

struct TimeTrackingHeaderPillView: View {
    private static let maxProjectCount = 3
    private static let contentHeight: CGFloat = 28
    private static let outerHorizontalPadding: CGFloat = 8
    private static let outerVerticalPadding: CGFloat = 7

    let presentation: TimeTrackingQuickActionsPresentation
    let chipsEnabled: Bool
    let primaryAction: () -> Void
    let stopAction: () -> Void
    let interruptionCount: Int
    let lastInterruptionAt: Date?
    let interruptionAction: () -> Void
    let allocateAction: (TimeTrackingBucket) -> Void
    let openAction: () -> Void

    var body: some View {
        let variants = presentation.headerLayoutVariants(maxProjectCount: Self.maxProjectCount)

        GeometryReader { geometry in
            let rowLayout = TimeTrackingHeaderRowLayout(
                pendingDurationText: presentation.pendingDurationText,
                visibleControlsCount: presentation.visibleHeaderControls.count,
                includesInterruptionButton: true
            )
            let variant = rowLayout.fittingVariant(
                for: geometry.size.width,
                variants: variants
            ) ?? variants.last

            if let variant {
                headerToolbar(
                    variant,
                    rowLayout: rowLayout,
                    availableWidth: geometry.size.width
                )
                .frame(width: geometry.size.width, height: Self.contentHeight, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.contentHeight)
        .padding(.horizontal, Self.outerHorizontalPadding)
        .padding(.vertical, Self.outerVerticalPadding)
        .background(
            Capsule(style: .continuous)
                .fill(NomadTheme.chartBackground.opacity(0.95))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(NomadTheme.cardBorder.opacity(0.92), lineWidth: 1)
                )
        )
    }

    private func headerToolbar(
        _ variant: TimeTrackingHeaderLayoutVariant,
        rowLayout: TimeTrackingHeaderRowLayout,
        availableWidth: CGFloat
    ) -> some View {
        let chipLaneWidth = rowLayout.chipLaneWidth(for: variant, availableWidth: availableWidth)
        let chipWidths = rowLayout.chipWidths(for: variant, availableWidth: availableWidth)

        return HStack(spacing: variant.rowSpacing) {
            pendingDurationView(style: variant.pendingLabelStyle)
                .fixedSize(horizontal: true, vertical: false)

            HStack(spacing: variant.rowSpacing) {
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
            }
            .fixedSize(horizontal: true, vertical: false)

            TimeTrackingInterruptionButton(
                title: "Report interruption",
                count: interruptionCount,
                lastReportedAt: lastInterruptionAt,
                isEnabled: true,
                style: .compact,
                action: interruptionAction
            )
            .fixedSize(horizontal: true, vertical: false)

            HStack(spacing: variant.chipSpacing) {
                ForEach(Array(variant.configuration.chips.enumerated()), id: \.element.id) { index, chip in
                    headerChipButton(
                        chip: chip,
                        density: variant.chipDensity,
                        visibleCharacterCount: variant.visibleChipTitleCharacterCount,
                        width: chipWidths[index]
                    ) {
                        allocateAction(chip.bucket)
                    }
                }
            }
            .frame(width: chipLaneWidth, alignment: .leading)
            .layoutPriority(1)

            headerIconChipButton(
                title: presentation.openControlIcon.title,
                systemImage: presentation.openControlIcon.systemImage,
                chromeDensity: variant.chromeDensity,
                action: openAction
            )
            .fixedSize(horizontal: true, vertical: false)
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
        width: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
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
            .frame(width: width, height: density.chipHeight, alignment: .center)
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
}

struct TimeTrackingHeaderChipMetrics {
    let minimumWidth: CGFloat
    let idealWidth: CGFloat
}

struct TimeTrackingHeaderRowLayout {
    private static let outerHorizontalPadding: CGFloat = 16
    private static let statusIconWidth: CGFloat = 12
    private static let interruptionButtonWidth: CGFloat = 54

    let pendingDurationText: String
    let visibleControlsCount: Int
    let includesInterruptionButton: Bool

    init(
        pendingDurationText: String,
        visibleControlsCount: Int,
        includesInterruptionButton: Bool = false
    ) {
        self.pendingDurationText = pendingDurationText
        self.visibleControlsCount = visibleControlsCount
        self.includesInterruptionButton = includesInterruptionButton
    }

    func fittingVariant(
        for availableWidth: CGFloat,
        variants: [TimeTrackingHeaderLayoutVariant]
    ) -> TimeTrackingHeaderLayoutVariant? {
        variants.first(where: {
            chipLaneWidth(for: $0, availableWidth: availableWidth) >= minimumChipLaneWidth(for: $0)
        })
    }

    func chipLaneWidth(
        for variant: TimeTrackingHeaderLayoutVariant,
        availableWidth: CGFloat
    ) -> CGFloat {
        let contentWidth = max(availableWidth - Self.outerHorizontalPadding, 0)
        let fixedWidth = pendingWidth(for: variant)
            + controlClusterWidth(for: variant)
            + (includesInterruptionButton ? Self.interruptionButtonWidth : 0)
            + variant.chromeDensity.iconButtonSize
            + (variant.rowSpacing * (includesInterruptionButton ? 4 : 3))
        return max(contentWidth - fixedWidth, 0)
    }

    func chipWidths(
        for variant: TimeTrackingHeaderLayoutVariant,
        availableWidth: CGFloat
    ) -> [CGFloat] {
        let chips = variant.configuration.chips
        guard chips.isEmpty == false else {
            return []
        }

        let metrics = chips.map { variant.chipDensity.metrics(for: $0.bucket) }
        let spacingWidth = variant.chipSpacing * CGFloat(max(chips.count - 1, 0))
        let distributableWidth = max(chipLaneWidth(for: variant, availableWidth: availableWidth) - spacingWidth, 0)
        let minimumTotal = metrics.reduce(0) { $0 + $1.minimumWidth }
        let idealTotal = metrics.reduce(0) { $0 + $1.idealWidth }

        guard distributableWidth > 0 else {
            return metrics.map(\.minimumWidth)
        }

        if distributableWidth <= minimumTotal {
            return metrics.map(\.minimumWidth)
        }

        if distributableWidth >= idealTotal {
            let extraWidth = distributableWidth - idealTotal
            let weightTotal = idealTotal > 0 ? idealTotal : CGFloat(metrics.count)
            return metrics.map { metric in
                metric.idealWidth + extraWidth * (metric.idealWidth / weightTotal)
            }
        }

        let deficit = idealTotal - distributableWidth
        let shrinkCapacities = metrics.map { $0.idealWidth - $0.minimumWidth }
        let shrinkCapacityTotal = shrinkCapacities.reduce(0, +)

        guard shrinkCapacityTotal > 0 else {
            return metrics.map(\.idealWidth)
        }

        return zip(metrics, shrinkCapacities).map { metric, shrinkCapacity in
            metric.idealWidth - deficit * (shrinkCapacity / shrinkCapacityTotal)
        }
    }

    private func minimumChipLaneWidth(for variant: TimeTrackingHeaderLayoutVariant) -> CGFloat {
        let chips = variant.configuration.chips
        guard chips.isEmpty == false else {
            return 0
        }

        let spacingWidth = variant.chipSpacing * CGFloat(max(chips.count - 1, 0))
        return chips
            .map { variant.chipDensity.metrics(for: $0.bucket).minimumWidth }
            .reduce(spacingWidth, +)
    }

    private func pendingWidth(for variant: TimeTrackingHeaderLayoutVariant) -> CGFloat {
        let pendingText = switch variant.pendingLabelStyle {
        case .full:
            "Pending \(pendingDurationText)"
        case .durationOnly:
            pendingDurationText
        }

        let textWidth = ceil((pendingText as NSString).size(withAttributes: [.font: Self.makeStatusFont()]).width)
        let iconSpacing: CGFloat = variant.pendingLabelStyle == .full ? 6 : 4
        return Self.statusIconWidth + iconSpacing + textWidth
    }

    private func controlClusterWidth(for variant: TimeTrackingHeaderLayoutVariant) -> CGFloat {
        guard visibleControlsCount > 0 else {
            return 0
        }

        return CGFloat(visibleControlsCount) * variant.chromeDensity.iconButtonSize
            + CGFloat(max(visibleControlsCount - 1, 0)) * variant.rowSpacing
    }

    private static func makeStatusFont() -> NSFont {
        NSFont.systemFont(ofSize: 12, weight: .semibold)
    }
}

extension TimeTrackingHeaderLayoutVariant {
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

extension TimeTrackingHeaderChromeDensity {
    var iconButtonSize: CGFloat {
        switch self {
        case .regular:
            28
        case .compact:
            26
        }
    }
}

private extension TimeTrackingHeaderChipDensity {
    var chipHeight: CGFloat {
        switch self {
        case .regular:
            28
        case .compact:
            26
        }
    }

    func metrics(for bucket: TimeTrackingBucket) -> TimeTrackingHeaderChipMetrics {
        let isOtherChip = bucket == .other

        switch (self, isOtherChip) {
        case (.regular, false):
            return TimeTrackingHeaderChipMetrics(
                minimumWidth: 34,
                idealWidth: 48
            )
        case (.regular, true):
            return TimeTrackingHeaderChipMetrics(
                minimumWidth: 32,
                idealWidth: 44
            )
        case (.compact, false):
            return TimeTrackingHeaderChipMetrics(
                minimumWidth: 30,
                idealWidth: 42
            )
        case (.compact, true):
            return TimeTrackingHeaderChipMetrics(
                minimumWidth: 28,
                idealWidth: 38
            )
        }
    }
}

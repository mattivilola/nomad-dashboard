import NomadCore
import SwiftUI

public enum TimeTrackingInterruptionButtonStyle: Sendable {
    case compact
    case standard
    case prominent
}

public struct TimeTrackingInterruptionButton: View {
    private let title: String
    private let count: Int
    private let lastReportedAt: Date?
    private let isEnabled: Bool
    private let style: TimeTrackingInterruptionButtonStyle
    private let action: () -> Void

    @State private var flashProgress = 0.0

    public init(
        title: String,
        count: Int,
        lastReportedAt: Date?,
        isEnabled: Bool = true,
        style: TimeTrackingInterruptionButtonStyle = .standard,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.count = count
        self.lastReportedAt = lastReportedAt
        self.isEnabled = isEnabled
        self.style = style
        self.action = action
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: false)) { context in
            Button {
                triggerFlash()
                action()
            } label: {
                label(currentDate: context.date)
            }
            .buttonStyle(.plain)
            .disabled(isEnabled == false)
            .help(helpText)
            .accessibilityLabel(helpText)
        }
    }

    private func label(currentDate: Date) -> some View {
        let heat = interruptionHeat(at: currentDate)
        let metrics = styleMetrics

        return ZStack {
            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .fill(NomadTheme.sand.opacity(isEnabled ? metrics.baseBackgroundOpacity : 0.10))

            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .fill(NomadTheme.coral.opacity(isEnabled ? (metrics.hotBackgroundOpacity * heat) : 0))

            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .stroke(NomadTheme.sand.opacity(isEnabled ? metrics.baseStrokeOpacity : 0.28), lineWidth: 1)

            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .stroke(NomadTheme.coral.opacity(isEnabled ? (metrics.hotStrokeOpacity * heat) : 0), lineWidth: 1.1)

            flashOverlay(metrics: metrics)

            content(metrics: metrics, heat: heat)
        }
        .frame(minWidth: metrics.minimumWidth, minHeight: metrics.height)
        .scaleEffect(1 + (flashProgress * metrics.flashScale))
        .shadow(
            color: NomadTheme.coral.opacity((heat * 0.16) + (flashProgress * 0.18)),
            radius: metrics.shadowRadius,
            y: metrics.shadowYOffset
        )
        .opacity(isEnabled ? 1 : 0.76)
    }

    private func content(metrics: StyleMetrics, heat: Double) -> some View {
        Group {
            switch style {
            case .compact:
                HStack(spacing: 6) {
                    icon(metrics: metrics, heat: heat)
                    countBadge(metrics: metrics, heat: heat)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
            case .standard:
                HStack(spacing: 10) {
                    icon(metrics: metrics, heat: heat)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NomadTheme.primaryText.opacity(isEnabled ? 1 : 0.74))
                            .lineLimit(1)

                        Text(countLine)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(NomadTheme.secondaryText.opacity(isEnabled ? 1 : 0.72))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    countBadge(metrics: metrics, heat: heat)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            case .prominent:
                HStack(spacing: 14) {
                    icon(metrics: metrics, heat: heat)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(NomadTheme.primaryText.opacity(isEnabled ? 1 : 0.74))
                            .lineLimit(1)

                        Text(helpText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(NomadTheme.secondaryText.opacity(isEnabled ? 1 : 0.72))
                            .lineLimit(2)
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 4) {
                        countBadge(metrics: metrics, heat: heat)

                        if count > 0 {
                            Text("23m each")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(NomadTheme.secondaryText)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
    }

    private func icon(metrics: StyleMetrics, heat: Double) -> some View {
        ZStack {
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: metrics.iconSize, weight: .semibold))
                .foregroundStyle(NomadTheme.sand.opacity(isEnabled ? 0.92 : 0.42))

            Image(systemName: "bolt.circle.fill")
                .font(.system(size: metrics.iconSize, weight: .semibold))
                .foregroundStyle(NomadTheme.coral.opacity(isEnabled ? max(heat, flashProgress * 0.8) : 0))
        }
    }

    private func countBadge(metrics: StyleMetrics, heat: Double) -> some View {
        Text("\(count)")
            .font(metrics.countFont)
            .monospacedDigit()
            .foregroundStyle(NomadTheme.primaryText.opacity(isEnabled ? 1 : 0.74))
            .padding(.horizontal, metrics.badgeHorizontalPadding)
            .padding(.vertical, metrics.badgeVerticalPadding)
            .background(
                Capsule(style: .continuous)
                    .fill(NomadTheme.cardBackground.opacity(0.82))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(NomadTheme.coral.opacity(isEnabled ? (0.18 + (heat * 0.30)) : 0.10), lineWidth: 1)
                    )
            )
    }

    private func flashOverlay(metrics: StyleMetrics) -> some View {
        RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
            .fill(NomadTheme.coral.opacity(flashProgress * 0.16))
            .overlay(
                RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                    .stroke(NomadTheme.coral.opacity(flashProgress * 0.55), lineWidth: 1.6)
                    .scaleEffect(1 + (flashProgress * 0.08))
            )
    }

    private func triggerFlash() {
        guard isEnabled else {
            return
        }

        withAnimation(.easeOut(duration: 0.14)) {
            flashProgress = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            withAnimation(.easeOut(duration: 0.7)) {
                flashProgress = 0
            }
        }
    }

    private func interruptionHeat(at currentDate: Date) -> Double {
        guard let lastReportedAt else {
            return 0
        }

        let elapsed = max(currentDate.timeIntervalSince(lastReportedAt), 0)
        let ratio = 1 - min(elapsed / TimeTrackingFocusMetrics.interruptionRecoveryDuration, 1)
        return max(ratio, 0)
    }

    private var countLine: String {
        count == 1 ? "1 interruption today" : "\(count) interruptions today"
    }

    private var helpText: String {
        if count == 0 {
            return "Report an interruption. Focus cooldown assumes 23 minutes per interruption."
        }

        return "\(countLine.capitalized). Estimated focus loss \(focusLossText)."
    }

    private var focusLossText: String {
        let minutes = Int(TimeTrackingFocusMetrics.estimatedFocusLoss(for: count) / 60)
        let hours = minutes / 60
        let remainder = minutes % 60

        if hours == 0 {
            return "\(remainder)m"
        }

        if remainder == 0 {
            return "\(hours)h"
        }

        return "\(hours)h \(remainder)m"
    }

    private var styleMetrics: StyleMetrics {
        switch style {
        case .compact:
            StyleMetrics(
                minimumWidth: 54,
                height: 32,
                cornerRadius: 16,
                iconSize: 13,
                countFont: .caption.weight(.semibold),
                badgeHorizontalPadding: 7,
                badgeVerticalPadding: 3,
                baseBackgroundOpacity: 0.18,
                hotBackgroundOpacity: 0.44,
                baseStrokeOpacity: 0.34,
                hotStrokeOpacity: 0.42,
                flashScale: 0.02,
                shadowRadius: 8,
                shadowYOffset: 2
            )
        case .standard:
            StyleMetrics(
                minimumWidth: 176,
                height: 48,
                cornerRadius: 18,
                iconSize: 15,
                countFont: .caption.weight(.semibold),
                badgeHorizontalPadding: 8,
                badgeVerticalPadding: 4,
                baseBackgroundOpacity: 0.18,
                hotBackgroundOpacity: 0.40,
                baseStrokeOpacity: 0.34,
                hotStrokeOpacity: 0.40,
                flashScale: 0.025,
                shadowRadius: 10,
                shadowYOffset: 3
            )
        case .prominent:
            StyleMetrics(
                minimumWidth: 280,
                height: 84,
                cornerRadius: 24,
                iconSize: 26,
                countFont: .headline.weight(.bold),
                badgeHorizontalPadding: 11,
                badgeVerticalPadding: 6,
                baseBackgroundOpacity: 0.22,
                hotBackgroundOpacity: 0.48,
                baseStrokeOpacity: 0.38,
                hotStrokeOpacity: 0.46,
                flashScale: 0.03,
                shadowRadius: 16,
                shadowYOffset: 5
            )
        }
    }
}

private struct StyleMetrics {
    let minimumWidth: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    let iconSize: CGFloat
    let countFont: Font
    let badgeHorizontalPadding: CGFloat
    let badgeVerticalPadding: CGFloat
    let baseBackgroundOpacity: Double
    let hotBackgroundOpacity: Double
    let baseStrokeOpacity: Double
    let hotStrokeOpacity: Double
    let flashScale: CGFloat
    let shadowRadius: CGFloat
    let shadowYOffset: CGFloat
}

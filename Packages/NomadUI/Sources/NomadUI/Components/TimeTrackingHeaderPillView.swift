import NomadCore
import SwiftUI

/// One compact, never-truncating row: status dot and pending time, play/pause (and stop
/// while paused), the interruption button and an Allocate menu. Project names live in the
/// menu so they cannot be cut off.
struct TimeTrackingHeaderPillView: View {
    private static let maxAllocateProjectCount = 5
    private static let contentHeight: CGFloat = 28
    private static let controlSize: CGFloat = 28

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
        HStack(spacing: 6) {
            statusView

            HStack(spacing: 6) {
                ForEach(presentation.visibleHeaderControls, id: \.title) { control in
                    iconButton(title: control.title, systemImage: control.systemImage) {
                        switch control.kind {
                        case .primary:
                            primaryAction()
                        case .stop:
                            stopAction()
                        }
                    }
                }
            }

            TimeTrackingInterruptionButton(
                title: "Report interruption",
                count: interruptionCount,
                lastReportedAt: lastInterruptionAt,
                isEnabled: true,
                style: .compact,
                action: interruptionAction
            )
            .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 6)

            allocateMenu
        }
        .frame(height: Self.contentHeight)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Capsule(style: .continuous)
                .fill(NomadTheme.chartBackground.opacity(0.95))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(NomadTheme.cardBorder.opacity(0.92), lineWidth: 1)
                )
        )
    }

    private var statusView: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusTint)
                .frame(width: 8, height: 8)

            Text("Pending \(presentation.pendingDurationText)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NomadTheme.primaryText)
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(presentation.activityTitle), \(presentation.pendingDurationText) pending")
    }

    private var statusTint: Color {
        switch presentation.activityState {
        case .running:
            NomadTheme.teal
        case .paused:
            NomadTheme.sand
        case .stopped:
            NomadTheme.tertiaryText
        }
    }

    private var allocateMenu: some View {
        Menu {
            ForEach(presentation.allocateMenuChips(maxProjectCount: Self.maxAllocateProjectCount)) { chip in
                Button(chip.title) {
                    allocateAction(chip.bucket)
                }
                .disabled(chipsEnabled == false)
            }

            Divider()

            Button(presentation.openTitle, systemImage: presentation.openSystemImage) {
                openAction()
            }
        } label: {
            HStack(spacing: 4) {
                Text("Allocate")
                    .font(.caption.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(NomadTheme.primaryText)
            .padding(.horizontal, 10)
            .frame(height: Self.controlSize)
            .background(
                Capsule(style: .continuous)
                    .fill(NomadTheme.inlineButtonBackground.opacity(0.95))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(NomadTheme.cardBorder.opacity(0.92), lineWidth: 1)
                    )
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Allocate pending time")
        .accessibilityLabel("Allocate pending time")
    }

    private func iconButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NomadTheme.primaryText)
                .frame(width: Self.controlSize, height: Self.controlSize)
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

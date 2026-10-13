import NomadCore
import SwiftUI

/// One compact row shown while the Mac is kept awake: the time left (or elapsed) and a stop button.
struct KeepAwakeHeaderPillView: View {
    private static let contentHeight: CGFloat = 28
    private static let controlSize: CGFloat = 28
    private static let stopTitle = "Stop keeping awake"

    let session: KeepAwakeSession
    let lidClosedState: KeepAwakeLidClosedState
    let allowLidClosedAction: () -> Void
    let stopAction: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "cup.and.heat.waves.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NomadTheme.teal)
                .accessibilityHidden(true)

            // Only the text re-renders every second, and only while a session is running.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(KeepAwakePresentation(session: session).statusText(at: context.date))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(NomadTheme.primaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            lidClosedIndicator

            stopButton
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

    @ViewBuilder
    private var lidClosedIndicator: some View {
        switch KeepAwakeLidClosedPresentation(state: lidClosedState).indicator {
        case let .icon(systemImage, isHighlighted, help):
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isHighlighted ? NomadTheme.teal : NomadTheme.tertiaryText)
                .frame(width: Self.controlSize, height: Self.controlSize)
                .help(help)
                .accessibilityLabel(help)
        case .allowButton:
            Button(action: allowLidClosedAction) {
                Text(KeepAwakeLidClosedPresentation.allowButtonTitle)
                    .font(.caption.weight(.semibold))
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
            .buttonStyle(.plain)
            .fixedSize()
            .help(KeepAwakeLidClosedPresentation.allowButtonHelp)
            .accessibilityLabel(KeepAwakeLidClosedPresentation.allowButtonTitle)
        case nil:
            EmptyView()
        }
    }

    private var stopButton: some View {
        Button(action: stopAction) {
            Image(systemName: "stop.fill")
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
        .help(Self.stopTitle)
        .accessibilityLabel(Self.stopTitle)
    }
}

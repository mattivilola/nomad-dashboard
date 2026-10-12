import SwiftUI

enum DashboardInlineButtonRole {
    /// Teal label: the primary inline action of a card ("Open Settings", "More details").
    case highlighted
    /// Primary-text label: secondary inline actions that sit beside a highlighted one.
    case neutral
}

/// Colors of an inline dashboard action. Explicit theme colors keep the look identical
/// in light and dark appearance and make it testable.
struct DashboardInlineButtonAppearance: Equatable {
    let foreground: Color
    let background: Color
    let border: Color

    static func make(
        role: DashboardInlineButtonRole,
        isEnabled: Bool
    ) -> DashboardInlineButtonAppearance {
        let foreground: Color = switch role {
        case .highlighted:
            NomadTheme.teal
        case .neutral:
            NomadTheme.primaryText
        }

        return DashboardInlineButtonAppearance(
            foreground: foreground.opacity(isEnabled ? 1 : 0.72),
            background: NomadTheme.inlineButtonBackground.opacity(isEnabled ? 1 : 0.76),
            border: NomadTheme.cardBorder.opacity(isEnabled ? 1 : 0.76)
        )
    }
}

struct DashboardInlineButtonLayout: Equatable {
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let fillsAvailableWidth: Bool

    static func make(
        isCompact: Bool,
        fillsAvailableWidth: Bool
    ) -> DashboardInlineButtonLayout {
        DashboardInlineButtonLayout(
            horizontalPadding: isCompact ? 10 : 12,
            verticalPadding: isCompact ? 6 : 7,
            fillsAvailableWidth: fillsAvailableWidth
        )
    }
}

/// The one button style for every inline action inside the dashboard cards: teal caption
/// text on the inline button background in a rounded rectangle. Replaces the mix of
/// system links, prominent buttons and per-feature capsules.
struct DashboardInlineButtonStyle: ButtonStyle {
    var role: DashboardInlineButtonRole = .highlighted
    var isCompact = false
    var fillsAvailableWidth = false

    func makeBody(configuration: Configuration) -> some View {
        InlineButtonLabel(
            configuration: configuration,
            role: role,
            layout: .make(isCompact: isCompact, fillsAvailableWidth: fillsAvailableWidth)
        )
    }

    private struct InlineButtonLabel: View {
        let configuration: ButtonStyleConfiguration
        let role: DashboardInlineButtonRole
        let layout: DashboardInlineButtonLayout

        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let appearance = DashboardInlineButtonAppearance.make(role: role, isEnabled: isEnabled)
            let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

            configuration.label
                .font(.caption.weight(.semibold))
                .foregroundStyle(appearance.foreground)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.vertical, layout.verticalPadding)
                .frame(maxWidth: layout.fillsAvailableWidth ? .infinity : nil, alignment: .center)
                .background(
                    shape
                        .fill(appearance.background)
                        .overlay(shape.stroke(appearance.border, lineWidth: 1))
                )
                .opacity(configuration.isPressed ? 0.78 : 1)
                .contentShape(shape)
        }
    }
}

extension ButtonStyle where Self == DashboardInlineButtonStyle {
    static var dashboardInline: DashboardInlineButtonStyle {
        DashboardInlineButtonStyle()
    }

    static func dashboardInline(
        role: DashboardInlineButtonRole = .highlighted,
        isCompact: Bool = false,
        fillsAvailableWidth: Bool = false
    ) -> DashboardInlineButtonStyle {
        DashboardInlineButtonStyle(role: role, isCompact: isCompact, fillsAvailableWidth: fillsAvailableWidth)
    }
}

/// Square icon chip shared by the row-level icon actions (copy, map, "more" menus).
struct DashboardIconChip: View {
    let systemImage: String
    var isEnabled = true

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(NomadTheme.actionIconForeground.opacity(isEnabled ? 1 : 0.55))
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(NomadTheme.inlineButtonBackground.opacity(isEnabled ? 1 : 0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(NomadTheme.cardBorder.opacity(isEnabled ? 1 : 0.7), lineWidth: 1)
                    )
            )
    }
}

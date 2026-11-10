import SwiftUI

/// The one scaffold for dashboard detail dialogs (map previews, alert details, ...): a header with a
/// trailing close button, the content, and a footer row of actions. Sheets supply the slots so they
/// all share spacing, background and the Escape-to-close behaviour instead of re-implementing them.
public struct DashboardDetailSheet<Header: View, Content: View, Actions: View>: View {
    private let minWidth: CGFloat
    private let minHeight: CGFloat
    private let maxHeight: CGFloat?
    private let header: Header
    private let content: Content
    private let actions: Actions

    @Environment(\.dismiss) private var dismiss

    public init(
        minWidth: CGFloat = 460,
        minHeight: CGFloat = 420,
        maxHeight: CGFloat? = nil,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
        @ViewBuilder actions: () -> Actions
    ) {
        self.minWidth = minWidth
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.header = header()
        self.content = content()
        self.actions = actions()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                header
                    .frame(maxWidth: .infinity, alignment: .leading)

                closeButton
            }

            content

            HStack(spacing: 10) {
                actions
            }
        }
        .padding(20)
        .frame(minWidth: minWidth, minHeight: minHeight, maxHeight: maxHeight, alignment: .topLeading)
        .background(NomadTheme.background)
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NomadTheme.actionIconForeground)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(NomadTheme.actionIconBackground)
                        .overlay(Circle().stroke(NomadTheme.actionIconBorder, lineWidth: 1))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel("Close")
        .help("Close")
    }
}

/// The standard header of a `DashboardDetailSheet`: a rounded title, an optional subtitle, extra
/// lines under them (a colored kind label, an address) and an optional trailing accessory such as
/// a price or a status badge.
public struct DashboardDetailTitleHeader<Details: View, Accessory: View>: View {
    private let title: String
    private let subtitle: String?
    private let details: Details
    private let accessory: Accessory

    public init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder details: () -> Details,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.details = details()
        self.accessory = accessory()
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(NomadTheme.primaryText)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(NomadTheme.secondaryText)
                }

                details
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            accessory
        }
    }
}

public extension DashboardDetailTitleHeader where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder details: () -> Details) {
        self.init(title: title, subtitle: subtitle, details: details, accessory: { EmptyView() })
    }
}

public extension DashboardDetailTitleHeader where Details == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.init(title: title, subtitle: subtitle, details: { EmptyView() }, accessory: accessory)
    }
}

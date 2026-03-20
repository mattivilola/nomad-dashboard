import SwiftUI

public enum StatusSymbolTreatment: Equatable, Sendable {
    case plain
    case warningBadge
}

public enum StatusSymbolSize: Sendable {
    case menuBar
    case panel
}

public struct StatusSymbolView: View {
    public let systemName: String
    public let treatment: StatusSymbolTreatment
    public let size: StatusSymbolSize
    public let foregroundColor: Color?

    public init(
        systemName: String,
        treatment: StatusSymbolTreatment = .plain,
        size: StatusSymbolSize = .panel,
        foregroundColor: Color? = nil
    ) {
        self.systemName = systemName
        self.treatment = treatment
        self.size = size
        self.foregroundColor = foregroundColor
    }

    public var body: some View {
        switch treatment {
        case .plain:
            symbolImage
                .foregroundStyle(foregroundColor ?? Color.primary)
        case .warningBadge:
            symbolImage
                .foregroundStyle(Color.white.opacity(0.98))
                .padding(.horizontal, size.horizontalPadding)
                .padding(.vertical, size.verticalPadding)
                .background(
                    Capsule(style: .continuous)
                        .fill(NomadTheme.coral.opacity(0.96))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.75)
                )
                .compositingGroup()
        }
    }

    private var symbolImage: some View {
        Image(systemName: systemName)
            .font(size.font)
    }
}

private extension StatusSymbolSize {
    var font: Font {
        switch self {
        case .menuBar:
            .system(size: 11.5, weight: .semibold)
        case .panel:
            .caption2.weight(.semibold)
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .menuBar:
            4.5
        case .panel:
            4
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .menuBar:
            2.5
        case .panel:
            2
        }
    }
}

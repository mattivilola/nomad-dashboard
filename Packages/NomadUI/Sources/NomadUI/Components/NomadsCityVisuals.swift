import NomadCore
import SwiftUI

/// A city photograph with a native, branded fallback when Nomads.com has no usable image.
public struct NomadsCityPhoto: View {
    private let cityName: String
    private let imageURL: URL?
    private let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(cityName: String, imageURL: URL?, height: CGFloat) {
        self.cityName = cityName
        self.imageURL = imageURL
        self.height = height
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let imageURL {
                    AsyncImage(url: imageURL, transaction: Transaction(animation: reduceMotion ? nil : .easeInOut(duration: 0.2))) { phase in
                        switch phase {
                        case let .success(image):
                            image
                                .resizable()
                                .scaledToFill()
                                .transition(.opacity)
                        case .empty:
                            fallback.overlay { ProgressView().tint(.white) }
                        default:
                            fallback
                        }
                    }
                } else {
                    fallback
                }
            }
            // A loaded image must crop to the proposed card size instead of
            // imposing its aspect-ratio width on the surrounding scroll view.
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [
                    NomadTheme.teal.opacity(0.95),
                    NomadTheme.coral.opacity(0.8),
                    NomadTheme.sand.opacity(0.85)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "globe.europe.africa.fill")
                .font(.system(size: min(height * 0.42, 76), weight: .light))
                .foregroundStyle(.white.opacity(0.82))
                .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
        }
    }
}

public struct NomadsCityResultCard: View {
    private let city: NomadsCity
    private let directoryCity: NomadsDirectoryCity?
    private let isSelected: Bool
    private let action: () -> Void

    public init(
        city: NomadsCity,
        directoryCity: NomadsDirectoryCity?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.city = city
        self.directoryCity = directoryCity
        self.isSelected = isSelected
        self.action = action
    }

    private var imageURL: URL? {
        directoryCity?.imageURL ?? directoryCity?.largeImageURL
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    NomadsCityPhoto(cityName: city.name, imageURL: imageURL, height: 136)
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.75)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(city.name)
                            .font(.headline.weight(.bold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.80)
                        Text(city.country).font(.caption.weight(.medium)).lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                    .padding(8)
                    .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(10)
                }

                HStack(spacing: 8) {
                    Label(compactMonthlyCost, systemImage: "dollarsign.circle")
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Label(compactInternet, systemImage: "wifi")
                        .lineLimit(1)
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(NomadTheme.secondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(NomadTheme.cardBackground)
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? NomadTheme.teal : NomadTheme.cardBorder, lineWidth: isSelected ? 2 : 1)
            }
            .shadow(color: .black.opacity(isSelected ? 0.15 : 0.07), radius: isSelected ? 8 : 3, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(city.name), \(city.country). \(NomadsCityFormatting.monthlyUSD(city.costForNomadUSDPerMonth)). \(NomadsCityFormatting.internet(city.internetMbps))"
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var compactMonthlyCost: String {
        guard let amount = city.costForNomadUSDPerMonth, amount.isFinite, amount > 0 else {
            return "Cost n/a"
        }
        return amount.formatted(.currency(code: "USD").precision(.fractionLength(0))) + "/mo"
    }

    private var compactInternet: String {
        guard let speed = city.internetMbps, speed.isFinite, speed > 0 else {
            return "Net n/a"
        }
        return speed.formatted(.number.precision(.fractionLength(0))) + " Mbps"
    }
}

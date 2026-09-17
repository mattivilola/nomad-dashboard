import Foundation
import NomadCore
import SwiftUI

struct NomadsCityDetailView: View {
    let city: NomadsCity
    let provider: NomadsCityProvider
    let directoryCity: NomadsDirectoryCity?
    let loadsDetails: Bool
    let matchDescription: String?

    @State private var detail: NomadsCity?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var retryID = UUID()

    init(
        city: NomadsCity,
        provider: NomadsCityProvider,
        directoryCity: NomadsDirectoryCity? = nil,
        loadsDetails: Bool = true,
        matchDescription: String? = nil
    ) {
        self.city = city
        self.provider = provider
        self.directoryCity = directoryCity
        self.loadsDetails = loadsDetails
        self.matchDescription = matchDescription
    }

    private var displayedCity: NomadsCity {
        guard let detail, detail.slug == city.slug else { return city }
        return detail
    }

    private var imageURL: URL? {
        directoryCity?.largeImageURL ?? directoryCity?.imageURL
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Color.clear.frame(height: 0).id("city-detail-top")
                        cityHero
                        NomadsSourceCredit(cityURL: displayedCity.cityURL ?? city.cityURL, includesPhotos: true)
                        remoteWorkSignals
                        costEstimates
                        meetupSection
                        dataNote
                    }
                    .frame(width: max(0, min(viewport.size.width, 900) - 48), alignment: .leading)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: city.slug, initial: true) {
                    proxy.scrollTo("city-detail-top", anchor: .top)
                }
            }
        }
        .id(city.slug)
        .task(id: "\(city.slug)-\(retryID)-\(loadsDetails)") {
            guard loadsDetails else {
                detail = nil
                errorMessage = nil
                isLoading = false
                return
            }

            detail = nil
            errorMessage = nil
            isLoading = true
            do {
                let response = try await provider.city(slug: city.slug)
                guard !Task.isCancelled else { return }
                detail = response
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
            guard !Task.isCancelled else { return }
            isLoading = false
        }
    }

    private var cityHero: some View {
        ZStack(alignment: .bottomLeading) {
            NomadsCityPhoto(cityName: city.name, imageURL: imageURL, height: 270)
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.70)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 7) {
                if let matchDescription, !matchDescription.isEmpty {
                    Text(matchDescription)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.35), in: Capsule())
                }
                Text(city.name)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .lineLimit(2)
                Text(city.country)
                    .font(.title3.weight(.medium))
                if let url = displayedCity.cityURL ?? city.cityURL {
                    Link(destination: url) {
                        Label("View \(city.name) on Nomads.com", systemImage: "arrow.up.right.square")
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .padding(22)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(NomadTheme.cardBorder.opacity(0.75), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var remoteWorkSignals: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label("Remote work signals", systemImage: "wifi")
                    .font(.title3.weight(.bold))
                Spacer()
                if isLoading {
                    ProgressView().controlSize(.small)
                }
            }

            HStack(spacing: 12) {
                CitySignalTile(
                    title: "Internet",
                    value: NomadsCityFormatting.internet(displayedCity.internetMbps),
                    symbol: "wifi",
                    tint: NomadTheme.teal
                )
                CitySignalTile(
                    title: "Overall",
                    value: NomadsCityFormatting.score(displayedCity.overallScore),
                    symbol: "sparkles",
                    tint: NomadTheme.coral
                )
            }

            VStack(spacing: 11) {
                CityRatingBar(title: "Safety", score: displayedCity.safetyScore, tint: NomadTheme.teal)
                CityRatingBar(title: "Walkability", score: displayedCity.walkabilityScore, tint: NomadTheme.sand)
                CityRatingBar(title: "English speaking", score: displayedCity.englishSpeakingScore, tint: NomadTheme.coral)
            }
        }
        .cityCard()
    }

    private var costEstimates: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Monthly reference estimates", systemImage: "dollarsign.circle")
                .font(.title3.weight(.bold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 10)], spacing: 10) {
                CityCostTile(
                    title: "Nomad lifestyle",
                    value: NomadsCityFormatting.monthlyUSD(displayedCity.costForNomadUSDPerMonth),
                    symbol: "suitcase.rolling",
                    tint: NomadTheme.coral
                )
                CityCostTile(
                    title: "1-bedroom, centre",
                    value: NomadsCityFormatting.monthlyUSD(displayedCity.rent1brCenterUSDPerMonth),
                    symbol: "building.2",
                    tint: NomadTheme.teal
                )
                CityCostTile(
                    title: "Coworking",
                    value: NomadsCityFormatting.monthlyUSD(displayedCity.coworkingUSDPerMonth),
                    symbol: "laptopcomputer",
                    tint: NomadTheme.sand
                )
            }
        }
        .cityCard()
    }

    private var meetupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Next meetup", systemImage: "person.2.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(NomadTheme.coral)
                Spacer()
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(NomadTheme.teal)
            }
            if isLoading {
                ProgressView("Checking city details…").controlSize(.small)
            } else if let errorMessage {
                Text("City details couldn't be updated. The search estimates remain available.")
                    .foregroundStyle(NomadTheme.secondaryText)
                Text(errorMessage).font(.caption).foregroundStyle(.secondary)
                Button("Try city details again") { retryID = UUID() }
                    .buttonStyle(.bordered)
            } else if let meetup = displayedCity.nextMeetup,
                      NomadsCityMeetupPresentation.isUpcoming(dateString: meetup.date)
            {
                Text(meetup.name).font(.headline)
                HStack(spacing: 5) {
                    Text(meetup.date)
                    if let people = meetup.peopleGoing, people >= 0 {
                        Text("• \(people) going")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(NomadTheme.secondaryText)
                if let url = meetup.meetupURL {
                    Link("View meetup on Nomads.com", destination: url)
                        .font(.subheadline.weight(.semibold))
                }
            } else {
                Text(loadsDetails ? "No upcoming meetup was returned for this city." : "No upcoming meetup in this saved city result.")
                    .foregroundStyle(NomadTheme.secondaryText)
            }
        }
        .cityCard(accent: NomadTheme.coral)
    }

    private var dataNote: some View {
        Text("Estimates and community ratings are reference signals, not live measurements or travel advice. Confirm prices, connection quality, and event details before booking.")
            .font(.caption)
            .foregroundStyle(NomadTheme.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

private struct CitySignalTile: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.13), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(NomadTheme.secondaryText)
                Text(value).font(.headline)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NomadTheme.tileBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct CityRatingBar: View {
    let title: String
    let score: Double?
    let tint: Color

    private var normalizedScore: Double {
        guard let score, score.isFinite, (0...5).contains(score) else { return 0 }
        return score / 5
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(.subheadline).frame(width: 110, alignment: .leading)
            GeometryReader { proxy in
                Capsule()
                    .fill(NomadTheme.cardBorder.opacity(0.8))
                    .overlay(alignment: .leading) {
                        Capsule().fill(tint).frame(width: proxy.size.width * normalizedScore)
                    }
            }
            .frame(height: 7)
            Text(NomadsCityFormatting.score(score))
                .font(.caption.weight(.semibold))
                .foregroundStyle(NomadTheme.secondaryText)
                .frame(width: 72, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CityCostTile: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(title).font(.caption).foregroundStyle(NomadTheme.secondaryText)
            Text(value).font(.subheadline.weight(.semibold)).lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .padding(12)
        .background(NomadTheme.tileBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private extension View {
    func cityCard(accent: Color? = nil) -> some View {
        padding(18)
            .background(NomadTheme.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(accent?.opacity(0.35) ?? NomadTheme.cardBorder.opacity(0.9), lineWidth: 1)
            }
    }
}

enum NomadsCityMeetupPresentation {
    static func isUpcoming(
        dateString: String,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        let parts = dateString.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else {
            return false
        }

        let components = DateComponents(year: year, month: month, day: day)
        guard let meetupDay = calendar.date(from: components) else { return false }
        let normalized = calendar.dateComponents([.year, .month, .day], from: meetupDay)
        guard normalized == components else { return false }
        return meetupDay >= calendar.startOfDay(for: now)
    }
}

import NomadCore
import SwiftUI

public struct NomadsCityExplorerView: View {
    private let provider: NomadsCityProvider
    @ObservedObject private var currentCity: NomadsCurrentCityController
    @State private var mode: ExplorerMode = .current
    @State private var country = ""
    @State private var maximumCost = 0
    @State private var minimumInternet = 0
    @State private var result: NomadsSearchResult?
    @State private var resultScope = "Worldwide"
    @State private var selectedSlug: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    public init(provider: NomadsCityProvider, currentCity: NomadsCurrentCityController) {
        self.provider = provider
        self.currentCity = currentCity
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.5)
            if mode == .search {
                searchControls
            }
            HSplitView {
                destinationBrowser.frame(minWidth: 360, idealWidth: 470, maxWidth: 560)
                detailPane.frame(minWidth: 410, maxWidth: .infinity, maxHeight: .infinity)
            }
            footer
        }
        .background(NomadTheme.background.opacity(0.48))
        .tint(NomadTheme.teal)
        .frame(minWidth: 900, minHeight: 630)
        .onDisappear {
            searchTask?.cancel()
            isLoading = false
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "globe.europe.africa.fill")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(NomadTheme.coral)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Explore cities").font(.title2.weight(.bold))
                Text(mode == .current ? "A local view of your current stop." : "Find a destination that fits your work and budget.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 15)
            Picker("Destination view", selection: $mode) {
                Label("Around me", systemImage: "location.fill").tag(ExplorerMode.current)
                Label("Discover", systemImage: "globe").tag(ExplorerMode.search)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 235)
        }
        .padding(.horizontal, 24).padding(.vertical, 20)
    }

    private var searchControls: some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("COUNTRY").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                TextField("Anywhere · e.g. Portugal", text: $country)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Country, blank for worldwide")
                    .onSubmit(search)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("MONTHLY BUDGET · USD").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Picker("Monthly budget in USD", selection: $maximumCost) {
                    Text("Any budget").tag(0)
                    ForEach([1_500, 2_000, 3_000, 4_000, 5_000, 7_500], id: \.self) { amount in
                        Text("Up to \(amount.formatted())").tag(amount)
                    }
                }.labelsHidden().frame(width: 155)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("CITY INTERNET").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Picker("Minimum city internet speed", selection: $minimumInternet) {
                    Text("Any speed").tag(0)
                    ForEach([25, 50, 100, 200], id: \.self) { speed in
                        Text("\(speed)+ Mbps").tag(speed)
                    }
                }.labelsHidden().frame(width: 130)
            }
            Button(action: search) {
                Label(isLoading ? "Searching…" : "Find cities", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .disabled(isLoading)
        .padding(.horizontal, 24).padding(.vertical, 16)
    }

    @ViewBuilder
    private var destinationBrowser: some View {
        if mode == .current {
            currentDestination
        } else {
            searchDestinations
        }
    }

    private var currentDestination: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label("AROUND YOU", systemImage: "location.fill")
                        .font(.caption.weight(.bold)).foregroundStyle(NomadTheme.teal)
                    Spacer()
                    Toggle("Follow my city", isOn: $currentCity.enabled)
                        .toggleStyle(.switch).controlSize(.small)
                        .help("Match your dashboard location locally. Check again only when your city changes, or when you choose Retry.")
                }
                if !currentCity.enabled {
                    ContentUnavailableView("Automatic matching is off", systemImage: "location.slash", description: Text("Turn on Follow my city to find your current destination. You can still search in Discover."))
                } else if currentCity.isLoading {
                    ProgressView("Finding your city…").frame(maxWidth: .infinity).padding(.vertical, 40)
                } else if let city = currentCity.matchedCity, let match = currentCity.match {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(currentCity.currentLocationName ?? city.name).font(.title3.weight(.semibold))
                        Text(match.isNearby ? "Closest listed destination within 50 km" : "Your city is on Nomads.com")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    NomadsCityResultCard(city: city, directoryCity: match.directoryCity, isSelected: true, action: {})
                        .allowsHitTesting(false)
                    if match.isNearby, let distance = match.distanceKilometers {
                        Label("\(distance.formatted(.number.precision(.fractionLength(0)))) km from your dashboard location", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.subheadline).foregroundStyle(NomadTheme.teal)
                    }
                    Text("This result stays saved while you're in the same city.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let error = currentCity.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(NomadTheme.coral)
                    }
                } else if let error = currentCity.errorMessage {
                    ContentUnavailableView("City check unavailable", systemImage: "wifi.exclamationmark", description: Text(error))
                    Button("Retry city check") { currentCity.retry() }.buttonStyle(.bordered)
                } else if currentCity.state == .notFound, let name = currentCity.currentLocationName {
                    ContentUnavailableView("No nearby city listed", systemImage: "mappin.slash", description: Text("No match for \(name) or within 50 km. We'll check again when your city changes."))
                    Button("Discover other cities") { mode = .search }.buttonStyle(.borderedProminent)
                } else {
                    ContentUnavailableView("Waiting for your city", systemImage: "location.magnifyingglass", description: Text("Use device location or external IP location in the dashboard. You can also browse destinations in Discover."))
                }
                if currentCity.enabled {
                    Text("Uses your dashboard's device location, or its approximate IP location when needed. Coordinates stay on your Mac.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
        }
    }

    private var searchDestinations: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoading {
                ProgressView("Finding destinations…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Search unavailable", systemImage: "wifi.exclamationmark")
                } description: { Text(errorMessage) } actions: { Button("Try again", action: search) }
            } else if let result {
                HStack {
                    Text(resultScope).font(.headline)
                    Spacer()
                    Text("\(result.cities.count) destinations").font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 20).padding(.vertical, 14)
                if result.cities.isEmpty {
                    ContentUnavailableView("No matching cities", systemImage: "magnifyingglass", description: Text("Try a higher budget, lower internet minimum, or another country."))
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 195), spacing: 14)], spacing: 16) {
                            ForEach(result.cities) { city in
                                NomadsCityResultCard(
                                    city: city,
                                    directoryCity: directoryCity(for: city.slug),
                                    isSelected: selectedSlug == city.slug
                                ) { selectedSlug = city.slug }
                            }
                        }.padding(.horizontal, 18).padding(.bottom, 20)
                    }
                }
            } else {
                ContentUnavailableView("Where to next?", systemImage: "globe.europe.africa", description: Text("Choose a country or search worldwide. Compare up to 20 destinations in Nomads.com's ranking order."))
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var detailPane: some View {
        if mode == .current, currentCity.enabled, !currentCity.isLoading,
           let city = currentCity.matchedCity, let match = currentCity.match
        {
            NomadsCityDetailView(
                city: city,
                provider: provider,
                directoryCity: match.directoryCity,
                loadsDetails: false,
                matchDescription: match.isNearby ? "Near \(currentCity.currentLocationName ?? "your location")" : "Your current city"
            )
            .id("current-\(city.slug)")
        } else if mode == .search, let city = result?.cities.first(where: { $0.slug == selectedSlug }) {
            NomadsCityDetailView(city: city, provider: provider, directoryCity: directoryCity(for: city.slug))
                .id("search-\(city.slug)")
        } else {
            VStack(spacing: 16) {
                Image(systemName: "map.fill").font(.system(size: 62, weight: .light)).foregroundStyle(NomadTheme.teal.opacity(0.7))
                Text("A place to live. A place to work.").font(.title3.weight(.semibold))
                Text("City costs, work signals, and people to meet.").font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Link("Data & photos from Nomads.com", destination: URL(string: "https://nomads.com")!)
            Spacer()
            if let date = mode == .current ? currentCity.checkedAt : result?.fetchedAt {
                Text("\(mode == .current ? "City checked" : "Search retrieved") \(date.formatted(date: .abbreviated, time: .shortened))")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption).padding(.horizontal, 20).padding(.vertical, 12)
        .background(.bar)
    }

    private func directoryCity(for slug: String) -> NomadsDirectoryCity? {
        currentCity.directory.first { $0.slug == slug || $0.shortSlug == slug }
    }

    private func search() {
        guard !isLoading else { return }
        searchTask?.cancel()
        let query = NomadsCitySearch(country: country, maxCostUSD: maximumCost == 0 ? nil : maximumCost, minInternetMbps: minimumInternet == 0 ? nil : minimumInternet)
        let trimmedCountry = country.trimmingCharacters(in: .whitespacesAndNewlines)
        resultScope = trimmedCountry.isEmpty ? "Worldwide" : trimmedCountry
        result = nil
        selectedSlug = nil
        errorMessage = nil
        isLoading = true
        searchTask = Task { @MainActor in
            async let directoryLoad: Void = currentCity.loadDirectory()
            do {
                let response = try await provider.search(query)
                guard !Task.isCancelled else { return }
                result = response
                selectedSlug = response.cities.first?.slug
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
            isLoading = false
            await directoryLoad
        }
    }
}

private enum ExplorerMode: Hashable {
    case current
    case search
}

enum NomadsCityFormatting {
    static func monthlyUSD(_ amount: Double?) -> String {
        guard let amount, amount.isFinite, amount > 0 else { return "Not available" }
        return amount.formatted(.currency(code: "USD").precision(.fractionLength(0))) + " / month"
    }

    static func score(_ value: Double?) -> String {
        guard let value, value.isFinite, (0...5).contains(value) else { return "Not available" }
        return value.formatted(.number.precision(.fractionLength(1))) + " / 5"
    }

    static func internet(_ speed: Double?) -> String {
        guard let speed, speed.isFinite, speed > 0 else { return "Not available" }
        return speed.formatted(.number.precision(.fractionLength(0))) + " Mbps"
    }
}

import Foundation

public struct NomadsMeetup: Codable, Sendable, Hashable {
    public let name: String
    public let date: String
    public let peopleGoing: Int?
    public let url: URL?

    public var meetupURL: URL? {
        url
    }

    private enum CodingKeys: String, CodingKey {
        case name, date, url
        case peopleGoing = "people_going"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        date = try container.decode(String.self, forKey: .date)
        peopleGoing = try container.decodeIfPresent(Int.self, forKey: .peopleGoing)
        url = try Self.trustedURL(container.decodeIfPresent(String.self, forKey: .url))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(peopleGoing, forKey: .peopleGoing)
        try container.encodeIfPresent(url?.absoluteString, forKey: .url)
    }
}

public struct NomadsCity: Codable, Sendable, Identifiable, Hashable {
    public let slug: String
    public let name: String
    public let country: String
    public let url: URL?
    public let overallScore: Double?
    public let costForNomadUSDPerMonth: Double?
    public let rent1brCenterUSDPerMonth: Double?
    public let coworkingUSDPerMonth: Double?
    public let internetMbps: Double?
    public let safetyScore: Double?
    public let walkabilityScore: Double?
    public let englishSpeakingScore: Double?
    public let nextMeetup: NomadsMeetup?

    public var id: String {
        slug
    }

    /// An HTTPS nomads.com link supplied by the public API, when present and trusted.
    public var cityURL: URL? {
        url
    }

    private enum CodingKeys: String, CodingKey {
        case slug, name, country, url
        case overallScore = "overall_score"
        case costForNomadUSDPerMonth = "cost_for_nomad_usd_per_month"
        case rent1brCenterUSDPerMonth = "rent_1br_center_usd_per_month"
        case coworkingUSDPerMonth = "coworking_usd_per_month"
        case internetMbps = "internet_mbps"
        case safetyScore = "safety_score_0_to_5"
        case walkabilityScore = "walkability_score_0_to_5"
        case englishSpeakingScore = "english_speaking_score_0_to_5"
        case nextMeetup = "next_meetup"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slug = try container.decode(String.self, forKey: .slug)
        name = try container.decode(String.self, forKey: .name)
        country = try container.decode(String.self, forKey: .country)
        url = try Self.trustedURL(container.decodeIfPresent(String.self, forKey: .url))
        overallScore = try container.decodeIfPresent(Double.self, forKey: .overallScore)
        costForNomadUSDPerMonth = try container.decodeIfPresent(Double.self, forKey: .costForNomadUSDPerMonth)
        rent1brCenterUSDPerMonth = try container.decodeIfPresent(Double.self, forKey: .rent1brCenterUSDPerMonth)
        coworkingUSDPerMonth = try container.decodeIfPresent(Double.self, forKey: .coworkingUSDPerMonth)
        internetMbps = try container.decodeIfPresent(Double.self, forKey: .internetMbps)
        safetyScore = try container.decodeIfPresent(Double.self, forKey: .safetyScore)
        walkabilityScore = try container.decodeIfPresent(Double.self, forKey: .walkabilityScore)
        englishSpeakingScore = try container.decodeIfPresent(Double.self, forKey: .englishSpeakingScore)
        nextMeetup = try container.decodeIfPresent(NomadsMeetup.self, forKey: .nextMeetup)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(slug, forKey: .slug)
        try container.encode(name, forKey: .name)
        try container.encode(country, forKey: .country)
        try container.encodeIfPresent(url?.absoluteString, forKey: .url)
        try container.encodeIfPresent(overallScore, forKey: .overallScore)
        try container.encodeIfPresent(costForNomadUSDPerMonth, forKey: .costForNomadUSDPerMonth)
        try container.encodeIfPresent(rent1brCenterUSDPerMonth, forKey: .rent1brCenterUSDPerMonth)
        try container.encodeIfPresent(coworkingUSDPerMonth, forKey: .coworkingUSDPerMonth)
        try container.encodeIfPresent(internetMbps, forKey: .internetMbps)
        try container.encodeIfPresent(safetyScore, forKey: .safetyScore)
        try container.encodeIfPresent(walkabilityScore, forKey: .walkabilityScore)
        try container.encodeIfPresent(englishSpeakingScore, forKey: .englishSpeakingScore)
        try container.encodeIfPresent(nextMeetup, forKey: .nextMeetup)
    }
}

public struct NomadsDirectoryCity: Codable, Sendable, Identifiable, Hashable {
    public let name: String
    public let country: String
    public let slug: String
    public let shortSlug: String?
    public let latitude: Double?
    public let longitude: Double?
    public let imageURL: URL?
    public let largeImageURL: URL?

    public var id: String {
        slug
    }

    private enum CodingKeys: String, CodingKey {
        case name, country, latitude, longitude, image
        case slug = "long_slug"
        case shortSlug = "short_slug"
        case largeImageURL = "image_large"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        country = try container.decode(String.self, forKey: .country)
        slug = try container.decode(String.self, forKey: .slug)
        shortSlug = try container.decodeIfPresent(String.self, forKey: .shortSlug)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        imageURL = try trustedDirectoryImageURL(container.decodeIfPresent(String.self, forKey: .image))
        largeImageURL = try trustedDirectoryImageURL(container.decodeIfPresent(String.self, forKey: .largeImageURL))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(country, forKey: .country)
        try container.encode(slug, forKey: .slug)
        try container.encodeIfPresent(shortSlug, forKey: .shortSlug)
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(longitude, forKey: .longitude)
        try container.encodeIfPresent(imageURL?.absoluteString, forKey: .image)
        try container.encodeIfPresent(largeImageURL?.absoluteString, forKey: .largeImageURL)
    }
}

public struct NomadsCitySearch: Hashable, Sendable {
    public let country: String
    public let maxCostUSD: Int?
    public let minInternetMbps: Int?

    public init(country: String = "", maxCostUSD: Int? = nil, minInternetMbps: Int? = nil) {
        self.country = country.trimmingCharacters(in: .whitespacesAndNewlines)
        self.maxCostUSD = maxCostUSD
        self.minInternetMbps = minInternetMbps
    }
}

public struct NomadsSearchResult: Sendable {
    public let cities: [NomadsCity]
    public let fetchedAt: Date

    public init(cities: [NomadsCity], fetchedAt: Date) {
        self.cities = cities
        self.fetchedAt = fetchedAt
    }
}

private extension NomadsMeetup {
    static func trustedURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), isTrustedNomadsURL(url) else { return nil }
        return url
    }
}

private extension NomadsCity {
    static func trustedURL(_ value: String?) -> URL? {
        NomadsMeetup.trustedURL(value)
    }
}

private func isTrustedNomadsURL(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
    return host == "nomads.com" || host.hasSuffix(".nomads.com")
}

private func trustedDirectoryImageURL(_ value: String?) -> URL? {
    guard let value, let url = URL(string: value), url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return nil }
    if host == "nomads.com", url.path.hasPrefix("/assets/img/places/") {
        return url
    }
    guard host == "resizeapi.com", url.path.contains("https://nomads.com/assets/img/places/") else { return nil }
    return url
}

import Foundation
import NomadCore
@testable import NomadUI
import Testing

struct TravelAlertDetailPresentationTests {
    private let issued = Date(timeIntervalSince1970: 1_700_000_000) // 14 Nov 2023 UTC
    private let expires = Date(timeIntervalSince1970: 1_700_259_200) // 17 Nov 2023 UTC

    @Test
    func headingPluralisesPerKind() {
        func heading(_ kind: TravelAlertKind, count: Int) -> String? {
            let items = (0..<count).map {
                TravelAlertItem(id: "\($0)", title: "Item \($0)", severity: .caution, sourceName: "Source")
            }
            return TravelAlertDetailPresentation(state: makeState(kind: kind, items: items)).itemsHeading
        }

        #expect(heading(.weather, count: 6) == "6 active alerts")
        #expect(heading(.weather, count: 1) == "1 active alert")
        #expect(heading(.security, count: 3) == "3 recent bulletins")
        #expect(heading(.security, count: 1) == "1 recent bulletin")
        #expect(heading(.advisory, count: 6) == "6 monitored countries")
        #expect(heading(.advisory, count: 1) == "1 monitored country")
        #expect(heading(.weather, count: 0) == nil)
    }

    @Test
    func itemsMapMetadataSeverityAndURL() throws {
        let url = try #require(URL(string: "https://weather.example/flood"))
        let presentation = TravelAlertDetailPresentation(
            state: makeState(
                kind: .weather,
                sourceName: "WeatherKit",
                items: [
                    TravelAlertItem(
                        id: "a",
                        title: "Flood warning",
                        detail: "Rivers rising.",
                        severity: .warning,
                        areaName: "Coast",
                        sourceName: "National Weather Service",
                        url: url,
                        issuedAt: issued,
                        expiresAt: expires
                    ),
                    TravelAlertItem(id: "b", title: "Wind advisory", severity: .info, sourceName: "WeatherKit")
                ]
            )
        )

        let first = try #require(presentation.items.first)
        #expect(first.title == "Flood warning")
        #expect(first.detail == "Rivers rising.")
        #expect(first.badgeTitle == "Warning")
        #expect(first.url == url)
        #expect(first.metadataText == "Coast · National Weather Service · Issued 14 Nov · Until 17 Nov")

        let second = try #require(presentation.items.last)
        #expect(second.detail == nil)
        #expect(second.badgeTitle == "Info")
        #expect(second.url == nil)
        #expect(second.metadataText.isEmpty)
    }

    @Test
    func readyStateUsesRowSummaryAndSourceButton() throws {
        let url = try #require(URL(string: "https://weather.example"))
        let presentation = TravelAlertDetailPresentation(
            state: makeState(kind: .weather, severity: .warning, sourceName: "NWS", sourceURL: url)
        )

        #expect(presentation.id == .weather)
        #expect(presentation.title == "Weather Alerts")
        #expect(presentation.statusLabel == "Warning")
        #expect(presentation.summary == "Summary.")
        #expect(presentation.sourceName == "NWS")
        #expect(presentation.sourceURL == url)
        #expect(presentation.sourceButtonTitle == "Open NWS")
        #expect(presentation.freshnessText.hasPrefix("Updated "))
    }

    @Test
    func staleStateKeepsLastKnownItemsAndSummaryConvention() {
        let presentation = TravelAlertDetailPresentation(
            state: makeState(
                kind: .security,
                status: .stale,
                items: [TravelAlertItem(id: "1", title: "Bulletin", severity: .caution, sourceName: "ReliefWeb")]
            )
        )

        #expect(presentation.statusLabel == "Stale")
        #expect(presentation.summary == "Last known: Summary.")
        #expect(presentation.items.count == 1)
        #expect(presentation.itemsHeading == "1 recent bulletin")
        #expect(presentation.freshnessText.hasPrefix("Last good refresh "))
    }

    @Test
    func unavailableAndCheckingStatesHaveNoItemsOrSourceLink() {
        let unavailable = TravelAlertDetailPresentation(
            state: TravelAlertSignalState(
                kind: .advisory,
                status: .unavailable,
                signal: nil,
                reason: .countryRequired,
                sourceName: "Smartraveller",
                sourceURL: URL(string: "https://www.smartraveller.gov.au"),
                lastAttemptedAt: nil,
                lastSuccessAt: nil
            )
        )

        #expect(unavailable.statusLabel == "Unavailable")
        #expect(unavailable.summary == "Country needed for nearby alerts")
        #expect(unavailable.items.isEmpty)
        #expect(unavailable.itemsHeading == nil)
        #expect(unavailable.sourceURL == nil)

        let checking = TravelAlertDetailPresentation(state: makeState(kind: .weather, status: .checking))

        #expect(checking.statusLabel == "Checking")
        #expect(checking.summary == "Checking alerts…")
        #expect(checking.items.isEmpty)
    }

    @Test
    func metadataOmitsSourceMatchingTheSheetSource() {
        let presentation = TravelAlertDetailPresentation(
            state: makeState(
                kind: .advisory,
                sourceName: "Smartraveller",
                items: [
                    TravelAlertItem(
                        id: "FR",
                        title: "France",
                        severity: .caution,
                        sourceName: "Smartraveller",
                        issuedAt: issued
                    )
                ]
            )
        )

        #expect(presentation.items.first?.metadataText == "Issued 14 Nov")
    }

    private func makeState(
        kind: TravelAlertKind,
        status: TravelAlertSignalStatus = .ready,
        severity: TravelAlertSeverity = .caution,
        sourceName: String = "ReliefWeb",
        sourceURL: URL? = nil,
        items: [TravelAlertItem] = []
    ) -> TravelAlertSignalState {
        TravelAlertSignalState(
            kind: kind,
            status: status,
            signal: TravelAlertSignalSnapshot(
                kind: kind,
                severity: severity,
                title: kind.rawValue,
                summary: "Summary.",
                sourceName: sourceName,
                sourceURL: sourceURL,
                updatedAt: issued,
                affectedCountryCodes: [],
                items: items
            ),
            reason: nil,
            sourceName: sourceName,
            sourceURL: sourceURL,
            lastAttemptedAt: issued,
            lastSuccessAt: issued
        )
    }
}

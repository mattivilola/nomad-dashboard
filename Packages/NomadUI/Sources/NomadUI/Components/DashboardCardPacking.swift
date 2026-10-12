import NomadCore

enum DashboardCardRenderWidth: Equatable {
    case full
    case half
}

struct DashboardCardRowItem: Identifiable, Equatable {
    let cardID: DashboardCardID
    /// The width the user chose for the card. Stored preferences are never rewritten by packing.
    let preferredWidthMode: DashboardCardWidthMode
    let renderWidth: DashboardCardRenderWidth

    var id: DashboardCardID {
        cardID
    }

    /// The layout the card actually renders with: narrow only while it really shares a row
    /// with a narrow neighbour, otherwise the wide layout at full width.
    var layoutWidthMode: DashboardCardWidthMode {
        switch renderWidth {
        case .half:
            .narrow
        case .full:
            .wide
        }
    }
}

struct DashboardCardRow: Identifiable, Equatable {
    let items: [DashboardCardRowItem]

    var id: String {
        items.map(\.cardID.rawValue).joined(separator: "|")
    }
}

enum DashboardCardPacking {
    /// Packs cards into rows: two adjacent narrow cards share a row at half width; every
    /// other card, including a narrow card without a narrow partner, takes the full width.
    /// A collapsed card is a one-line summary and always takes the full width, so it never pairs.
    static func rows(
        order: [DashboardCardID],
        widthModes: [DashboardCardID: DashboardCardWidthMode],
        collapsed: Set<DashboardCardID> = []
    ) -> [DashboardCardRow] {
        func packsNarrow(_ cardID: DashboardCardID) -> Bool {
            (widthModes[cardID] ?? .wide) == .narrow && collapsed.contains(cardID) == false
        }

        var rows: [DashboardCardRow] = []
        var index = 0

        while index < order.count {
            let cardID = order[index]
            let widthMode = widthModes[cardID] ?? .wide

            if packsNarrow(cardID),
               index + 1 < order.count,
               packsNarrow(order[index + 1])
            {
                rows.append(
                    DashboardCardRow(items: [
                        DashboardCardRowItem(cardID: cardID, preferredWidthMode: .narrow, renderWidth: .half),
                        DashboardCardRowItem(cardID: order[index + 1], preferredWidthMode: .narrow, renderWidth: .half)
                    ])
                )
                index += 2
                continue
            }

            rows.append(
                DashboardCardRow(items: [
                    DashboardCardRowItem(cardID: cardID, preferredWidthMode: widthMode, renderWidth: .full)
                ])
            )
            index += 1
        }

        return rows
    }
}

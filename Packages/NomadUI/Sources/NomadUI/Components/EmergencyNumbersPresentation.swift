import NomadCore

extension EmergencyNumbers {
    /// "Emergency 112": the number to call first, for card subtitles and summaries.
    var headline: String {
        "Emergency \(general)"
    }

    /// The other numbers worth knowing, only those that differ from `general`:
    /// "Police 110 · Ambulance/Fire 119 · Gendarmerie 177". Nil when `general` covers everything.
    var othersText: String? {
        var parts: [String] = []

        if let police {
            parts.append("Police \(police)")
        }

        switch (ambulance, fire) {
        case let (ambulance?, fire?) where ambulance == fire:
            parts.append("Ambulance/Fire \(ambulance)")
        default:
            if let ambulance {
                parts.append("Ambulance \(ambulance)")
            }
            if let fire {
                parts.append("Fire \(fire)")
            }
        }

        parts.append(contentsOf: other.map { "\($0.name) \($0.number)" })

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

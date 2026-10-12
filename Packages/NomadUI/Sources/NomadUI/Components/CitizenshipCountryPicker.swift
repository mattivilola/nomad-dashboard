import NomadCore
import SwiftUI

/// Searchable sheet for adding a citizenship. Picking a country reports its ISO code and closes the sheet.
public struct CitizenshipCountryPicker: View {
    private let chosen: [String]
    private let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private let countries = CitizenshipSettingsPresentation.allCountries()

    /// - Parameters:
    ///   - chosen: Citizenships already added; they are left out of the list.
    ///   - onSelect: Called with the upper-case ISO 3166-1 alpha-2 code of the picked country.
    public init(chosen: [String], onSelect: @escaping (String) -> Void) {
        self.chosen = chosen
        self.onSelect = onSelect
    }

    private var matches: [CitizenshipCountry] {
        CitizenshipSettingsPresentation.countries(countries, matching: query, excluding: chosen)
    }

    public var body: some View {
        VStack(spacing: 0) {
            Text(CitizenshipSettingsPresentation.pickerTitle)
                .font(.headline)
                .padding()

            TextField(CitizenshipSettingsPresentation.pickerSearchPrompt, text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            List(matches) { country in
                Button {
                    onSelect(country.code)
                    dismiss()
                } label: {
                    HStack {
                        Text(country.name)
                        Spacer()
                        Text(country.code)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if matches.isEmpty {
                    Text("No matching country")
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 460, height: 520)
    }
}

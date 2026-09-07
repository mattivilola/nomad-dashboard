import NomadCore
import SwiftUI

struct CountryDayEditorSheet: View {
    let initialDay: VisitedCountryDay?
    let onSave: (VisitedCountryDayOverride) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var countryCode: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        initialDay: VisitedCountryDay?,
        onSave: @escaping (VisitedCountryDayOverride) async throws -> Void
    ) {
        self.initialDay = initialDay
        self.onSave = onSave
        let initialDate = Self.date(for: initialDay?.day) ?? .now
        _startDate = State(initialValue: initialDate)
        _endDate = State(initialValue: initialDate)
        _countryCode = State(initialValue: initialDay?.countryCode ?? "FI")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(initialDay == nil ? "Add country days" : "Edit country day")
                    .font(.title2.weight(.semibold))
                Text("Manual changes are saved locally. You can restore the original observation later.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Form {
                DatePicker("From", selection: $startDate, displayedComponents: .date)
                DatePicker("Through", selection: $endDate, in: startDate..., displayedComponents: .date)

                Picker("Country", selection: $countryCode) {
                    ForEach(CountryChoice.all) { country in
                        Text(country.name).tag(country.code)
                    }
                }
                .accessibilityHint("Select the country for every day in this range.")
            }
            .formStyle(.grouped)

            Text(rangeDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .accessibilityElement(children: .combine)
            }

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isSaving ? "Saving…" : "Save days") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onChange(of: startDate) { _, newValue in
            if endDate < newValue {
                endDate = newValue
            }
        }
    }

    private var rangeDescription: String {
        let count = Calendar.autoupdatingCurrent.dateComponents([.day], from: startDate, to: endDate).day.map { $0 + 1 } ?? 0
        return count == 1 ? "This saves one manual country day." : "This saves \(count) manual country days."
    }

    private func save() {
        let calendar = Calendar.autoupdatingCurrent
        let dayCount = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? -1
        guard dayCount >= 0 else {
            errorMessage = "The end date must be on or after the start date."
            return
        }
        guard dayCount < 366 else {
            errorMessage = "Save ranges of up to 366 days at a time."
            return
        }
        guard let country = CountryChoice.all.first(where: { $0.code == countryCode }) else {
            errorMessage = "Choose a country before saving."
            return
        }

        isSaving = true
        errorMessage = nil
        Task {
            do {
                for offset in 0...dayCount {
                    guard let date = calendar.date(byAdding: .day, value: offset, to: startDate) else { continue }
                    try await onSave(.init(
                        day: VisitedCountryDayStamp(date: date, calendar: calendar),
                        country: country.name,
                        countryCode: country.code
                    ))
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }

    private static func date(for day: VisitedCountryDayStamp?) -> Date? {
        guard let day else { return nil }
        return Calendar.autoupdatingCurrent.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))
    }
}

private struct CountryChoice: Identifiable {
    let code: String
    let name: String
    var id: String {
        code
    }

    static let all = Locale.Region.isoRegions
        .map(\.identifier)
        .sorted()
        .compactMap { code in
            Locale.current.localizedString(forRegionCode: code).map { CountryChoice(code: code, name: $0) }
        }
}

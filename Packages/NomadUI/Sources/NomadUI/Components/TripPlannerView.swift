import NomadCore
import SwiftUI

/// The Trip Planner window: the planned trips on the left and what to know about the selected one on the
/// right. Trips stay on this Mac; only the destination country code is sent to look up holidays and advisories.
public struct TripPlannerView: View {
    @StateObject private var model: TripPlannerModel
    private let homeTimeZoneIdentifier: String
    private let openURLAction: (URL) -> Void
    private let copyTextAction: (String) -> Void

    /// - Parameters:
    ///   - homeTimeZoneIdentifier: The traveller's home time zone, for the time difference to the destination.
    ///   - openURLAction: Opens a web link (a mission's map or website, the travel registration).
    ///   - copyTextAction: Copies text (a phone number, an address).
    @MainActor
    public init(
        settingsStore: AppSettingsStore,
        snapshotStore: DashboardSnapshotStore,
        homeTimeZoneIdentifier: String,
        openURLAction: @escaping (URL) -> Void,
        copyTextAction: @escaping (String) -> Void
    ) {
        self.init(
            model: TripPlannerModel.live(
                settingsStore: settingsStore,
                snapshotStore: snapshotStore,
                homeTimeZoneIdentifier: homeTimeZoneIdentifier
            ),
            homeTimeZoneIdentifier: homeTimeZoneIdentifier,
            openURLAction: openURLAction,
            copyTextAction: copyTextAction
        )
    }

    /// The window around a model, for previews and tests that bring their own services.
    @MainActor
    init(
        model: TripPlannerModel,
        homeTimeZoneIdentifier: String,
        openURLAction: @escaping (URL) -> Void,
        copyTextAction: @escaping (String) -> Void
    ) {
        _model = StateObject(wrappedValue: model)
        self.homeTimeZoneIdentifier = homeTimeZoneIdentifier
        self.openURLAction = openURLAction
        self.copyTextAction = copyTextAction
    }

    public var body: some View {
        ZStack {
            NomadTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Divider().opacity(0.5)

                if model.trips.isEmpty {
                    emptyState
                } else {
                    HSplitView {
                        tripList
                            .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)

                        detail
                            .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .tint(NomadTheme.teal)
        .frame(minWidth: 820, minHeight: 560)
        .sheet(item: $model.editor) { session in
            TripEditorSheet(
                draft: session.draft,
                now: Date(),
                calendar: model.calendar,
                locale: model.locale,
                saveAction: { model.save($0) },
                deleteAction: session.draft.isNew ? nil : { if let id = session.draft.id { model.delete(id) } },
                cancelAction: { model.editor = nil }
            )
        }
        .onChange(of: homeTimeZoneIdentifier) { _, identifier in
            model.homeTimeZoneIdentifier = identifier
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "airplane.departure")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(NomadTheme.teal)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(TripPlannerText.windowTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(NomadTheme.primaryText)

                Text(TripPlannerText.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(NomadTheme.secondaryText)
            }

            Spacer(minLength: 15)

            Button {
                model.beginAdding()
            } label: {
                Label(TripPlannerText.addTripTitle, systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.canAddTrip == false)
            .help(model.canAddTrip ? "Plan a new trip" : TripPlannerText.limitText)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    // MARK: List

    private var tripList: some View {
        VStack(spacing: 0) {
            List(selection: selection) {
                ForEach(model.listRows) { row in
                    TripListRowView(row: row)
                        .tag(row.id)
                        .contextMenu {
                            Button("Edit…") { model.beginEditing(row.id) }
                        }
                }
            }
            .scrollContentBackground(.hidden)

            if model.canAddTrip == false {
                Text(TripPlannerText.limitText)
                    .font(.caption)
                    .foregroundStyle(NomadTheme.secondaryText)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var selection: Binding<UUID?> {
        Binding(get: { model.selectedTripID }, set: { model.select($0) })
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let presentation = model.presentation, let id = model.selectedTripID {
            TripPreviewView(
                presentation: presentation,
                checklistActions: TripChecklistActions(
                    setChecked: { model.setChecked($0, itemID: $1) },
                    addCustomItem: { model.addCustomItem(title: $0) },
                    setCustomItemChecked: { model.setCustomItemChecked($0, id: $1) },
                    removeCustomItem: { model.removeCustomItem(id: $0) },
                    openURL: openURLAction
                ),
                editAction: { model.beginEditing(id) },
                refreshOnlineAction: { model.refreshOnline() },
                openURLAction: openURLAction,
                copyTextAction: copyTextAction
            )
            .id(id)
        } else {
            Color.clear
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(TripPlannerText.emptyTitle, systemImage: "airplane.departure")
        } description: {
            Text(TripPlannerText.emptyMessage)
                .frame(maxWidth: 420)
        } actions: {
            Button(TripPlannerText.addTripTitle) { model.beginAdding() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            Text(TripPlannerText.footer)
                .font(.caption)
                .foregroundStyle(NomadTheme.tertiaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TripListRowView: View {
    let row: TripListRow

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.countryName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(row.hasEnded ? NomadTheme.tertiaryText : NomadTheme.primaryText)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(row.dates)
                        .font(.caption)
                        .foregroundStyle(NomadTheme.secondaryText)
                        .lineLimit(1)

                    if let progress = row.checklistProgress {
                        Label(progress, systemImage: "checklist")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(row.checklistTone.statusTint(neutral: NomadTheme.tertiaryText))
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }

            Spacer(minLength: 4)

            NeutralChip(title: row.timing)
                .fixedSize()
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }
}

/// The add and edit sheet. Saving and deleting go through the model, which sanitizes before storing.
private struct TripEditorSheet: View {
    @State var draft: TripDraft
    let now: Date
    let calendar: Calendar
    let locale: Locale
    let saveAction: (TripDraft) -> Void
    let deleteAction: (() -> Void)?
    let cancelAction: () -> Void

    @State private var showsCountryPicker = false
    @State private var showsDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent("Country") {
                        Button(countryName ?? TripPlannerText.chooseCountryTitle) {
                            showsCountryPicker = true
                        }
                    }

                    DatePicker(
                        "Start",
                        selection: Binding(get: { draft.startDate }, set: { draft.setStart($0) }),
                        displayedComponents: .date
                    )

                    DatePicker(
                        "End",
                        selection: $draft.endDate,
                        in: draft.endDateRange(calendar: calendar),
                        displayedComponents: .date
                    )
                } header: {
                    Text(draft.isNew ? TripPlannerText.addTripTitle : TripPlannerText.editTripTitle)
                }

                Section {
                    TextField(TripPlannerText.notePlaceholder, text: $draft.note, axis: .vertical)
                        .lineLimit(2...4)
                        .onChange(of: draft.note) { _, _ in draft.limitNote() }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(TripPlannerText.noteCounter(draft.note))

                        if let hint = draft.hint(now: now, calendar: calendar) {
                            Text(hint)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .formStyle(.grouped)

            HStack {
                if deleteAction != nil {
                    Button(TripPlannerText.deleteTitle, role: .destructive) {
                        showsDeleteConfirmation = true
                    }
                }

                Spacer()

                Button(TripPlannerText.cancelTitle, action: cancelAction)
                    .keyboardShortcut(.cancelAction)

                Button(TripPlannerText.saveTitle) { saveAction(draft) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.canSave(now: now, calendar: calendar) == false)
            }
            .padding(16)
        }
        .frame(width: 440)
        .sheet(isPresented: $showsCountryPicker) {
            CitizenshipCountryPicker(title: TripPlannerText.destinationPickerTitle, chosen: []) { code in
                draft.countryCode = code
            }
        }
        .confirmationDialog(
            "Delete the trip to \(countryName ?? "this country")?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(TripPlannerText.deleteConfirmTitle, role: .destructive) {
                deleteAction?()
            }
        } message: {
            Text(TripPlannerText.deleteConfirmationMessage(countryName: countryName ?? "this country"))
        }
    }

    private var countryName: String? {
        draft.countryCode.map { CountryNames.displayName(forCode: $0, locale: locale) }
    }
}

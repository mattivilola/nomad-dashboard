import NomadCore
import SwiftUI

/// What the checklist can do to the selected trip. Every action ends in the Trip Planner model, which stores
/// the result locally through the settings sanitizer.
struct TripChecklistActions {
    let setChecked: (Bool, String) -> Void
    /// Adds an own item; false when nothing was added.
    let addCustomItem: (String) -> Bool
    let setCustomItemChecked: (Bool, UUID) -> Void
    let removeCustomItem: (UUID) -> Void
    let openURL: (URL) -> Void
}

/// The body of the "Before you leave" tile: the progress bar, the suggested items by group and the
/// traveller's own items with a field to add more.
struct TripChecklistSection: View {
    let checklist: TripChecklistPresentation
    let actions: TripChecklistActions

    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let progress = checklist.progress {
                UsageProgressBar(progress: progress, tint: NomadTheme.teal, height: 4)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Checklist progress")
                    .accessibilityValue(checklist.progressText)
            }

            ForEach(checklist.groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    groupTitle(group.title)

                    ForEach(group.items) { item in
                        itemRow(item)
                    }
                }
            }

            customSection

            Text(TripChecklistPresentation.localCaption)
                .font(.caption2)
                .foregroundStyle(NomadTheme.tertiaryText)
        }
    }

    private func groupTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(NomadTheme.tertiaryText)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Suggested items

    private func itemRow(_ item: TripChecklistPresentation.ItemRow) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle(
                isOn: Binding(
                    get: { item.isChecked },
                    set: { actions.setChecked($0, item.id) }
                )
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(item.isChecked ? NomadTheme.secondaryText : NomadTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if let detail = item.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(NomadTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .toggleStyle(.checkbox)

            Spacer(minLength: 8)

            if let link = item.link {
                Button(TripChecklistPresentation.openLinkTitle) { actions.openURL(link) }
                    .buttonStyle(.dashboardInline(isCompact: true))
                    .help(link.host ?? link.absoluteString)
                    .accessibilityLabel("\(TripChecklistPresentation.openLinkTitle) page for \(item.title)")
            }
        }
    }

    // MARK: Own items

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            groupTitle(TripChecklistPresentation.customGroupTitle)

            ForEach(checklist.customItems) { item in
                HStack(alignment: .top, spacing: 8) {
                    Toggle(
                        isOn: Binding(
                            get: { item.isChecked },
                            set: { actions.setCustomItemChecked($0, item.id) }
                        )
                    ) {
                        Text(item.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(item.isChecked ? NomadTheme.secondaryText : NomadTheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .toggleStyle(.checkbox)

                    Spacer(minLength: 8)

                    Button {
                        actions.removeCustomItem(item.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(NomadTheme.tertiaryText)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(TripChecklistPresentation.removeTitle)
                    .accessibilityLabel("\(TripChecklistPresentation.removeTitle) \(item.title)")
                }
            }

            HStack(spacing: 8) {
                TextField(TripChecklistPresentation.addPlaceholder, text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                    .disabled(checklist.canAddCustomItem == false)
                    .onSubmit(addDraft)
                    .onChange(of: draft) { _, text in
                        let limited = TripChecklistPresentation.limitedTitle(text)
                        if limited != text {
                            draft = limited
                        }
                    }

                Button(action: addDraft) {
                    DashboardIconChip(systemImage: "plus", isEnabled: checklist.canAdd(draft))
                }
                .buttonStyle(.plain)
                .disabled(checklist.canAdd(draft) == false)
                .help(TripChecklistPresentation.addTitle)
                .accessibilityLabel(TripChecklistPresentation.addTitle)
            }

            if let note = checklist.limitNote(forDraft: draft) {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(NomadTheme.tertiaryText)
            }
        }
    }

    private func addDraft() {
        guard checklist.canAdd(draft), actions.addCustomItem(draft) else {
            return
        }

        draft = ""
    }
}

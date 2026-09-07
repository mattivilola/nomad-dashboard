import AppKit
import NomadCore
import SwiftUI

public struct NomadLifeDiaryView: View {
    @ObservedObject private var controller: NomadLifeController
    @State private var editingEntry: NomadLifeConnectionDiaryEntry?
    @State private var searchText = ""

    public init(controller: NomadLifeController) {
        self.controller = controller
    }

    public var body: some View {
        List {
            Section("Connection diary") {
                if controller.isLoadingDiary {
                    ProgressView("Loading your local diary…")
                } else if controller.entries.isEmpty {
                    ContentUnavailableView("No workplace visits yet", systemImage: "briefcase", description: Text("When collection is enabled and Nomad sees you stationary, it saves a local connection summary."))
                } else if filteredEntries.isEmpty {
                    ContentUnavailableView("No matching workplace visits", systemImage: "magnifyingglass", description: Text("Try a different place or note."))
                }
                ForEach(filteredEntries) { entry in
                    Button { editingEntry = entry } label: { EntryRow(entry: entry).contentShape(Rectangle()) }.buttonStyle(.plain)
                        .contextMenu { Button("Open in Google Maps") { NSWorkspace.shared.open(entry.googleMapsURL) }
                            Button("Confirm suggested venue") { controller.confirmSuggestion(id: entry.id) }.disabled(entry.confidence == .confirmed)
                        }
                }
            }
        }
        .navigationTitle("Nomad Life")
        .searchable(text: $searchText, prompt: "Search places and notes")
        .sheet(item: $editingEntry) { entry in DiaryEntryEditor(entry: entry) { name, note, confirmVenue in controller.updateEntry(id: entry.id, name: name, note: note, confirmVenue: confirmVenue) } }
    }

    private var filteredEntries: [NomadLifeConnectionDiaryEntry] {
        controller.entries.filter {
            searchText.isEmpty || $0.displayName.localizedCaseInsensitiveContains(searchText) || ($0.note?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
}

private struct EntryRow: View {
    let entry: NomadLifeConnectionDiaryEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Label(entry.displayName, systemImage: entry.confidence == .confirmed ? "checkmark.seal.fill" : "mappin.and.ellipse")
                Spacer()
                Text(entry.endedAt, style: .date).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Text(entry.confidence == .confirmed ? "Confirmed venue" : "Suggested venue")
                Text("\(entry.sampleCount) samples")
                if let latency = entry.averageLatencyMilliseconds {
                    Text("\(Int(latency)) ms")
                }
                if entry.disconnectCount > 0 {
                    Label("\(entry.disconnectCount)", systemImage: "wifi.exclamationmark")
                }
            }.font(.caption).foregroundStyle(.secondary)
            Text("Device location • \(entry.startedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(.tertiary)
        }.padding(.vertical, 3)
    }
}

private struct DiaryEntryEditor: View {
    let entry: NomadLifeConnectionDiaryEntry
    let save: (String, String, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var note: String
    @State private var confirmVenue: Bool
    init(entry: NomadLifeConnectionDiaryEntry, save: @escaping (String, String, Bool) -> Void) {
        self.entry = entry
        self.save = save
        _name = State(initialValue: entry.name ?? "")
        _note = State(initialValue: entry.note ?? "")
        _confirmVenue = State(initialValue: entry.confidence == .confirmed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Workplace visit").font(.title2.weight(.semibold))
            Text("Suggestion: \(entry.suggestedName)").foregroundStyle(.secondary)
            Text("This is a local diary entry based on your authorized device location. Saving a note does not confirm the suggested venue.").foregroundStyle(.secondary)
            Toggle("Confirm this venue name", isOn: $confirmVenue)
            if confirmVenue {
                TextField("Venue name", text: $name)
            }
            TextField("Private note", text: $note, axis: .vertical).lineLimit(3...6)
            Link("Open in Google Maps", destination: entry.googleMapsURL)
            HStack { Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save(name, note, confirmVenue)
                    dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }.padding().frame(width: 440)
    }
}

private extension NomadLifeConnectionDiaryEntry {
    var googleMapsURL: URL {
        var components = URLComponents(string: "https://www.google.com/maps/search/")!
        components.queryItems = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "query", value: "\(latitude),\(longitude)")]
        return components.url!
    }
}

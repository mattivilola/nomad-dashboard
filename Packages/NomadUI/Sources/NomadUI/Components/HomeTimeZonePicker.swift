import SwiftUI

/// Searchable sheet for choosing the home time zone.
public struct HomeTimeZonePicker: View {
    @Binding private var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    public init(selection: Binding<String>) {
        _selection = selection
    }

    private var zones: [String] {
        TimeZone.knownTimeZoneIdentifiers.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
    }

    public var body: some View {
        VStack(spacing: 0) {
            Text("Choose home time zone").font(.headline).padding()
            TextField("Search region or city", text: $query).textFieldStyle(.roundedBorder).padding(.horizontal)
            List(zones, id: \.self) { id in
                Button { selection = id
                    dismiss()
                } label: { HStack { Text(id.replacingOccurrences(of: "_", with: " "))
                    Spacer()
                    Text(time(in: id)).foregroundStyle(.secondary)
                    if id == selection {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }.contentShape(Rectangle()) }.buttonStyle(.plain)
            }
            HStack { Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding()
        }.frame(width: 460, height: 520)
    }

    private func time(in id: String) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone(identifier: id)
        return formatter.string(from: .now)
    }
}

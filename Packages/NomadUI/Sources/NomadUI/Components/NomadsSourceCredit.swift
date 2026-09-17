import SwiftUI

/// Keep the source credit next to its data, independently of local navigation.
struct NomadsSourceCredit: View {
    static let homepage = URL(string: "https://nomads.com")!
    static let joinURL = URL(string: "https://nomads.com/?join=nomads")!

    var cityURL: URL?
    var includesPhotos = false
    var prominent = false

    var body: some View {
        Link(destination: cityURL ?? Self.homepage) {
            Label(includesPhotos ? "Data & photos from Nomads.com" : "Data from Nomads.com", systemImage: "arrow.up.right.square")
                .underline()
        }
        .font(prominent ? .headline : .subheadline.weight(.semibold))
        .foregroundStyle(NomadTheme.teal)
        .help(cityURL == nil ? "Visit Nomads.com, the source of this destination data" : "View the original city page on Nomads.com")
    }
}

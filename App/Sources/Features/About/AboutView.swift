import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Nomad Dashboard", systemImage: "suitcase.rolling.fill")
                .font(.system(size: 24, weight: .semibold, design: .rounded))

            Text("Native macOS menu bar telemetry for travelling developers.")
                .foregroundStyle(.secondary)

            Divider()

            LabeledContent("Maintainer", value: "Matti Vilola")
            LabeledContent("Contributor", value: "ILO APPLICATIONS SL")
            LabeledContent("Website", value: "iloapps.dev")
            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")

            HStack {
                Link("Project Site", destination: URL(string: "https://iloapps.dev")!)
                Link("Apache-2.0", destination: URL(string: "https://www.apache.org/licenses/LICENSE-2.0")!)
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(width: 420)
    }
}


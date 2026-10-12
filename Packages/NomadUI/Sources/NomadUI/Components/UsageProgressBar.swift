import SwiftUI

/// Thin capsule progress bar tinted by status: a faint track of the tint with a solid fill.
/// Shared by the glance Data tile and the Data Guard card (the system `ProgressView` ignores
/// its tint in some states and renders grey).
struct UsageProgressBar: View {
    let progress: Double
    let tint: Color
    var height: CGFloat = 3

    var body: some View {
        let clamped = min(max(progress, 0), 1)

        Capsule()
            .fill(tint.opacity(0.18))
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    Capsule()
                        .fill(tint)
                        .frame(width: geometry.size.width * clamped)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityValue("\(Int((clamped * 100).rounded())) percent")
    }
}

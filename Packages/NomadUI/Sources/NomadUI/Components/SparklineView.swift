import NomadCore
import SwiftUI

/// What a sparkline draws and says, independent of SwiftUI so it can be unit tested.
struct SparklinePresentation: Equatable {
    enum Kind: Equatable {
        /// Fewer than `minimumPointCount` samples: a dashed baseline stands in.
        case collecting
        /// Enough samples but no movement: a flat line at mid-height.
        case steady
        case trend
    }

    static let minimumPointCount = 3
    /// Values closer together than this count as "no movement".
    static let flatTolerance = 0.01

    let kind: Kind
    /// Points in the unit square, x from the oldest to the newest sample, y from 0 (lowest
    /// value) to 1 (highest value). Empty unless `kind == .trend`.
    let samples: [CGPoint]
    let minimum: Double?
    let maximum: Double?
    let latest: Double?
    let timeSpan: TimeInterval?
    let helpText: String
    let accessibilityLabel: String

    init(
        points: [MetricPoint],
        title: String = "Trend",
        placeholder: String = "Collecting trend…",
        format: (Double) -> String = { String(format: "%.0f", $0) }
    ) {
        let sorted = points.sorted { $0.timestamp < $1.timestamp }

        guard sorted.count >= Self.minimumPointCount,
              let first = sorted.first,
              let last = sorted.last,
              let minimum = sorted.map(\.value).min(),
              let maximum = sorted.map(\.value).max()
        else {
            kind = .collecting
            samples = []
            minimum = nil
            maximum = nil
            latest = sorted.last?.value
            timeSpan = nil
            helpText = placeholder
            accessibilityLabel = "\(title): \(placeholder)"
            return
        }

        let span = last.timestamp.timeIntervalSince(first.timestamp)
        let latest = last.value
        self.minimum = minimum
        self.maximum = maximum
        self.latest = latest
        timeSpan = span

        let spanText = Self.spanText(span)

        if abs(maximum - minimum) <= Self.flatTolerance {
            kind = .steady
            samples = []
            helpText = "Last \(spanText) · steady at \(format(latest))"
            accessibilityLabel = "\(title) over the last \(spanText): steady at \(format(latest))"
            return
        }

        kind = .trend
        let range = maximum - minimum
        samples = sorted.enumerated().map { index, point in
            let x = span > 0
                ? point.timestamp.timeIntervalSince(first.timestamp) / span
                : Double(index) / Double(sorted.count - 1)
            return CGPoint(x: x, y: (point.value - minimum) / range)
        }
        helpText = "Last \(spanText) · min \(format(minimum)) · max \(format(maximum)) · now \(format(latest))"
        accessibilityLabel = "\(title) over the last \(spanText): minimum \(format(minimum)), maximum \(format(maximum)), latest \(format(latest))"
    }

    /// "45 s", "8 min", "2 h": the span a sparkline covers, in the coarsest readable unit.
    static func spanText(_ seconds: TimeInterval) -> String {
        let seconds = max(seconds, 0)

        if seconds < 90 {
            return "\(max(Int(seconds.rounded()), 1)) s"
        }

        let minutes = Int((seconds / 60).rounded())
        if minutes < 90 {
            return "\(minutes) min"
        }

        let hours = (seconds / 3_600 * 10).rounded() / 10
        return hours == hours.rounded() ? "\(Int(hours)) h" : String(format: "%.1f h", hours)
    }
}

/// A tiny, axis-less trend line (about 24 pt high) that sits directly under the metric it
/// describes. Hover shows the covered time span and min/max; VoiceOver gets the same
/// summary.
struct SparklineView: View {
    static let height: CGFloat = 24

    let points: [MetricPoint]
    let tint: Color
    var title: String = "Trend"
    var placeholder: String = "Collecting trend…"
    var format: (Double) -> String = { String(format: "%.0f", $0) }

    var body: some View {
        let presentation = SparklinePresentation(
            points: points,
            title: title,
            placeholder: placeholder,
            format: format
        )

        ZStack {
            switch presentation.kind {
            case .collecting:
                SparklineBaseline()
                    .stroke(
                        NomadTheme.tertiaryText.opacity(0.7),
                        style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [3, 3])
                    )
            case .steady:
                SparklineBaseline()
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            case .trend:
                SparklineShape(samples: presentation.samples, closesToBaseline: true)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.28), tint.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                SparklineShape(samples: presentation.samples, closesToBaseline: false)
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .contentShape(Rectangle())
        .help(presentation.helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }
}

private struct SparklineBaseline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

private struct SparklineShape: Shape {
    let samples: [CGPoint]
    let closesToBaseline: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Keep the stroke inside the frame at both extremes.
        let plot = rect.insetBy(dx: 1, dy: 2)
        let points = samples.map {
            CGPoint(x: plot.minX + $0.x * plot.width, y: plot.maxY - $0.y * plot.height)
        }

        guard let first = points.first, let last = points.last else {
            return path
        }

        if closesToBaseline {
            path.move(to: CGPoint(x: first.x, y: rect.maxY))
            path.addLine(to: first)
        } else {
            path.move(to: first)
        }

        for point in points.dropFirst() {
            path.addLine(to: point)
        }

        if closesToBaseline {
            path.addLine(to: CGPoint(x: last.x, y: rect.maxY))
            path.closeSubpath()
        }

        return path
    }
}

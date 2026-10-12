import Foundation
import NomadCore

enum TimeTrackingDurationFormatting {
    /// "42m", "3h", "6h 58m": whole minutes, no zero-padded parts.
    static func text(_ duration: TimeInterval) -> String {
        let totalMinutes = Int((duration / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours == 0 {
            return "\(minutes)m"
        }

        if minutes == 0 {
            return "\(hours)h"
        }

        return "\(hours)h \(minutes)m"
    }
}

/// Today's time split for the Time Tracking card: the segments of the thin allocation bar,
/// the legend under it and the focus-loss caption.
struct TimeTrackingAllocationPresentation: Equatable {
    static let maxLegendEntries = 4

    enum SegmentKind: Equatable {
        /// Time already assigned to a project or Other. `toneIndex` picks a tone of the
        /// neutral/teal ramp in order of size, so adjacent segments stay distinguishable.
        case allocated(toneIndex: Int)
        /// Tracked time that still needs an allocation.
        case pending
    }

    struct Segment: Equatable, Identifiable {
        let id: String
        let title: String
        let duration: TimeInterval
        let durationText: String
        /// Share of the bar, 0...1. Zero-length buckets have no segment.
        let fraction: Double
        let kind: SegmentKind
        /// Full detail for hover, including the interruptions of the bucket.
        let helpText: String
    }

    struct LegendEntry: Equatable, Identifiable {
        let id: String
        let title: String
        let durationText: String
        let kind: SegmentKind
        let helpText: String
    }

    /// Allocated buckets largest first, then the pending remainder.
    let segments: [Segment]
    /// At most `maxLegendEntries` allocated buckets, then the pending remainder.
    let legend: [LegendEntry]
    /// Allocated buckets that did not fit the legend.
    let hiddenLegendCount: Int
    let barHelpText: String
    /// "≈15m focus lost", or nil without interruptions.
    let focusLossCaption: String?

    init(summary: TimeTrackingDaySummary, bucketTitle: (TimeTrackingBucket) -> String) {
        let allocatedBuckets = summary.bucketDurations.filter { $0.bucket != .unallocated }
        let pending = max(summary.unallocatedDuration, 0)
        let total = allocatedBuckets.reduce(0) { $0 + max($1.duration, 0) } + pending

        func helpText(title: String, duration: TimeInterval, interruptionCount: Int, focusAdjusted: TimeInterval) -> String {
            var text = "\(title): \(TimeTrackingDurationFormatting.text(duration))"
            if interruptionCount > 0 {
                text += " · \(interruptionCount) interruption\(interruptionCount == 1 ? "" : "s")"
                text += " · focus \(TimeTrackingDurationFormatting.text(focusAdjusted))"
            }
            return text
        }

        var segments: [Segment] = []
        var legend: [LegendEntry] = []
        var toneIndex = 0

        for bucketDuration in allocatedBuckets {
            let title = bucketTitle(bucketDuration.bucket)
            let durationText = TimeTrackingDurationFormatting.text(bucketDuration.duration)
            let help = helpText(
                title: title,
                duration: bucketDuration.duration,
                interruptionCount: bucketDuration.interruptionCount,
                focusAdjusted: bucketDuration.focusAdjustedDuration
            )
            let kind = SegmentKind.allocated(toneIndex: toneIndex)
            toneIndex += 1

            if bucketDuration.duration > 0, total > 0 {
                segments.append(
                    Segment(
                        id: bucketDuration.id,
                        title: title,
                        duration: bucketDuration.duration,
                        durationText: durationText,
                        fraction: bucketDuration.duration / total,
                        kind: kind,
                        helpText: help
                    )
                )
            }

            if legend.count < Self.maxLegendEntries {
                legend.append(
                    LegendEntry(id: bucketDuration.id, title: title, durationText: durationText, kind: kind, helpText: help)
                )
            }
        }

        hiddenLegendCount = max(allocatedBuckets.count - Self.maxLegendEntries, 0)

        if pending > 0 {
            let pendingText = TimeTrackingDurationFormatting.text(pending)
            let help = "Pending: \(pendingText) still to allocate"
            if total > 0 {
                segments.append(
                    Segment(
                        id: "pending",
                        title: "Pending",
                        duration: pending,
                        durationText: pendingText,
                        fraction: pending / total,
                        kind: .pending,
                        helpText: help
                    )
                )
            }
            legend.append(
                LegendEntry(id: "pending", title: "Pending", durationText: pendingText, kind: .pending, helpText: help)
            )
        }

        self.segments = segments
        self.legend = legend
        barHelpText = "Allocated \(TimeTrackingDurationFormatting.text(summary.totalAllocatedDuration)) of \(TimeTrackingDurationFormatting.text(summary.totalTrackedDuration)) tracked today"
            + (pending > 0 ? " · \(TimeTrackingDurationFormatting.text(pending)) pending" : "")

        focusLossCaption = summary.estimatedFocusLossDuration > 0
            ? "≈\(TimeTrackingDurationFormatting.text(summary.estimatedFocusLossDuration)) focus lost"
            : nil
    }
}

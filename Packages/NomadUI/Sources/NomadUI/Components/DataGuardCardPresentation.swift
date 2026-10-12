import Foundation
import NomadCore

/// What the Data Guard card says: what is left first, then how it is used and why it is
/// monitoring.
struct DataGuardCardPresentation: Equatable {
    /// "1.0 GB left", "Cap reached", or "Used 3.2 GB" without a cap.
    let leadText: String
    /// Status of the cap, tinting the lead text and the progress bar.
    let level: HealthLevel
    /// Share of the cap used, 0...1; nil without a cap.
    let progress: Double?
    /// "of 5 GB · resets 1 Nov · ~2 days at this pace"; parts that are unknown are left out.
    let usageCaption: String?
    /// "↓ 3.17 GB · ↑ 572 MB".
    let transferCaption: String
    /// Why monitoring is (not) active.
    let statusText: String
    /// The measured interface and its caveat, for hover.
    let statusHelp: String?

    init(snapshot: MeteredUsageSnapshot, now: Date, calendar: Calendar = .current) {
        let outlook = MeteredUsageOutlook(snapshot: snapshot, now: now, calendar: calendar)
        let used = MeteredUsageFormatting.byteCount(snapshot.usedBytes)
        level = snapshot.usageLevel
        progress = snapshot.capBytes != nil ? snapshot.usageFraction.map { min(max($0, 0), 1) } : nil

        if let remaining = outlook.remainingBytes {
            leadText = snapshot.isCapReached || remaining == 0
                ? "Cap reached"
                : "\(MeteredUsageFormatting.byteCount(remaining)) left"
        } else {
            leadText = "Used \(used)"
        }

        if let capBytes = snapshot.capBytes {
            let parts = [
                "of \(MeteredUsageFormatting.byteCount(capBytes))",
                outlook.resetsAt.map { "resets \($0.formatted(.dateTime.month(.abbreviated).day()))" },
                outlook.estimatedDaysLeft.map(Self.paceText)
            ]
            usageCaption = parts.compactMap(\.self).joined(separator: " · ")
        } else {
            usageCaption = nil
        }

        let received = snapshot.billingPeriod == .session ? snapshot.sessionBytesReceived : snapshot.periodBytesReceived
        let sent = snapshot.billingPeriod == .session ? snapshot.sessionBytesSent : snapshot.periodBytesSent
        transferCaption = "↓ \(MeteredUsageFormatting.byteCount(received)) · ↑ \(MeteredUsageFormatting.byteCount(sent))"

        if snapshot.isMonitoringActive == false {
            statusText = "Not monitoring"
        } else if snapshot.isKnownMeteredNetwork {
            statusText = "Remembered metered network"
        } else if snapshot.manualSessionEnabled {
            statusText = "Turned on manually"
        } else {
            statusText = "Monitoring"
        }

        statusHelp = snapshot.meteredInterfaceName.map { "Measured on \($0) (default route). VPNs may shift this." }
    }

    /// "~2 days at this pace", "<1 day at this pace".
    static func paceText(_ days: Double) -> String {
        if days < 1 {
            return "<1 day at this pace"
        }

        if days >= 100 {
            return "100+ days at this pace"
        }

        let rounded = Int(days.rounded())
        return "~\(rounded) \(rounded == 1 ? "day" : "days") at this pace"
    }
}

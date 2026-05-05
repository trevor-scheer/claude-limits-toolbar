import Foundation

enum DurationFormatter {
    /// Compact "Xh Ym" / "Xd Yh" / "Xm" string for the time between `now` and `date`.
    static func compact(until date: Date, now: Date = Date()) -> String {
        let interval = max(0, date.timeIntervalSince(now))
        let totalMinutes = Int(interval / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let days = hours / 24

        if days >= 2 {
            let remHours = hours % 24
            return remHours > 0 ? "\(days)d \(remHours)h" : "\(days)d"
        }
        if hours >= 1 {
            return "\(hours)h \(minutes)m"
        }
        if totalMinutes >= 1 {
            return "\(totalMinutes)m"
        }
        return "<1m"
    }
}

enum PercentageFormatter {
    static func short(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }
}

enum BarLabel {
    static func text(state: UsageState, now: Date = Date()) -> String {
        switch state {
        case .loading:
            return "…"
        case .ok(let snap):
            return primary(snap: snap, now: now) ?? "—"
        case .error(_, let last):
            if let last, let body = primary(snap: last, now: now) {
                return "⚠️ " + body
            }
            return "⚠️"
        }
    }

    private static func primary(snap: UsageSnapshot, now: Date) -> String? {
        guard let five = snap.fiveHour else { return nil }
        let pct = PercentageFormatter.short(five.utilization)
        guard let resetsAt = five.resetsAt else { return pct }
        let dur = DurationFormatter.compact(until: resetsAt, now: now)
        return "\(pct) · \(dur)"
    }
}

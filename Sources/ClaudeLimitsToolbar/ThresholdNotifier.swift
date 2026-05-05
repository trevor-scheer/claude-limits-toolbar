import Foundation
import UserNotifications

protocol AlertSink: Sendable {
    func deliver(title: String, body: String, identifier: String) async
}

struct UNAlertSink: AlertSink {
    func deliver(title: String, body: String, identifier: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}

@MainActor
final class ThresholdNotifier {
    enum AlertLevel: Int { case none = 0, low = 1, high = 2 }

    private let defaults: UserDefaults
    private let sink: AlertSink

    init(defaults: UserDefaults = .standard, sink: AlertSink = UNAlertSink()) {
        self.defaults = defaults
        self.sink = sink
    }

    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func evaluate(snapshot: UsageSnapshot, settings: AppSettings) {
        for key in LimitKey.allCases {
            guard let limit = snapshot.limit(key) else { continue }
            evaluateLimit(key: key, limit: limit, settings: settings)
        }
    }

    private func evaluateLimit(key: LimitKey, limit: UsageLimit, settings: AppSettings) {
        let stateKey = "alertLevel.\(key.rawValue)"
        let resetsAtKey = "alertResetsAt.\(key.rawValue)"

        let storedResetsAt = defaults.object(forKey: resetsAtKey) as? Date
        var lastLevel = AlertLevel(rawValue: defaults.integer(forKey: stateKey)) ?? .none

        if storedResetsAt != limit.resetsAt {
            lastLevel = .none
            if let resetsAt = limit.resetsAt {
                defaults.set(resetsAt, forKey: resetsAtKey)
            } else {
                defaults.removeObject(forKey: resetsAtKey)
            }
            defaults.set(AlertLevel.none.rawValue, forKey: stateKey)
        }

        let pct = limit.utilization
        var newLevel = lastLevel

        if settings.highAlertEnabled, pct >= settings.highThreshold, lastLevel.rawValue < AlertLevel.high.rawValue {
            postAlert(key: key, level: .high, percentage: pct)
            newLevel = .high
        } else if settings.lowAlertEnabled, pct >= settings.lowThreshold, lastLevel.rawValue < AlertLevel.low.rawValue {
            postAlert(key: key, level: .low, percentage: pct)
            newLevel = .low
        }

        if newLevel != lastLevel {
            defaults.set(newLevel.rawValue, forKey: stateKey)
        }
    }

    private func postAlert(key: LimitKey, level: AlertLevel, percentage: Double) {
        let title = "Claude \(key.label) limit"
        let body = String(format: "You've used %.0f%% of this window.", percentage)
        let identifier = "\(key.rawValue).\(level.rawValue)"
        Task { await sink.deliver(title: title, body: body, identifier: identifier) }
    }
}

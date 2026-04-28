import Testing
import Foundation
@testable import ClaudeLimitsToolbar

@Suite struct ThresholdNotifierTests {
    @MainActor
    @Test func firesLowAlertOnFirstCrossing() async {
        let env = makeEnv()
        let notifier = ThresholdNotifier(defaults: env.defaults, sink: env.sink)

        notifier.evaluate(snapshot: makeSnapshot(fivePct: 80), settings: env.settings)
        await env.sink.waitForCount(1)

        let deliveries = await env.sink.snapshot()
        #expect(deliveries.count == 1)
        #expect(deliveries.first?.title.contains("5-hour") == true)
    }

    @MainActor
    @Test func doesNotRefireSameLevelInWindow() async {
        let env = makeEnv()
        let notifier = ThresholdNotifier(defaults: env.defaults, sink: env.sink)
        let resets = Date().addingTimeInterval(3600)

        notifier.evaluate(snapshot: makeSnapshot(fivePct: 80, resetsAt: resets), settings: env.settings)
        notifier.evaluate(snapshot: makeSnapshot(fivePct: 82, resetsAt: resets), settings: env.settings)
        notifier.evaluate(snapshot: makeSnapshot(fivePct: 85, resetsAt: resets), settings: env.settings)
        await env.sink.waitForCount(1)
        try? await Task.sleep(nanoseconds: 50_000_000)

        let count = await env.sink.snapshot().count
        #expect(count == 1)
    }

    @MainActor
    @Test func firesHighAlertWhenCrossingHigherThreshold() async {
        let env = makeEnv()
        let notifier = ThresholdNotifier(defaults: env.defaults, sink: env.sink)
        let resets = Date().addingTimeInterval(3600)

        notifier.evaluate(snapshot: makeSnapshot(fivePct: 80, resetsAt: resets), settings: env.settings)
        notifier.evaluate(snapshot: makeSnapshot(fivePct: 92, resetsAt: resets), settings: env.settings)
        await env.sink.waitForCount(2)

        #expect(await env.sink.snapshot().count == 2)
    }

    @MainActor
    @Test func resetWindowRearmsAlerts() async {
        let env = makeEnv()
        let notifier = ThresholdNotifier(defaults: env.defaults, sink: env.sink)
        let firstReset = Date().addingTimeInterval(3600)
        let secondReset = Date().addingTimeInterval(7200)

        notifier.evaluate(snapshot: makeSnapshot(fivePct: 80, resetsAt: firstReset), settings: env.settings)
        await env.sink.waitForCount(1)
        notifier.evaluate(snapshot: makeSnapshot(fivePct: 80, resetsAt: secondReset), settings: env.settings)
        await env.sink.waitForCount(2)

        #expect(await env.sink.snapshot().count == 2)
    }

    @MainActor
    @Test func respectsDisabledLowAlert() async {
        let env = makeEnv()
        env.settings.lowAlertEnabled = false
        let notifier = ThresholdNotifier(defaults: env.defaults, sink: env.sink)

        notifier.evaluate(snapshot: makeSnapshot(fivePct: 80), settings: env.settings)
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(await env.sink.snapshot().isEmpty)
    }

    @MainActor
    @Test func highAlertFiresEvenWhenLowDisabled() async {
        let env = makeEnv()
        env.settings.lowAlertEnabled = false
        let notifier = ThresholdNotifier(defaults: env.defaults, sink: env.sink)

        notifier.evaluate(snapshot: makeSnapshot(fivePct: 95), settings: env.settings)
        await env.sink.waitForCount(1)

        #expect(await env.sink.snapshot().count == 1)
    }

    // MARK: - helpers

    @MainActor
    private struct Env {
        let defaults: UserDefaults
        let sink: RecordingSink
        let settings: AppSettings
    }

    @MainActor
    private func makeEnv() -> Env {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return Env(
            defaults: defaults,
            sink: RecordingSink(),
            settings: AppSettings(defaults: defaults)
        )
    }

    private func makeSnapshot(fivePct: Double, resetsAt: Date = Date().addingTimeInterval(3600)) -> UsageSnapshot {
        UsageSnapshot(
            fiveHour: UsageLimit(utilization: fivePct, resetsAt: resetsAt),
            fetchedAt: Date()
        )
    }
}

actor RecordingSink: AlertSink {
    struct Delivery: Sendable { let title: String; let body: String; let identifier: String }
    private var deliveries: [Delivery] = []

    nonisolated func deliver(title: String, body: String, identifier: String) async {
        await append(Delivery(title: title, body: body, identifier: identifier))
    }

    private func append(_ d: Delivery) { deliveries.append(d) }

    func snapshot() -> [Delivery] { deliveries }

    func waitForCount(_ count: Int, timeout: TimeInterval = 1.0) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if deliveries.count >= count { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

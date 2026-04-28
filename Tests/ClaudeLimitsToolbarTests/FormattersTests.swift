import Testing
import Foundation
@testable import ClaudeLimitsToolbar

@Suite struct FormattersTests {
    private let now = Date(timeIntervalSince1970: 1_770_000_000)

    @Test func compactDuration_underAMinute() {
        #expect(DurationFormatter.compact(until: now.addingTimeInterval(15), now: now) == "<1m")
    }

    @Test func compactDuration_minutesOnly() {
        #expect(DurationFormatter.compact(until: now.addingTimeInterval(33 * 60), now: now) == "33m")
    }

    @Test func compactDuration_hoursAndMinutes() {
        #expect(DurationFormatter.compact(until: now.addingTimeInterval(2 * 3600 + 13 * 60), now: now) == "2h 13m")
    }

    @Test func compactDuration_days() {
        let oneDay: TimeInterval = 24 * 3600
        #expect(DurationFormatter.compact(until: now.addingTimeInterval(4 * oneDay + 18 * 3600), now: now) == "4d 18h")
    }

    @Test func compactDuration_negative() {
        #expect(DurationFormatter.compact(until: now.addingTimeInterval(-100), now: now) == "<1m")
    }

    @Test func barLabel_loading() {
        #expect(BarLabel.text(state: .loading, now: now) == "…")
    }

    @Test func barLabel_ok() {
        let snap = UsageSnapshot(
            fiveHour: UsageLimit(utilization: 47, resetsAt: now.addingTimeInterval(2 * 3600 + 13 * 60)),
            fetchedAt: now
        )
        #expect(BarLabel.text(state: .ok(snap), now: now) == "47% · 2h 13m")
    }

    @Test func barLabel_errorWithLastKnown() {
        let snap = UsageSnapshot(
            fiveHour: UsageLimit(utilization: 47, resetsAt: now.addingTimeInterval(2 * 3600 + 13 * 60)),
            fetchedAt: now
        )
        #expect(
            BarLabel.text(state: .error(.network("oops"), lastKnown: snap), now: now)
            == "⚠️ 47% · 2h 13m"
        )
    }

    @Test func barLabel_errorNoLastKnown() {
        #expect(BarLabel.text(state: .error(.noKeychainEntry, lastKnown: nil), now: now) == "⚠️")
    }

    @Test func barLabel_okWithNoFiveHour() {
        let snap = UsageSnapshot(fetchedAt: now)
        #expect(BarLabel.text(state: .ok(snap), now: now) == "—")
    }
}

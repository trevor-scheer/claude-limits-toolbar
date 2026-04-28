import Testing
import Foundation
@testable import ClaudeLimitsToolbar

@Suite struct UsageStoreTests {
    @Test func roundTripsSnapshot() {
        let suite = "store-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = UserDefaultsUsageStore(defaults: defaults)
        let original = UsageSnapshot(
            fiveHour: UsageLimit(utilization: 47, resetsAt: Date(timeIntervalSince1970: 1_770_000_000)),
            sevenDay: UsageLimit(utilization: 35, resetsAt: Date(timeIntervalSince1970: 1_770_500_000)),
            fetchedAt: Date(timeIntervalSince1970: 1_769_999_000)
        )
        store.save(original)
        let loaded = store.load()
        #expect(loaded?.fiveHour?.utilization == 47)
        #expect(loaded?.sevenDay?.utilization == 35)
        #expect(abs((loaded?.fetchedAt.timeIntervalSince1970 ?? 0) - 1_769_999_000) < 0.001)
    }

    @Test func returnsNilWhenEmpty() {
        let suite = "store-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsUsageStore(defaults: defaults)
        #expect(store.load() == nil)
    }
}

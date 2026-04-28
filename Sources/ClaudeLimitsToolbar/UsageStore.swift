import Foundation

protocol UsageStore {
    func load() -> UsageSnapshot?
    func save(_ snapshot: UsageSnapshot)
}

struct UserDefaultsUsageStore: UsageStore {
    static let key = "lastSnapshot"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> UsageSnapshot? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(UsageSnapshot.self, from: data)
    }

    func save(_ snapshot: UsageSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshot) {
            defaults.set(data, forKey: Self.key)
        }
    }
}

final class InMemoryUsageStore: UsageStore, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: UsageSnapshot?

    init(initial: UsageSnapshot? = nil) { self.snapshot = initial }

    func load() -> UsageSnapshot? {
        lock.lock(); defer { lock.unlock() }
        return snapshot
    }

    func save(_ snapshot: UsageSnapshot) {
        lock.lock(); defer { lock.unlock() }
        self.snapshot = snapshot
    }
}

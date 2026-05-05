import Testing
import Foundation
@testable import ClaudeLimitsToolbar

@Suite struct CachingKeychainClientTests {
    @Test func returnsCachedTokenWithoutHittingInner() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cached = KeychainCredential(accessToken: "cached", expiresAt: now.addingTimeInterval(3600))
        let cache = InMemoryTokenCache(cached)
        let inner = CountingKeychainClient(credential: KeychainCredential(accessToken: "fresh", expiresAt: now.addingTimeInterval(7200)))
        let client = CachingKeychainClient(inner: inner, cache: cache, clock: { now })

        let cred = try client.fetchCredential()

        #expect(cred.accessToken == "cached")
        #expect(inner.callCount == 0)
    }

    @Test func cacheMissReadsInnerAndPopulatesCache() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cache = InMemoryTokenCache()
        let inner = CountingKeychainClient(credential: KeychainCredential(accessToken: "fresh", expiresAt: now.addingTimeInterval(7200)))
        let client = CachingKeychainClient(inner: inner, cache: cache, clock: { now })

        let cred = try client.fetchCredential()

        #expect(cred.accessToken == "fresh")
        #expect(inner.callCount == 1)
        #expect(cache.load()?.accessToken == "fresh")
    }

    @Test func expiredCacheRereadsInner() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        // Cached token expires in the past — must not be served.
        let cached = KeychainCredential(accessToken: "stale", expiresAt: now.addingTimeInterval(-10))
        let cache = InMemoryTokenCache(cached)
        let inner = CountingKeychainClient(credential: KeychainCredential(accessToken: "fresh", expiresAt: now.addingTimeInterval(7200)))
        let client = CachingKeychainClient(inner: inner, cache: cache, clock: { now })

        let cred = try client.fetchCredential()

        #expect(cred.accessToken == "fresh")
        #expect(inner.callCount == 1)
    }

    @Test func tokenWithinSkewIsTreatedAsExpired() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        // Within the 60s skew window — refresh proactively.
        let cached = KeychainCredential(accessToken: "almost", expiresAt: now.addingTimeInterval(30))
        let cache = InMemoryTokenCache(cached)
        let inner = CountingKeychainClient(credential: KeychainCredential(accessToken: "fresh", expiresAt: now.addingTimeInterval(7200)))
        let client = CachingKeychainClient(inner: inner, cache: cache, clock: { now })

        _ = try client.fetchCredential()
        #expect(inner.callCount == 1)
    }

    @Test func purgeCacheClearsAndForcesReread() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cached = KeychainCredential(accessToken: "cached", expiresAt: now.addingTimeInterval(3600))
        let cache = InMemoryTokenCache(cached)
        let inner = CountingKeychainClient(credential: KeychainCredential(accessToken: "fresh", expiresAt: now.addingTimeInterval(7200)))
        let client = CachingKeychainClient(inner: inner, cache: cache, clock: { now })

        client.purgeCache()
        #expect(cache.load() == nil)

        let cred = try client.fetchCredential()
        #expect(cred.accessToken == "fresh")
        #expect(inner.callCount == 1)
    }

    @Test func skipsCachingWhenInnerLacksExpiry() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cache = InMemoryTokenCache()
        let inner = CountingKeychainClient(credential: KeychainCredential(accessToken: "fresh", expiresAt: nil))
        let client = CachingKeychainClient(inner: inner, cache: cache, clock: { now })

        _ = try client.fetchCredential()
        #expect(cache.load() == nil)
    }

    @Test func parsesMillisecondExpiresAt() throws {
        let json = #"""
        {"claudeAiOauth": {"accessToken": "abc", "expiresAt": 1778017133759}}
        """#.data(using: .utf8)!

        let cred = try ClaudeKeychainClient.parseCredential(from: json)
        #expect(cred.accessToken == "abc")
        let expected = Date(timeIntervalSince1970: 1778017133.759)
        let actual = try #require(cred.expiresAt)
        #expect(abs(actual.timeIntervalSince(expected)) < 0.01)
    }

    @Test func parsesISOExpiresAt() throws {
        let json = #"""
        {"claudeAiOauth": {"accessToken": "abc", "expiresAt": "2026-12-31T00:00:00Z"}}
        """#.data(using: .utf8)!

        let cred = try ClaudeKeychainClient.parseCredential(from: json)
        let actual = try #require(cred.expiresAt)
        let expected = ISO8601DateFormatter().date(from: "2026-12-31T00:00:00Z")!
        #expect(abs(actual.timeIntervalSince(expected)) < 1.0)
    }
}

private final class CountingKeychainClient: KeychainClient, @unchecked Sendable {
    let credential: KeychainCredential
    private let lock = NSLock()
    private var _callCount = 0

    init(credential: KeychainCredential) {
        self.credential = credential
    }

    var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _callCount
    }

    func fetchCredential() throws -> KeychainCredential {
        lock.lock(); _callCount += 1; lock.unlock()
        return credential
    }
}

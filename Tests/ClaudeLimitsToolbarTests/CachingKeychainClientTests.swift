import Testing
import Foundation
@testable import ClaudeLimitsToolbar

@Suite struct CachingKeychainClientTests {
    @Test func returnsCachedTokenWithoutHittingInner() throws {
        let cached = KeychainCredential(accessToken: "cached", expiresAt: nil)
        let cache = InMemoryTokenCache(cached)
        let inner = CountingKeychainClient(credential: KeychainCredential(accessToken: "fresh", expiresAt: nil))
        let client = CachingKeychainClient(inner: inner, cache: cache)

        let cred = try client.fetchCredential()

        #expect(cred.accessToken == "cached")
        #expect(inner.callCount == 0)
    }

    @Test func cacheMissReadsInnerAndPopulatesCache() throws {
        let cache = InMemoryTokenCache()
        let inner = CountingKeychainClient(credential: KeychainCredential(accessToken: "fresh", expiresAt: nil))
        let client = CachingKeychainClient(inner: inner, cache: cache)

        let cred = try client.fetchCredential()

        #expect(cred.accessToken == "fresh")
        #expect(inner.callCount == 1)
        #expect(cache.load()?.accessToken == "fresh")
    }

    @Test func servesCachedTokenEvenWhenExpired() throws {
        // We don't refresh on time-based expiry — that would touch Claude's
        // keychain entry and prompt the user. The 401 retry path purges the
        // cache when the API actually rejects the token.
        let stale = KeychainCredential(accessToken: "stale", expiresAt: Date(timeIntervalSince1970: 0))
        let cache = InMemoryTokenCache(stale)
        let inner = CountingKeychainClient(credential: KeychainCredential(accessToken: "fresh", expiresAt: nil))
        let client = CachingKeychainClient(inner: inner, cache: cache)

        let cred = try client.fetchCredential()

        #expect(cred.accessToken == "stale")
        #expect(inner.callCount == 0)
    }

    @Test func purgeCacheClearsAndForcesReread() throws {
        let cached = KeychainCredential(accessToken: "cached", expiresAt: nil)
        let cache = InMemoryTokenCache(cached)
        let inner = CountingKeychainClient(credential: KeychainCredential(accessToken: "fresh", expiresAt: nil))
        let client = CachingKeychainClient(inner: inner, cache: cache)

        client.purgeCache()
        #expect(cache.load() == nil)

        let cred = try client.fetchCredential()
        #expect(cred.accessToken == "fresh")
        #expect(inner.callCount == 1)
    }

    @Test func cachesEvenWhenExpiryUnknown() throws {
        let cache = InMemoryTokenCache()
        let inner = CountingKeychainClient(credential: KeychainCredential(accessToken: "fresh", expiresAt: nil))
        let client = CachingKeychainClient(inner: inner, cache: cache)

        _ = try client.fetchCredential()
        #expect(cache.load()?.accessToken == "fresh")
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

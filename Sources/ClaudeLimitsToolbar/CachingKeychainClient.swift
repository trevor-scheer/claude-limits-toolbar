import Foundation
import Security

/// Persists the access token in storage we own, so subsequent reads don't have
/// to touch Claude Code's keychain entry — which would re-prompt the user
/// every time the CLI rotates its credential.
protocol TokenCache: Sendable {
    func load() -> KeychainCredential?
    func save(_ credential: KeychainCredential) throws
    func purge()
}

struct CachingKeychainClient: KeychainClient {
    let inner: KeychainClient
    let cache: TokenCache
    /// Skew below the token's expiry where we proactively refresh.
    let refreshSkew: TimeInterval
    let clock: @Sendable () -> Date

    init(
        inner: KeychainClient,
        cache: TokenCache,
        refreshSkew: TimeInterval = 60,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.inner = inner
        self.cache = cache
        self.refreshSkew = refreshSkew
        self.clock = clock
    }

    func fetchCredential() throws -> KeychainCredential {
        if let cached = cache.load(), let exp = cached.expiresAt, exp > clock().addingTimeInterval(refreshSkew) {
            return cached
        }
        let fresh = try inner.fetchCredential()
        if fresh.expiresAt != nil {
            try? cache.save(fresh)
        }
        return fresh
    }

    func purgeCache() {
        cache.purge()
        inner.purgeCache()
    }
}

/// Stores a single credential as a JSON-encoded keychain item under our own
/// service. Reading items we created ourselves does not prompt.
struct KeychainTokenCache: TokenCache {
    let service: String
    let account: String

    init(service: String = "com.trevorscheer.claude-limits-toolbar.token-cache",
         account: String = "default") {
        self.service = service
        self.account = account
    }

    private struct Payload: Codable {
        var accessToken: String
        var expiresAt: Date?
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func load() -> KeychainCredential? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(Payload.self, from: data) else { return nil }
        return KeychainCredential(accessToken: payload.accessToken, expiresAt: payload.expiresAt)
    }

    func save(_ credential: KeychainCredential) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Payload(accessToken: credential.accessToken, expiresAt: credential.expiresAt))

        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(add as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let attrs: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attrs as CFDictionary)
            if updateStatus != errSecSuccess {
                throw UsageError.keychainAccessFailed(updateStatus)
            }
        default:
            throw UsageError.keychainAccessFailed(addStatus)
        }
    }

    func purge() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

/// In-memory implementation for tests.
final class InMemoryTokenCache: TokenCache, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: KeychainCredential?

    init(_ initial: KeychainCredential? = nil) {
        self.stored = initial
    }

    func load() -> KeychainCredential? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func save(_ credential: KeychainCredential) throws {
        lock.lock(); defer { lock.unlock() }
        stored = credential
    }

    func purge() {
        lock.lock(); defer { lock.unlock() }
        stored = nil
    }
}

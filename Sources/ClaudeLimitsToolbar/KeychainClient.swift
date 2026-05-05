import Foundation
import Security

struct KeychainCredential: Equatable, Sendable {
    var accessToken: String
    /// `expiresAt` from the `claudeAiOauth` payload; `nil` if absent or unparseable.
    var expiresAt: Date?
}

protocol KeychainClient: Sendable {
    func fetchCredential() throws -> KeychainCredential
    func purgeCache()
}

extension KeychainClient {
    func fetchAccessToken() throws -> String {
        try fetchCredential().accessToken
    }
    func purgeCache() {}
}

struct ClaudeKeychainClient: KeychainClient {
    static let service = "Claude Code-credentials"

    func fetchCredential() throws -> KeychainCredential {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw UsageError.malformedKeychainPayload
            }
            return try Self.parseCredential(from: data)
        case errSecItemNotFound:
            throw UsageError.noKeychainEntry
        default:
            throw UsageError.keychainAccessFailed(status)
        }
    }

    static func parseCredential(from data: Data) throws -> KeychainCredential {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = json["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String,
            !token.isEmpty
        else {
            throw UsageError.malformedKeychainPayload
        }
        return KeychainCredential(accessToken: token, expiresAt: parseExpiresAt(oauth["expiresAt"]))
    }

    /// `expiresAt` is observed as a millisecond Unix timestamp in real payloads;
    /// the test fixtures use ISO 8601 strings. Accept both.
    static func parseExpiresAt(_ raw: Any?) -> Date? {
        if let millis = raw as? Double {
            return Date(timeIntervalSince1970: millis / 1000)
        }
        if let millis = raw as? Int {
            return Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
        }
        if let string = raw as? String {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f.date(from: string)
        }
        return nil
    }

    static func parseAccessToken(from data: Data) throws -> String {
        try parseCredential(from: data).accessToken
    }
}

struct StaticKeychainClient: KeychainClient {
    let credential: KeychainCredential
    init(token: String, expiresAt: Date? = nil) {
        self.credential = KeychainCredential(accessToken: token, expiresAt: expiresAt)
    }
    func fetchCredential() throws -> KeychainCredential { credential }
}

struct FailingKeychainClient: KeychainClient {
    let error: UsageError
    func fetchCredential() throws -> KeychainCredential { throw error }
}

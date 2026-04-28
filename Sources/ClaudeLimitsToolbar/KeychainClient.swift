import Foundation
import Security

protocol KeychainClient: Sendable {
    func fetchAccessToken() throws -> String
}

struct ClaudeKeychainClient: KeychainClient {
    static let service = "Claude Code-credentials"

    func fetchAccessToken() throws -> String {
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
            return try Self.parseAccessToken(from: data)
        case errSecItemNotFound:
            throw UsageError.noKeychainEntry
        default:
            throw UsageError.keychainAccessFailed(status)
        }
    }

    static func parseAccessToken(from data: Data) throws -> String {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = json["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String,
            !token.isEmpty
        else {
            throw UsageError.malformedKeychainPayload
        }
        return token
    }
}

struct StaticKeychainClient: KeychainClient {
    let token: String
    func fetchAccessToken() throws -> String { token }
}

struct FailingKeychainClient: KeychainClient {
    let error: UsageError
    func fetchAccessToken() throws -> String { throw error }
}

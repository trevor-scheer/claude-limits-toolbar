import Testing
import Foundation
@testable import ClaudeLimitsToolbar

@Suite struct KeychainClientTests {
    @Test func parsesAccessTokenFromExpectedShape() throws {
        let json = #"""
        {
          "claudeAiOauth": {
            "accessToken": "abc123",
            "refreshToken": "ref",
            "expiresAt": "2026-12-31T00:00:00Z"
          }
        }
        """#.data(using: .utf8)!

        #expect(try ClaudeKeychainClient.parseAccessToken(from: json) == "abc123")
    }

    @Test func rejectsMissingToken() {
        let json = #"""
        {"claudeAiOauth": {"refreshToken": "x"}}
        """#.data(using: .utf8)!

        #expect(throws: UsageError.malformedKeychainPayload) {
            try ClaudeKeychainClient.parseAccessToken(from: json)
        }
    }

    @Test func rejectsEmptyToken() {
        let json = #"""
        {"claudeAiOauth": {"accessToken": ""}}
        """#.data(using: .utf8)!

        #expect(throws: UsageError.malformedKeychainPayload) {
            try ClaudeKeychainClient.parseAccessToken(from: json)
        }
    }

    @Test func rejectsUnrelatedJSON() {
        let json = #"{"foo": "bar"}"#.data(using: .utf8)!

        #expect(throws: UsageError.malformedKeychainPayload) {
            try ClaudeKeychainClient.parseAccessToken(from: json)
        }
    }
}

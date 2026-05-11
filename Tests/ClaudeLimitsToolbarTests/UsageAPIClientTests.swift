import Testing
import Foundation
@testable import ClaudeLimitsToolbar

@Suite struct UsageAPIClientTests {
    @Test func decodesSampleResponse() throws {
        let json = #"""
        {
          "five_hour": {"utilization": 2.0, "resets_at": "2026-02-08T12:00:00+00:00"},
          "seven_day": {"utilization": 35.0, "resets_at": "2026-02-12T03:00:00+00:00"},
          "seven_day_sonnet": {"utilization": 3.0, "resets_at": "2026-02-12T19:00:00+00:00"},
          "seven_day_opus": null
        }
        """#.data(using: .utf8)!

        let r = try AnthropicUsageAPIClient.decode(json)

        #expect(r.fiveHour?.utilization == 2.0)
        #expect(r.sevenDay?.utilization == 35.0)
        #expect(r.sevenDaySonnet?.utilization == 3.0)
        #expect(r.sevenDayOpus == nil)

        let expected = ISO8601DateFormatter().date(from: "2026-02-08T12:00:00Z")!
        #expect(r.fiveHour?.resetsAt == expected)
    }

    @Test func decodesFractionalSecondTimestamps() throws {
        let json = #"""
        {"five_hour": {"utilization": 7.0, "resets_at": "2026-04-28T18:09:59.903642+00:00"}}
        """#.data(using: .utf8)!

        let r = try AnthropicUsageAPIClient.decode(json)
        let expected = ISO8601DateFormatter().date(from: "2026-04-28T18:09:59Z")!
        let actual = try #require(r.fiveHour?.resetsAt)
        #expect(abs(actual.timeIntervalSince(expected)) < 1.0)
    }

    @Test func decodesAllNull() throws {
        let json = #"""
        {"five_hour": null, "seven_day": null, "seven_day_sonnet": null, "seven_day_opus": null}
        """#.data(using: .utf8)!

        let r = try AnthropicUsageAPIClient.decode(json)
        #expect(r.fiveHour == nil)
        #expect(r.sevenDay == nil)
        #expect(r.sevenDaySonnet == nil)
        #expect(r.sevenDayOpus == nil)
    }

    /// Real response shape observed 2026-05-05: `resets_at` can be null when
    /// utilization is 0, and the response includes unknown top-level keys
    /// (`seven_day_oauth_apps`, `extra_usage`, etc.) we should ignore.
    @Test func decodesNullResetsAtAndUnknownKeys() throws {
        let json = #"""
        {
          "five_hour": {"utilization": 17.0, "resets_at": "2026-05-05T18:30:01.015066+00:00"},
          "seven_day": {"utilization": 16.0, "resets_at": "2026-05-11T14:00:00.015085+00:00"},
          "seven_day_oauth_apps": null,
          "seven_day_opus": null,
          "seven_day_sonnet": {"utilization": 0.0, "resets_at": null},
          "seven_day_cowork": null,
          "tangelo": null,
          "extra_usage": {"is_enabled": true, "monthly_limit": 5000, "used_credits": 0.0, "utilization": null, "currency": "USD"}
        }
        """#.data(using: .utf8)!

        let r = try AnthropicUsageAPIClient.decode(json)
        #expect(r.fiveHour?.utilization == 17.0)
        #expect(r.sevenDay?.utilization == 16.0)
        #expect(r.sevenDaySonnet?.utilization == 0.0)
        #expect(r.sevenDaySonnet?.resetsAt == nil)
        #expect(r.sevenDayOpus == nil)
    }

    @Test func decodingErrorIncludesKeyPath() {
        let json = #"""
        {"five_hour": {"resets_at": "2026-02-08T12:00:00+00:00"}}
        """#.data(using: .utf8)!

        do {
            _ = try AnthropicUsageAPIClient.decode(json)
            Issue.record("expected decode to throw")
        } catch let UsageError.decoding(detail) {
            #expect(detail.contains("utilization"))
            #expect(detail.contains("fiveHour"))
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func rejectsMalformedDate() {
        let json = #"""
        {"five_hour": {"utilization": 1, "resets_at": "yesterday"}}
        """#.data(using: .utf8)!

        #expect(throws: UsageError.self) {
            try AnthropicUsageAPIClient.decode(json)
        }
    }

    @Test func retryAfterParsesDeltaSeconds() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let parsed = AnthropicUsageAPIClient.parseRetryAfter("120", now: now)
        #expect(parsed == now.addingTimeInterval(120))
    }

    @Test func retryAfterParsesHTTPDate() {
        let parsed = AnthropicUsageAPIClient.parseRetryAfter("Wed, 21 Oct 2015 07:28:00 GMT")
        let expected = ISO8601DateFormatter().date(from: "2015-10-21T07:28:00Z")!
        #expect(parsed == expected)
    }

    @Test func retryAfterIgnoresGarbage() {
        #expect(AnthropicUsageAPIClient.parseRetryAfter("not a date") == nil)
        #expect(AnthropicUsageAPIClient.parseRetryAfter(nil) == nil)
        #expect(AnthropicUsageAPIClient.parseRetryAfter("") == nil)
        #expect(AnthropicUsageAPIClient.parseRetryAfter("   ") == nil)
    }

    @Test func parsesAnthropicErrorEnvelope() {
        let body = #"""
        {"type": "error", "error": {"type": "authentication_error", "message": "OAuth token expired"}}
        """#.data(using: .utf8)!

        let parsed = AnthropicUsageAPIClient.parseErrorBody(body)
        #expect(parsed.topLevelType == "error")
        #expect(parsed.errorType == "authentication_error")
        #expect(parsed.message == "OAuth token expired")
    }

    @Test func parseErrorBodyFallsBackToRawSnippet() {
        let body = "internal error: something went sideways".data(using: .utf8)!
        let parsed = AnthropicUsageAPIClient.parseErrorBody(body)
        #expect(parsed.errorType == nil)
        #expect(parsed.message?.contains("sideways") == true)
    }

    @Test func parseErrorBodyHandlesEmpty() {
        let parsed = AnthropicUsageAPIClient.parseErrorBody(Data())
        #expect(parsed == AnthropicUsageAPIClient.ParsedAPIError())
    }

    @Test func authFailureClassifierCatchesCommonShapes() {
        let cases: [(String?, String?)] = [
            ("authentication_error", nil),
            ("invalid_request_error", "OAuth token has expired"),
            (nil, "Token has been revoked"),
            ("permission_error", "Credentials lack scope"),
            (nil, "Bearer credential invalid"),
        ]
        for (errType, message) in cases {
            let parsed = AnthropicUsageAPIClient.ParsedAPIError(
                topLevelType: "error", errorType: errType, message: message
            )
            #expect(AnthropicUsageAPIClient.looksLikeAuthFailure(parsed),
                    "expected auth-like classification for type=\(errType ?? "nil") message=\(message ?? "nil")")
        }
    }

    @Test func authFailureClassifierRejectsRealRateLimits() {
        let parsed = AnthropicUsageAPIClient.ParsedAPIError(
            topLevelType: "error",
            errorType: "rate_limit_error",
            message: "You have exceeded your 5-hour token budget."
        )
        #expect(!AnthropicUsageAPIClient.looksLikeAuthFailure(parsed))
    }

    @Test func formatDetailJoinsTypeAndMessage() {
        let parsed = AnthropicUsageAPIClient.ParsedAPIError(
            errorType: "authentication_error",
            message: "token expired"
        )
        #expect(AnthropicUsageAPIClient.formatDetail(parsed) == "authentication_error: token expired")
    }

    @Test func formatDetailReturnsNilWhenEmpty() {
        #expect(AnthropicUsageAPIClient.formatDetail(AnthropicUsageAPIClient.ParsedAPIError()) == nil)
    }
}

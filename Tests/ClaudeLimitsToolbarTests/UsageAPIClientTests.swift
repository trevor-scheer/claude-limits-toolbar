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
}

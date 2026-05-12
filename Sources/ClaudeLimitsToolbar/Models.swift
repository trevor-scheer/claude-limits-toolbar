import Foundation

struct UsageLimit: Codable, Equatable, Hashable {
    var utilization: Double
    var resetsAt: Date?
}

struct UsageResponse: Decodable, Equatable {
    var fiveHour: UsageLimit?
    var sevenDay: UsageLimit?
    var sevenDaySonnet: UsageLimit?
    var sevenDayOpus: UsageLimit?
}

struct UsageSnapshot: Codable, Equatable {
    var fiveHour: UsageLimit?
    var sevenDay: UsageLimit?
    var sevenDaySonnet: UsageLimit?
    var sevenDayOpus: UsageLimit?
    var fetchedAt: Date

    init(fiveHour: UsageLimit? = nil,
         sevenDay: UsageLimit? = nil,
         sevenDaySonnet: UsageLimit? = nil,
         sevenDayOpus: UsageLimit? = nil,
         fetchedAt: Date) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDaySonnet = sevenDaySonnet
        self.sevenDayOpus = sevenDayOpus
        self.fetchedAt = fetchedAt
    }

    init(_ response: UsageResponse, fetchedAt: Date) {
        self.fiveHour = response.fiveHour
        self.sevenDay = response.sevenDay
        self.sevenDaySonnet = response.sevenDaySonnet
        self.sevenDayOpus = response.sevenDayOpus
        self.fetchedAt = fetchedAt
    }

    func limit(_ key: LimitKey) -> UsageLimit? {
        switch key {
        case .fiveHour: return fiveHour
        case .sevenDay: return sevenDay
        case .sevenDaySonnet: return sevenDaySonnet
        case .sevenDayOpus: return sevenDayOpus
        }
    }
}

enum LimitKey: String, CaseIterable, Hashable {
    case fiveHour
    case sevenDay
    case sevenDaySonnet
    case sevenDayOpus

    var label: String {
        switch self {
        case .fiveHour: return "5-hour"
        case .sevenDay: return "7-day"
        case .sevenDaySonnet: return "7-day Sonnet"
        case .sevenDayOpus: return "7-day Opus"
        }
    }
}

enum UsageError: Error, Equatable {
    case noKeychainEntry
    case keychainAccessFailed(OSStatus)
    case malformedKeychainPayload
    case tokenInvalid(detail: String? = nil)
    case rateLimited(retryAfter: Date?, detail: String? = nil)
    case serverError(Int, detail: String? = nil)
    case network(String)
    case decoding(String)

    /// True when the error is plausibly fixable by clearing the cached token
    /// and re-reading Claude's keychain entry. Drives the "Re-authenticate"
    /// affordance in the error banner.
    var isRecoverableByReauth: Bool {
        switch self {
        case .tokenInvalid, .rateLimited, .serverError, .malformedKeychainPayload:
            return true
        case .noKeychainEntry, .keychainAccessFailed, .network, .decoding:
            return false
        }
    }

    var displayMessage: String {
        switch self {
        case .noKeychainEntry:
            return "No Claude Code credentials in your keychain. Sign in to Claude Code, then refresh."
        case .keychainAccessFailed(let status):
            return "Couldn't read Claude Code credentials (status \(status))."
        case .malformedKeychainPayload:
            return "Claude Code credentials are present but couldn't be parsed."
        case .tokenInvalid(let detail):
            return appending(detail, to: "The access token was rejected. Try `claude /login`, then click Re-authenticate.")
        case .rateLimited(let retryAfter, let detail):
            let when: String
            if let retryAfter, retryAfter > Date() {
                let formatted = retryAfter.formatted(date: .omitted, time: .shortened)
                when = "Retrying at \(formatted)."
            } else {
                when = "Will retry."
            }
            // 429s often turn out to be stale-token symptoms in disguise;
            // nudge the user toward Re-authenticate / `claude /login` so they
            // aren't stuck waiting through a Retry-After window for nothing.
            let base = "Anthropic API is rate-limiting requests. \(when) If this persists, try Re-authenticate (or `claude /login`)."
            return appending(detail, to: base)
        case .serverError(let code, let detail):
            return appending(detail, to: "Anthropic API returned \(code).")
        case .network(let detail):
            return "Network error: \(detail)"
        case .decoding(let detail):
            return "Couldn't parse the API response: \(detail)"
        }
    }

    private func appending(_ detail: String?, to base: String) -> String {
        guard let detail, !detail.isEmpty else { return base }
        return "\(base) (\(detail))"
    }
}

enum UsageState: Equatable {
    case loading
    case ok(UsageSnapshot)
    case error(UsageError, lastKnown: UsageSnapshot?)

    var snapshot: UsageSnapshot? {
        switch self {
        case .loading: return nil
        case .ok(let s): return s
        case .error(_, let s): return s
        }
    }

    var error: UsageError? {
        if case .error(let e, _) = self { return e }
        return nil
    }
}

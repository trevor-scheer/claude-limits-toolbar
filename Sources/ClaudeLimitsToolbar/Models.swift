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
    case tokenInvalid
    case rateLimited(retryAfter: Date?)
    case serverError(Int)
    case network(String)
    case decoding(String)

    var displayMessage: String {
        switch self {
        case .noKeychainEntry:
            return "No Claude Code credentials in your keychain. Sign in to Claude Code, then refresh."
        case .keychainAccessFailed(let status):
            return "Couldn't read Claude Code credentials (status \(status))."
        case .malformedKeychainPayload:
            return "Claude Code credentials are present but couldn't be parsed."
        case .tokenInvalid:
            return "The access token was rejected (401). Try `claude /login`."
        case .rateLimited(let retryAfter):
            if let retryAfter, retryAfter > Date() {
                let formatted = retryAfter.formatted(date: .omitted, time: .shortened)
                return "Anthropic API is rate-limiting requests. Retrying at \(formatted)."
            }
            return "Anthropic API is rate-limiting requests. Will retry."
        case .serverError(let code):
            return "Anthropic API returned \(code)."
        case .network(let detail):
            return "Network error: \(detail)"
        case .decoding(let detail):
            return "Couldn't parse the API response: \(detail)"
        }
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

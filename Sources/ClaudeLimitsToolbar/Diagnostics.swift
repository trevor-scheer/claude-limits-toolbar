import Foundation
import os.log

/// One record per API call attempt. Captures everything we need to tell apart
/// a real rate limit from a credential issue masquerading as one, without
/// leaking the full access token to disk or clipboard.
struct APIExchange: Sendable {
    let timestamp: Date
    let tokenFingerprint: String
    let statusCode: Int?
    let retryAfter: String?
    let parsedErrorType: String?
    let parsedErrorMessage: String?
    let bodySnippet: String?
    let transportError: String?

    static func tokenFingerprint(_ token: String) -> String {
        guard token.count >= 8 else { return "(short)" }
        let head = token.prefix(4)
        let tail = token.suffix(4)
        return "\(head)…\(tail) [len=\(token.count)]"
    }
}

/// Bounded in-memory ring of recent API exchanges. Read from the main thread by
/// the "Copy details" affordance and written from the URLSession task that the
/// API client runs on, so accesses are lock-guarded.
final class DiagnosticsRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var exchanges: [APIExchange] = []
    private let limit: Int

    init(limit: Int = 20) {
        self.limit = limit
    }

    func record(_ exchange: APIExchange) {
        lock.lock(); defer { lock.unlock() }
        exchanges.append(exchange)
        if exchanges.count > limit {
            exchanges.removeFirst(exchanges.count - limit)
        }
    }

    func snapshot() -> [APIExchange] {
        lock.lock(); defer { lock.unlock() }
        return exchanges
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        exchanges.removeAll()
    }
}

enum DiagnosticsLog {
    static let api = Logger(subsystem: "com.trevorscheer.claude-limits-toolbar", category: "API")
}

/// Renders the recent API exchanges into a human-readable block suitable for
/// pasting into a bug report. Includes a stable header so we can recognize the
/// shape across versions.
enum DiagnosticsFormatter {
    static func format(_ exchanges: [APIExchange], state: UsageState, lastUpdatedAt: Date?) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var lines: [String] = []
        lines.append("Claude Limits Toolbar diagnostics")
        lines.append("generated: \(iso.string(from: Date()))")
        lines.append("state: \(describe(state))")
        if let lastUpdatedAt {
            lines.append("last successful update: \(iso.string(from: lastUpdatedAt))")
        } else {
            lines.append("last successful update: (none)")
        }
        lines.append("recent API exchanges (newest last, \(exchanges.count)):")
        if exchanges.isEmpty {
            lines.append("  (none yet)")
        }
        for ex in exchanges {
            lines.append("---")
            lines.append("  at: \(iso.string(from: ex.timestamp))")
            lines.append("  token: \(ex.tokenFingerprint)")
            if let status = ex.statusCode {
                lines.append("  status: \(status)")
            }
            if let retry = ex.retryAfter {
                lines.append("  retry-after: \(retry)")
            }
            if let t = ex.parsedErrorType {
                lines.append("  error.type: \(t)")
            }
            if let m = ex.parsedErrorMessage {
                lines.append("  error.message: \(m)")
            }
            if let snip = ex.bodySnippet {
                lines.append("  body: \(snip)")
            }
            if let err = ex.transportError {
                lines.append("  transport-error: \(err)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func describe(_ state: UsageState) -> String {
        switch state {
        case .loading: return "loading"
        case .ok: return "ok"
        case .error(let e, _): return "error(\(e))"
        }
    }
}

import Foundation

protocol UsageAPIClient: Sendable {
    func fetchUsage(token: String) async throws -> UsageResponse
}

struct AnthropicUsageAPIClient: UsageAPIClient {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    let session: URLSession
    let diagnostics: DiagnosticsRecorder?

    init(session: URLSession = .shared, diagnostics: DiagnosticsRecorder? = nil) {
        self.session = session
        self.diagnostics = diagnostics
    }

    func fetchUsage(token: String) async throws -> UsageResponse {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-limits-toolbar/0.1", forHTTPHeaderField: "User-Agent")

        let fingerprint = APIExchange.tokenFingerprint(token)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            record(APIExchange(
                timestamp: Date(),
                tokenFingerprint: fingerprint,
                statusCode: nil,
                retryAfter: nil,
                parsedErrorType: nil,
                parsedErrorMessage: nil,
                bodySnippet: nil,
                transportError: error.localizedDescription
            ))
            DiagnosticsLog.api.error("transport error: \(error.localizedDescription, privacy: .public)")
            throw UsageError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            record(APIExchange(
                timestamp: Date(),
                tokenFingerprint: fingerprint,
                statusCode: nil,
                retryAfter: nil,
                parsedErrorType: nil,
                parsedErrorMessage: nil,
                bodySnippet: nil,
                transportError: "Non-HTTP response"
            ))
            throw UsageError.network("Non-HTTP response")
        }

        let retryAfterHeader = http.value(forHTTPHeaderField: "Retry-After")
        let parsedForLog = (200..<300).contains(http.statusCode)
            ? AnthropicUsageAPIClient.ParsedAPIError()
            : Self.parseErrorBody(data)
        record(APIExchange(
            timestamp: Date(),
            tokenFingerprint: fingerprint,
            statusCode: http.statusCode,
            retryAfter: retryAfterHeader,
            parsedErrorType: parsedForLog.errorType,
            parsedErrorMessage: parsedForLog.message,
            bodySnippet: bodySnippet(data),
            transportError: nil
        ))
        DiagnosticsLog.api.log(
            "status=\(http.statusCode, privacy: .public) retry-after=\(retryAfterHeader ?? "-", privacy: .public) error.type=\(parsedForLog.errorType ?? "-", privacy: .public) error.message=\(parsedForLog.message ?? "-", privacy: .public)"
        )

        switch http.statusCode {
        case 200..<300:
            return try Self.decode(data)
        case 401, 403:
            throw UsageError.tokenInvalid(detail: Self.formatDetail(parsedForLog))
        case 429:
            // Anthropic occasionally returns 429 for non-rate-limit conditions
            // (notably credential problems). If the body's `error.type` reads
            // like an auth issue, route through the tokenInvalid path so the
            // caller's evict-and-retry recovery kicks in.
            if Self.looksLikeAuthFailure(parsedForLog) {
                throw UsageError.tokenInvalid(detail: Self.formatDetail(parsedForLog))
            }
            throw UsageError.rateLimited(
                retryAfter: Self.parseRetryAfter(retryAfterHeader, now: Date()),
                detail: Self.formatDetail(parsedForLog)
            )
        default:
            throw UsageError.serverError(http.statusCode, detail: Self.formatDetail(parsedForLog))
        }
    }

    private func record(_ exchange: APIExchange) {
        diagnostics?.record(exchange)
    }

    private func bodySnippet(_ data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        let raw = String(data: data.prefix(300), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw?.isEmpty == false ? raw : nil
    }

    struct ParsedAPIError: Equatable {
        var topLevelType: String?
        var errorType: String?
        var message: String?
    }

    /// Decodes Anthropic's standard error envelope:
    ///   {"type": "error", "error": {"type": "...", "message": "..."}}
    /// Falls back to a raw string snippet if the body isn't JSON.
    static func parseErrorBody(_ data: Data) -> ParsedAPIError {
        guard !data.isEmpty else { return ParsedAPIError() }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let top = json["type"] as? String
            let inner = json["error"] as? [String: Any]
            return ParsedAPIError(
                topLevelType: top,
                errorType: inner?["type"] as? String,
                message: inner?["message"] as? String
            )
        }
        let snippet = String(data: data.prefix(200), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedAPIError(message: snippet?.isEmpty == false ? snippet : nil)
    }

    /// Best-effort detail string for an error response — combines the parsed
    /// error type and message when present, else a raw snippet.
    static func parseErrorDetail(_ data: Data) -> String? {
        formatDetail(parseErrorBody(data))
    }

    static func formatDetail(_ parsed: ParsedAPIError) -> String? {
        var parts: [String] = []
        if let t = parsed.errorType, !t.isEmpty { parts.append(t) }
        if let m = parsed.message, !m.isEmpty { parts.append(m) }
        if parts.isEmpty { return nil }
        return parts.joined(separator: ": ")
    }

    /// 429 should be treated as an auth failure when the body says so. We match
    /// on common Anthropic error types and on substrings that show up in their
    /// messages for OAuth credential issues.
    static func looksLikeAuthFailure(_ parsed: ParsedAPIError) -> Bool {
        let needles = [
            "authentication",
            "unauthorized",
            "invalid_api_key",
            "invalid_token",
            "invalid_request",
            "permission",
            "credential",
            "expired",
            "revoked",
            "oauth",
        ]
        let haystack = [parsed.errorType, parsed.message]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        guard !haystack.isEmpty else { return false }
        return needles.contains(where: haystack.contains)
    }

    /// Parses RFC 7231 §7.1.3 `Retry-After` — either delta-seconds or HTTP-date.
    static func parseRetryAfter(_ raw: String?, now: Date = Date()) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
            return nil
        }
        if let seconds = TimeInterval(raw) {
            return now.addingTimeInterval(seconds)
        }
        return httpDateFormatter.date(from: raw)
    }

    private static let httpDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()

    static func decode(_ data: Data) throws -> UsageResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = Self.iso.date(from: raw) { return date }
            if let date = Self.isoFractional.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(raw)"
            )
        }
        do {
            return try decoder.decode(UsageResponse.self, from: data)
        } catch {
            throw UsageError.decoding(describe(decodingError: error))
        }
    }

    /// `localizedDescription` collapses `DecodingError` to a vague string.
    /// Surface the key path and underlying detail so schema drift is debuggable.
    static func describe(decodingError error: Error) -> String {
        guard let decoding = error as? DecodingError else {
            return error.localizedDescription
        }
        switch decoding {
        case .keyNotFound(let key, let ctx):
            return "missing key \"\(key.stringValue)\" at \(pathString(ctx.codingPath))"
        case .valueNotFound(let type, let ctx):
            return "missing \(type) at \(pathString(ctx.codingPath))"
        case .typeMismatch(let type, let ctx):
            return "expected \(type) at \(pathString(ctx.codingPath))"
        case .dataCorrupted(let ctx):
            return "\(ctx.debugDescription) at \(pathString(ctx.codingPath))"
        @unknown default:
            return String(describing: decoding)
        }
    }

    private static func pathString(_ path: [CodingKey]) -> String {
        path.isEmpty ? "<root>" : path.map(\.stringValue).joined(separator: ".")
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

struct StubUsageAPIClient: UsageAPIClient {
    let result: Result<UsageResponse, UsageError>
    func fetchUsage(token: String) async throws -> UsageResponse {
        switch result {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }
}

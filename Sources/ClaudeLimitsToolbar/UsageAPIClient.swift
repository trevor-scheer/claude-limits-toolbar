import Foundation

protocol UsageAPIClient: Sendable {
    func fetchUsage(token: String) async throws -> UsageResponse
}

struct AnthropicUsageAPIClient: UsageAPIClient {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchUsage(token: String) async throws -> UsageResponse {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-limits-toolbar/0.1", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UsageError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw UsageError.network("Non-HTTP response")
        }

        switch http.statusCode {
        case 200..<300:
            return try Self.decode(data)
        case 401, 403:
            throw UsageError.tokenInvalid
        case 429:
            throw UsageError.rateLimited
        default:
            throw UsageError.serverError(http.statusCode)
        }
    }

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
            throw UsageError.decoding(error.localizedDescription)
        }
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

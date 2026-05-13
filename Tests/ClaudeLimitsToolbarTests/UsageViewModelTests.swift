import Testing
import Foundation
@testable import ClaudeLimitsToolbar

@Suite struct UsageViewModelTests {
    @MainActor
    @Test func rateLimitedFirstAttemptPurgesCacheAndRetriesOnce() async {
        let env = makeEnv()
        // Cache starts populated, inner has the "fresh" token Claude's keychain
        // would hand back after a purge.
        env.cache.populate(KeychainCredential(accessToken: "cached-stale", expiresAt: nil))
        env.inner.credential = KeychainCredential(accessToken: "fresh-after-purge", expiresAt: nil)

        env.api.queue([
            .failure(.rateLimited(retryAfter: Date().addingTimeInterval(60), detail: nil)),
            .success(sampleResponse()),
        ])

        let vm = makeViewModel(env: env)
        vm.start()
        await env.api.waitForCalls(2)
        await waitUntil { vm.state.snapshot != nil }

        #expect(env.api.callCount == 2)
        #expect(env.api.tokensSeen == ["cached-stale", "fresh-after-purge"])
        // Final state should be ok, not rateLimited.
        if case .ok = vm.state {} else {
            Issue.record("expected .ok, got \(vm.state)")
        }
    }

    @MainActor
    @Test func rateLimitedSecondAttemptEntersCooldown() async {
        let env = makeEnv()
        env.cache.populate(KeychainCredential(accessToken: "cached", expiresAt: nil))
        env.inner.credential = KeychainCredential(accessToken: "fresh", expiresAt: nil)

        let retryAfter = Date().addingTimeInterval(3600)
        env.api.queue([
            .failure(.rateLimited(retryAfter: retryAfter, detail: nil)),
            .failure(.rateLimited(retryAfter: retryAfter, detail: nil)),
        ])

        let vm = makeViewModel(env: env)
        vm.start()
        await env.api.waitForCalls(2)
        await waitUntil {
            if case .error(.rateLimited, _) = vm.state { return true }
            return false
        }

        #expect(env.api.callCount == 2)
        if case .error(.rateLimited, _) = vm.state {} else {
            Issue.record("expected rateLimited error, got \(vm.state)")
        }
    }

    @MainActor
    @Test func tokenInvalidRetryStillFiresEvenWhenInnerHasSameToken() async {
        // Real-world scenario from 2026-05-12: same token served by both the
        // cache and Claude's keychain, server starts returning 401. The retry
        // must still happen (and be observable) so diagnostics capture it.
        let env = makeEnv()
        let same = KeychainCredential(accessToken: "sk-same", expiresAt: nil)
        env.cache.populate(same)
        env.inner.credential = same

        env.api.queue([
            .failure(.tokenInvalid(detail: "authentication_error: Invalid authentication credentials")),
            .failure(.tokenInvalid(detail: "authentication_error: Invalid authentication credentials")),
        ])

        let vm = makeViewModel(env: env)
        vm.start()
        await env.api.waitForCalls(2)
        await waitUntil {
            if case .error(.tokenInvalid, _) = vm.state { return true }
            return false
        }

        #expect(env.api.callCount == 2)
        #expect(env.api.tokensSeen == ["sk-same", "sk-same"])
        if case .error(.tokenInvalid, _) = vm.state {} else {
            Issue.record("expected tokenInvalid, got \(vm.state)")
        }
    }

    @MainActor
    @Test func tokenInvalidStillRecoversAfterPurge() async {
        let env = makeEnv()
        env.cache.populate(KeychainCredential(accessToken: "stale", expiresAt: nil))
        env.inner.credential = KeychainCredential(accessToken: "fresh", expiresAt: nil)

        env.api.queue([
            .failure(.tokenInvalid(detail: "expired")),
            .success(sampleResponse()),
        ])

        let vm = makeViewModel(env: env)
        vm.start()
        await env.api.waitForCalls(2)
        await waitUntil { vm.state.snapshot != nil }

        #expect(env.api.tokensSeen == ["stale", "fresh"])
        if case .ok = vm.state {} else {
            Issue.record("expected .ok, got \(vm.state)")
        }
    }

    @MainActor
    @Test func reauthenticatePurgesAndRefetches() async {
        let env = makeEnv()
        env.cache.populate(KeychainCredential(accessToken: "stale", expiresAt: nil))
        env.inner.credential = KeychainCredential(accessToken: "fresh", expiresAt: nil)

        // First refresh: rate-limited twice (retry path exhausts), lands in cooldown.
        let retryAfter = Date().addingTimeInterval(3600)
        env.api.queue([
            .failure(.rateLimited(retryAfter: retryAfter, detail: nil)),
            .failure(.rateLimited(retryAfter: retryAfter, detail: nil)),
            .success(sampleResponse()),
        ])

        let vm = makeViewModel(env: env)
        vm.start()
        await env.api.waitForCalls(2)
        await waitUntil {
            if case .error(.rateLimited, _) = vm.state { return true }
            return false
        }

        // Inner had been read during the auto-retry. Re-prime the inner to
        // simulate that `claude /login` produced a new token since.
        env.inner.credential = KeychainCredential(accessToken: "post-reauth", expiresAt: nil)
        env.api.queueOne(.success(sampleResponse()))

        vm.reauthenticate()

        await env.api.waitForCalls(3)
        await waitUntil { vm.state.snapshot != nil }

        #expect(env.api.tokensSeen.last == "post-reauth")
        if case .ok = vm.state {} else {
            Issue.record("expected .ok after reauth, got \(vm.state)")
        }
    }

    // MARK: - helpers

    @MainActor
    private struct Env {
        let cache: InMemoryTokenCache
        let inner: MutableKeychainClient
        let api: ScriptedAPIClient
        let store: InMemoryUsageStore
        let notifier: ThresholdNotifier
        let settings: AppSettings
    }

    @MainActor
    private func makeEnv() -> Env {
        let suite = "vm-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = AppSettings(defaults: defaults)
        // Long interval — we drive the loop manually via state transitions, not
        // by waiting on its sleep.
        settings.refreshIntervalSeconds = 3600
        return Env(
            cache: InMemoryTokenCache(),
            inner: MutableKeychainClient(credential: KeychainCredential(accessToken: "fresh", expiresAt: nil)),
            api: ScriptedAPIClient(),
            store: InMemoryUsageStore(),
            notifier: ThresholdNotifier(defaults: defaults, sink: NoopAlertSink()),
            settings: settings
        )
    }

    @MainActor
    private func makeViewModel(env: Env) -> UsageViewModel {
        UsageViewModel(
            keychain: CachingKeychainClient(inner: env.inner, cache: env.cache),
            api: env.api,
            store: env.store,
            notifier: env.notifier,
            settings: env.settings
        )
    }

    private func sampleResponse() -> UsageResponse {
        let json = #"""
        {"five_hour": {"utilization": 7.0, "resets_at": "2026-04-28T18:09:59+00:00"}}
        """#.data(using: .utf8)!
        return try! AnthropicUsageAPIClient.decode(json)
    }

    @MainActor
    private func waitUntil(_ predicate: () -> Bool, timeout: TimeInterval = 2.0) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

// MARK: - Test doubles

extension InMemoryTokenCache {
    func populate(_ credential: KeychainCredential) {
        try? save(credential)
    }
}

final class MutableKeychainClient: KeychainClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _credential: KeychainCredential

    init(credential: KeychainCredential) {
        self._credential = credential
    }

    var credential: KeychainCredential {
        get { lock.lock(); defer { lock.unlock() }; return _credential }
        set { lock.lock(); _credential = newValue; lock.unlock() }
    }

    func fetchCredential() throws -> KeychainCredential { credential }
}

final class ScriptedAPIClient: UsageAPIClient, @unchecked Sendable {
    private let lock = NSLock()
    private var queueItems: [Result<UsageResponse, UsageError>] = []
    private var _tokensSeen: [String] = []

    func queue(_ results: [Result<UsageResponse, UsageError>]) {
        lock.lock(); defer { lock.unlock() }
        queueItems.append(contentsOf: results)
    }

    func queueOne(_ result: Result<UsageResponse, UsageError>) {
        queue([result])
    }

    var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _tokensSeen.count
    }

    var tokensSeen: [String] {
        lock.lock(); defer { lock.unlock() }
        return _tokensSeen
    }

    func fetchUsage(token: String) async throws -> UsageResponse {
        let next: Result<UsageResponse, UsageError>? = {
            lock.lock(); defer { lock.unlock() }
            _tokensSeen.append(token)
            return queueItems.isEmpty ? nil : queueItems.removeFirst()
        }()
        guard let next else {
            throw UsageError.network("scripted-api exhausted")
        }
        switch next {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }

    func waitForCalls(_ target: Int, timeout: TimeInterval = 2.0) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if callCount >= target { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

actor NoopAlertSink: AlertSink {
    nonisolated func deliver(title: String, body: String, identifier: String) async {}
}

import Foundation
import Combine
#if canImport(AppKit)
import AppKit
#endif

@MainActor
final class UsageViewModel: ObservableObject {
    @Published private(set) var state: UsageState
    @Published private(set) var lastUpdatedAt: Date?
    @Published var isRefreshing: Bool = false

    private let keychain: KeychainClient
    private let api: UsageAPIClient
    private let store: UsageStore
    private let notifier: ThresholdNotifier
    private let settings: AppSettings
    private let diagnostics: DiagnosticsRecorder?

    private var loopTask: Task<Void, Never>?
    private var settingsCancellable: AnyCancellable?

    init(keychain: KeychainClient,
         api: UsageAPIClient,
         store: UsageStore,
         notifier: ThresholdNotifier,
         settings: AppSettings,
         diagnostics: DiagnosticsRecorder? = nil) {
        self.keychain = keychain
        self.api = api
        self.store = store
        self.notifier = notifier
        self.settings = settings
        self.diagnostics = diagnostics

        let last = store.load()
        if let last {
            self.state = .ok(last)
            self.lastUpdatedAt = last.fetchedAt
        } else {
            self.state = .loading
            self.lastUpdatedAt = nil
        }
    }

    func start() {
        observeSettings()
        observeWake()
        restartLoop()
    }

    private func observeWake() {
        #if canImport(AppKit)
        NotificationCenter.default.removeObserver(
            self,
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }
        #endif
    }

    func refreshNow() {
        if rateLimitCooldownRemaining() != nil {
            return
        }
        restartLoop()
    }

    /// Force-purge the cached access token and immediately re-read Claude's
    /// keychain entry. Used by the "Re-authenticate" affordance when the cache
    /// is wedged on a stale token the API isn't honoring.
    func reauthenticate() {
        keychain.purgeCache()
        if case .error(.rateLimited, let last) = state {
            state = .error(.tokenInvalid(detail: "Re-authenticating…"), lastKnown: last)
        }
        restartLoop()
    }

    /// Build a paste-able diagnostics report and copy it to the clipboard.
    /// Returns the report so tests can introspect it. Used by the error
    /// banner's "Copy details" button.
    @discardableResult
    func copyDiagnostics() -> String {
        let report = DiagnosticsFormatter.format(
            diagnostics?.snapshot() ?? [],
            state: state,
            lastUpdatedAt: lastUpdatedAt
        )
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        #endif
        return report
    }

    private func restartLoop() {
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    private func runLoop() async {
        while !Task.isCancelled {
            await performRefresh()
            let seconds = nextSleepSeconds()
            do {
                try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            } catch {
                return
            }
        }
    }

    private func nextSleepSeconds() -> Int {
        let normal = max(30, settings.refreshIntervalSeconds)
        if let cooldown = rateLimitCooldownRemaining() {
            return max(normal, cooldown)
        }
        return normal
    }

    /// Returns seconds remaining until the API's `Retry-After` deadline, or `nil` if not in cooldown.
    private func rateLimitCooldownRemaining() -> Int? {
        guard case .error(.rateLimited(let retryAfter, _), _) = state,
              let retryAfter else { return nil }
        let delta = retryAfter.timeIntervalSinceNow
        guard delta > 0 else { return nil }
        return Int(delta.rounded(.up))
    }

    private func performRefresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        await attemptRefresh(allowRetry: true)
    }

    private func attemptRefresh(allowRetry: Bool) async {
        let token: String
        do {
            token = try keychain.fetchAccessToken()
        } catch let e as UsageError {
            state = .error(e, lastKnown: state.snapshot)
            return
        } catch {
            state = .error(.network(error.localizedDescription), lastKnown: state.snapshot)
            return
        }

        do {
            let response = try await api.fetchUsage(token: token)
            let snapshot = UsageSnapshot(response, fetchedAt: Date())
            store.save(snapshot)
            state = .ok(snapshot)
            lastUpdatedAt = snapshot.fetchedAt
            notifier.evaluate(snapshot: snapshot, settings: settings)
        } catch UsageError.tokenInvalid where allowRetry {
            // Cached token may be stale (claude /login or server-side rotation).
            // Evict and re-read Claude's keychain entry once.
            keychain.purgeCache()
            await attemptRefresh(allowRetry: false)
        } catch UsageError.rateLimited where allowRetry {
            // Belt-and-suspenders: even when the body doesn't explicitly look
            // like an auth failure, a 429 on the very first attempt of a cycle
            // is often a stale-token symptom. Purge once and try with a fresh
            // credential; if it still 429s, the second attempt will respect
            // Retry-After.
            keychain.purgeCache()
            await attemptRefresh(allowRetry: false)
        } catch let e as UsageError {
            state = .error(e, lastKnown: state.snapshot)
        } catch {
            state = .error(.network(error.localizedDescription), lastKnown: state.snapshot)
        }
    }

    private func observeSettings() {
        settingsCancellable = settings.$refreshIntervalSeconds
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.restartLoop() }
    }
}

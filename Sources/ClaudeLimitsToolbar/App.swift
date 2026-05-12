import SwiftUI
import AppKit
import UserNotifications

@MainActor
final class AppContext: ObservableObject {
    let settings: AppSettings
    let viewModel: UsageViewModel
    let notifier: ThresholdNotifier

    init() {
        let settings = AppSettings()
        let notifier = ThresholdNotifier()
        let diagnostics = DiagnosticsRecorder()
        self.settings = settings
        self.notifier = notifier
        self.viewModel = UsageViewModel(
            keychain: CachingKeychainClient(
                inner: ClaudeKeychainClient(),
                cache: KeychainTokenCache()
            ),
            api: AnthropicUsageAPIClient(diagnostics: diagnostics),
            store: UserDefaultsUsageStore(),
            notifier: notifier,
            settings: settings,
            diagnostics: diagnostics
        )
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let context = AppContext()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if !context.settings.hasCompletedFirstLaunch {
            context.settings.hasCompletedFirstLaunch = true
            LaunchAtLoginHelper.setEnabled(context.settings.launchAtLogin)
        }

        Task { @MainActor in
            await context.notifier.requestAuthorization()
        }

        context.viewModel.start()
    }
}

@main
struct ClaudeLimitsToolbarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(delegate.context.viewModel)
                .environmentObject(delegate.context.settings)
        } label: {
            MenuBarLabel(viewModel: delegate.context.viewModel)
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView()
                .environmentObject(delegate.context.settings)
        }
    }
}

import Foundation
import Combine

@MainActor
final class AppSettings: ObservableObject {
    @Published var lowThreshold: Double
    @Published var highThreshold: Double
    @Published var lowAlertEnabled: Bool
    @Published var highAlertEnabled: Bool
    @Published var refreshIntervalSeconds: Int
    @Published var launchAtLogin: Bool
    @Published var hasCompletedFirstLaunch: Bool

    private let defaults: UserDefaults
    private var cancellables: Set<AnyCancellable> = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "lowThreshold": 75.0,
            "highThreshold": 90.0,
            "lowAlertEnabled": true,
            "highAlertEnabled": true,
            "refreshIntervalSeconds": 120,
            "launchAtLogin": true,
            "hasCompletedFirstLaunch": false,
        ])
        self.lowThreshold = defaults.double(forKey: "lowThreshold")
        self.highThreshold = defaults.double(forKey: "highThreshold")
        self.lowAlertEnabled = defaults.bool(forKey: "lowAlertEnabled")
        self.highAlertEnabled = defaults.bool(forKey: "highAlertEnabled")
        self.refreshIntervalSeconds = defaults.integer(forKey: "refreshIntervalSeconds")
        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        self.hasCompletedFirstLaunch = defaults.bool(forKey: "hasCompletedFirstLaunch")

        bind($lowThreshold, key: "lowThreshold")
        bind($highThreshold, key: "highThreshold")
        bind($lowAlertEnabled, key: "lowAlertEnabled")
        bind($highAlertEnabled, key: "highAlertEnabled")
        bind($refreshIntervalSeconds, key: "refreshIntervalSeconds")
        bind($launchAtLogin, key: "launchAtLogin")
        bind($hasCompletedFirstLaunch, key: "hasCompletedFirstLaunch")
    }

    private func bind<T>(_ publisher: Published<T>.Publisher, key: String) {
        publisher
            .dropFirst()
            .sink { [defaults] value in defaults.set(value, forKey: key) }
            .store(in: &cancellables)
    }
}

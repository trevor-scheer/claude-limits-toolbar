import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Alerts") {
                ThresholdRow(
                    title: "First warning",
                    enabled: $settings.lowAlertEnabled,
                    threshold: $settings.lowThreshold
                )
                ThresholdRow(
                    title: "High warning",
                    enabled: $settings.highAlertEnabled,
                    threshold: $settings.highThreshold
                )
            }

            Section("Refresh") {
                Picker("Interval", selection: $settings.refreshIntervalSeconds) {
                    Text("60 seconds").tag(60)
                    Text("2 minutes").tag(120)
                    Text("5 minutes").tag(300)
                    Text("10 minutes").tag(600)
                    Text("15 minutes").tag(900)
                    Text("30 minutes").tag(1800)
                    Text("1 hour").tag(3600)
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { newValue in
                        settings.launchAtLogin = newValue
                        LaunchAtLoginHelper.setEnabled(newValue)
                    }
                ))
            }

            Section("About") {
                LabeledContent("Version", value: "0.1.0")
                Link("github.com/trevor-scheer/claude-limits-toolbar",
                     destination: URL(string: "https://github.com/trevor-scheer/claude-limits-toolbar")!)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 420)
    }
}

private struct ThresholdRow: View {
    let title: String
    @Binding var enabled: Bool
    @Binding var threshold: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(title, isOn: $enabled)
            HStack {
                Slider(value: $threshold, in: 50...95, step: 5)
                    .disabled(!enabled)
                Text(String(format: "%.0f%%", threshold))
                    .frame(width: 48, alignment: .trailing)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(enabled ? .primary : .secondary)
            }
        }
    }
}

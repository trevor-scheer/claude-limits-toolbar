import SwiftUI
import AppKit

struct PopoverView: View {
    @EnvironmentObject var viewModel: UsageViewModel
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = viewModel.state.error {
                ErrorBanner(
                    error: error,
                    onReauth: { viewModel.reauthenticate() },
                    onCopyDetails: { viewModel.copyDiagnostics() }
                )
                Divider()
            }

            content

            Divider()
            FooterBar(
                lastUpdatedAt: viewModel.lastUpdatedAt,
                isRefreshing: viewModel.isRefreshing,
                onRefresh: { viewModel.refreshNow() },
                onCopyDetails: { viewModel.copyDiagnostics() },
                onQuit: { NSApplication.shared.terminate(nil) }
            )
        }
        .frame(width: 320)
    }

    static func openPreferencesLegacy() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let snap = viewModel.state.snapshot {
            VStack(spacing: 0) {
                ForEach(Array(LimitKey.allCases.enumerated()), id: \.element) { index, key in
                    LimitRow(label: key.label, limit: snap.limit(key), thresholds: thresholds)
                    if index < LimitKey.allCases.count - 1 {
                        Divider()
                    }
                }
            }
        } else {
            HStack {
                ProgressView().controlSize(.small)
                Text("Loading…").foregroundStyle(.secondary)
                Spacer()
            }
            .padding(12)
        }
    }

    private var thresholds: (low: Double, high: Double) {
        (settings.lowThreshold, settings.highThreshold)
    }
}

private struct ErrorBanner: View {
    let error: UsageError
    let onReauth: () -> Void
    let onCopyDetails: () -> Void

    @State private var copiedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(error.displayMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer()
                Button(copiedAt == nil ? "Copy details" : "Copied ✓") {
                    onCopyDetails()
                    copiedAt = Date()
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        if let copiedAt, Date().timeIntervalSince(copiedAt) >= 1.4 {
                            self.copiedAt = nil
                        }
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .help("Copy the recent API exchanges and error state to the clipboard.")

                if error.isRecoverableByReauth {
                    Button("Re-authenticate", action: onReauth)
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .help("Clear the cached access token and re-read Claude Code's keychain entry.")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct LimitRow: View {
    let label: String
    let limit: UsageLimit?
    let thresholds: (low: Double, high: Double)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                Text(percentText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(color)
            }
            ProgressView(value: barValue)
                .tint(color)
            Text(resetText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var percentText: String {
        if let l = limit { return PercentageFormatter.short(l.utilization) }
        return "—"
    }

    private var barValue: Double {
        if let l = limit { return min(1, max(0, l.utilization / 100)) }
        return 0
    }

    private var color: Color {
        guard let l = limit else { return .secondary }
        if l.utilization >= thresholds.high { return .red }
        if l.utilization >= thresholds.low { return .orange }
        return .accentColor
    }

    private var resetText: String {
        guard let l = limit else { return "no usage" }
        guard let resetsAt = l.resetsAt else { return "no upcoming reset" }
        return "resets in \(DurationFormatter.compact(until: resetsAt))"
    }
}

private struct FooterBar: View {
    let lastUpdatedAt: Date?
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onCopyDetails: () -> Void
    let onQuit: () -> Void

    @State private var copiedAt: Date?

    var body: some View {
        HStack(spacing: 8) {
            if let updated = lastUpdatedAt {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onRefresh) {
                if isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .help("Refresh")
            Button {
                onCopyDetails()
                copiedAt = Date()
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    if let copiedAt, Date().timeIntervalSince(copiedAt) >= 1.4 {
                        self.copiedAt = nil
                    }
                }
            } label: {
                Image(systemName: copiedAt == nil ? "doc.on.clipboard" : "checkmark")
            }
            .buttonStyle(.borderless)
            .help("Copy recent API diagnostics to the clipboard.")
            preferencesButton
            Button("Quit", action: onQuit)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var preferencesButton: some View {
        if #available(macOS 14.0, *) {
            ModernSettingsButton()
        } else {
            Button("Preferences…") { PopoverView.openPreferencesLegacy() }
                .buttonStyle(.borderless)
        }
    }
}

// LSUIElement apps can't bring their windows above other apps without first
// being promoted to a regular activation policy. Promote on open, demote when
// the Settings window closes — costs a brief Dock icon while it's open.
@available(macOS 14.0, *)
private struct ModernSettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Preferences…") {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            openSettings()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard let window = NSApp.windows.first(where: {
                    $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window"
                }) else {
                    NSApp.setActivationPolicy(.accessory)
                    return
                }
                window.makeKeyAndOrderFront(nil)

                var observer: NSObjectProtocol?
                observer = NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { _ in
                    NSApp.setActivationPolicy(.accessory)
                    if let observer { NotificationCenter.default.removeObserver(observer) }
                }
            }
        }
        .buttonStyle(.borderless)
    }
}

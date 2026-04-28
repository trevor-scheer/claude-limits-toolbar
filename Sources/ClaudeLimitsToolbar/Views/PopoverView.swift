import SwiftUI
import AppKit

struct PopoverView: View {
    @EnvironmentObject var viewModel: UsageViewModel
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = viewModel.state.error {
                ErrorBanner(error: error)
                Divider()
            }

            content

            Divider()
            FooterBar(
                lastUpdatedAt: viewModel.lastUpdatedAt,
                isRefreshing: viewModel.isRefreshing,
                onRefresh: { viewModel.refreshNow() },
                onPreferences: { Self.openPreferences() },
                onQuit: { NSApplication.shared.terminate(nil) }
            )
        }
        .frame(width: 320)
    }

    static func openPreferences() {
        NSApp.activate(ignoringOtherApps: true)
        // The SwiftUI `Settings` scene installs an action handler for this selector on macOS 13+.
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(error.displayMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
        if let l = limit {
            return "resets in \(DurationFormatter.compact(until: l.resetsAt))"
        }
        return "no usage"
    }
}

private struct FooterBar: View {
    let lastUpdatedAt: Date?
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onPreferences: () -> Void
    let onQuit: () -> Void

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
            Button("Preferences…", action: onPreferences)
                .buttonStyle(.borderless)
            Button("Quit", action: onQuit)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

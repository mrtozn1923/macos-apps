import SwiftUI

struct MonitorRow: View {
    let monitor: Monitor
    let status: MonitorStatus
    let effectiveState: MonitorState
    let offline: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(StateStyle.color(offline ? .unknown : effectiveState))
                .frame(width: 9, height: 9)
                .overlay {
                    if effectiveState == .down && !offline {
                        Circle().stroke(Color.red.opacity(0.4), lineWidth: 4)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(monitor.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1)
                    .truncationMode(effectiveState == .up ? .middle : .tail)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                Text(effectiveState == .down ? "—" : DurationFormatter.latency(status.lastResult?.latencyMs))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                Text(DurationFormatter.percent(status.uptime24h))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Sparkline(values: status.sparkline)
                .frame(width: 56, height: 22)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(minHeight: 46)
        .opacity(effectiveState == .paused ? 0.55 : 1)
    }

    private var subtitle: String {
        switch effectiveState {
        case .paused:
            return L("Paused")
        case .down:
            let since: String = status.since.map { " · " + DurationFormatter.short(Date().timeIntervalSince($0)) } ?? ""
            return (status.reason ?? L("Down")) + since
        case .warning:
            return status.reason ?? monitor.target
        case .unknown:
            return offline ? L("Waiting for network") : L("Checking…")
        case .up:
            return monitor.target
        }
    }

    private var subtitleColor: Color {
        switch effectiveState {
        case .down: return .red
        case .warning: return .orange
        default: return .secondary
        }
    }
}

enum StateStyle {
    static func color(_ state: MonitorState) -> Color {
        switch state {
        case .up: return .green
        case .warning: return .yellow
        case .down: return .red
        case .paused, .unknown: return .gray
        }
    }
}

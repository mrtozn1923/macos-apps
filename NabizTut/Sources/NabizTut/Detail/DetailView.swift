import SwiftUI

struct DetailActions {
    let checkNow: () -> Void
    let edit: () -> Void
    let setPaused: (Bool) -> Void
}

enum ChartRange: String, CaseIterable, Identifiable {
    case day, week, month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return L("24 hours")
        case .week: return L("7 days")
        case .month: return L("30 days")
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .day: return 86_400
        case .week: return 7 * 86_400
        case .month: return 30 * 86_400
        }
    }
}

struct ChartPoint: Identifiable {
    let id: Int
    let date: Date
    let latency: Int?
    let failed: Bool
}

struct DetailData {
    var points: [ChartPoint] = []
    var incidents: [Incident] = []
    var uptime: Double?
    var average: Int?
    var p95: Int?

    static func load(monitorID: UUID, range: ChartRange, history: HistoryRepository) -> DetailData {
        let since: Date = Date().addingTimeInterval(-range.seconds)
        var data: DetailData = DetailData()
        data.uptime = history.uptime(monitorID: monitorID, since: since)
        data.incidents = history.incidents(monitorID: monitorID, since: since)

        if range == .day {
            let samples: [Sample] = history.samples(monitorID: monitorID, since: since)
            data.points = samples.enumerated().map { ChartPoint(id: $0.offset, date: $0.element.date,
                                                                 latency: $0.element.ok ? $0.element.latencyMs : nil,
                                                                 failed: !$0.element.ok) }
            let latencies: [Int] = samples.filter(\.ok).compactMap(\.latencyMs).sorted()
            data.average = latencies.isEmpty ? nil : latencies.reduce(0, +) / latencies.count
            data.p95 = latencies.isEmpty ? nil : latencies[min(latencies.count - 1, Int(Double(latencies.count) * 0.95))]
        } else {
            let hours: [HourlySample] = history.hourlySeries(monitorID: monitorID, since: since)
            data.points = hours.enumerated().map { ChartPoint(id: $0.offset, date: $0.element.hour,
                                                               latency: $0.element.avgMs, failed: $0.element.failed > 0) }
            // Weighted by number of successful checks in each hour.
            var weighted: Int = 0
            var count: Int = 0
            for hour in hours {
                guard let avg = hour.avgMs else { continue }
                let ok: Int = hour.total - hour.failed
                weighted += avg * ok
                count += ok
            }
            data.average = count > 0 ? weighted / count : nil
            let p95s: [Int] = hours.compactMap(\.p95Ms).sorted()
            data.p95 = p95s.isEmpty ? nil : p95s[min(p95s.count - 1, Int(Double(p95s.count) * 0.95))]
        }
        return data
    }
}

struct DetailView: View {
    let monitorID: UUID
    let state: AppState
    let history: HistoryRepository
    let actions: DetailActions

    @State private var range: ChartRange = .day
    @State private var data: DetailData = DetailData()

    private var monitor: Monitor? { state.monitors.first { $0.id == monitorID } }

    var body: some View {
        if let monitor {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header(monitor)
                    Picker("", selection: $range) {
                        ForEach(ChartRange.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 360)

                    LatencyChart(points: data.points, incidents: data.incidents, range: range)
                        .frame(height: 240)

                    summary
                    IncidentList(incidents: data.incidents)
                }
                .padding(22)
            }
            .task(id: "\(range.rawValue)-\(state.historyRevision)") {
                let id: UUID = monitorID
                let selected: ChartRange = range
                let repository: HistoryRepository = history
                data = await Task.detached { DetailData.load(monitorID: id, range: selected, history: repository) }.value
            }
        } else {
            Text(L("This monitor was deleted.")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ monitor: Monitor) -> some View {
        let status: MonitorStatus = state.status(for: monitor.id)
        let effective: MonitorState = state.offline ? .unknown : state.effectiveState(monitor)
        return HStack(alignment: .top, spacing: 12) {
            Circle().fill(StateStyle.color(effective)).frame(width: 14, height: 14).padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(monitor.displayName).font(.title2.weight(.semibold))
                Text("\(monitor.kind.title) · \(monitor.target)").font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                HStack(spacing: 14) {
                    Text(statusLine(effective, status)).foregroundStyle(effective == .down ? .red : .primary)
                    if let last = status.lastResult?.date {
                        Text(L("Last check %@", last.formatted(.relative(presentation: .named))))
                            .foregroundStyle(.secondary)
                    }
                    if let expiry = status.certExpiry {
                        Label(L("SSL until %@", expiry.formatted(date: .abbreviated, time: .omitted)), systemImage: "lock")
                            .foregroundStyle(expiry.timeIntervalSinceNow < Double(monitor.sslWarnDays) * 86_400 ? .orange : .secondary)
                    }
                }
                .font(.callout)
            }
            Spacer()
            HStack(spacing: 8) {
                Button(L("Check now"), systemImage: "arrow.clockwise", action: actions.checkNow).disabled(monitor.paused)
                Button(monitor.paused ? L("Resume") : L("Pause"), systemImage: monitor.paused ? "play" : "pause") {
                    actions.setPaused(!monitor.paused)
                }
                Button(L("Edit…"), systemImage: "pencil", action: actions.edit)
            }
            .labelStyle(.titleAndIcon)
            .controlSize(.small)
        }
    }

    private func statusLine(_ state: MonitorState, _ status: MonitorStatus) -> String {
        switch state {
        case .up: return L("Up")
        case .warning: return status.reason ?? L("Warning")
        case .down:
            let since: String = status.since.map { " · " + DurationFormatter.short(Date().timeIntervalSince($0)) } ?? ""
            return (status.reason ?? L("Down")) + since
        case .paused: return L("Paused")
        case .unknown: return self.state.offline ? L("Offline") : L("Checking…")
        }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            SummaryCard(title: L("Uptime"), value: DurationFormatter.percent(data.uptime))
            SummaryCard(title: L("Average"), value: DurationFormatter.latency(data.average))
            SummaryCard(title: "p95", value: DurationFormatter.latency(data.p95))
            SummaryCard(title: L("Outages"), value: "\(data.incidents.count)")
        }
    }
}

struct SummaryCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }
}

import Charts
import SwiftUI

struct LatencyChart: View {
    let points: [ChartPoint]
    let incidents: [Incident]
    let range: ChartRange

    @State private var selected: ChartPoint?

    /// Points with a latency, split into segments at failed checks so the line breaks during outages.
    private var segmented: [(point: ChartPoint, segment: Int)] {
        var segment: Int = 0
        var result: [(point: ChartPoint, segment: Int)] = []
        for point in points {
            if point.latency == nil {
                if result.last?.segment == segment { segment += 1 }
                continue
            }
            result.append((point, segment))
        }
        return result
    }

    var body: some View {
        if points.isEmpty {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.04))
                .overlay(Text(L("No data for this period yet")).foregroundStyle(.secondary))
        } else {
            chart
        }
    }

    private var chart: some View {
        let start: Date = Date().addingTimeInterval(-range.seconds)
        return Chart {
            ForEach(incidents) { incident in
                RectangleMark(xStart: .value("Start", max(incident.started, start)),
                              xEnd: .value("End", incident.ended ?? Date()))
                    .foregroundStyle(Color.red.opacity(0.15))
            }
            ForEach(segmented, id: \.point.id) { item in
                let point: ChartPoint = item.point
                AreaMark(x: .value("Time", point.date), y: .value("ms", point.latency ?? 0), series: .value("Segment", item.segment))
                    .foregroundStyle(LinearGradient(colors: [Color.accentColor.opacity(0.25), Color.accentColor.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", point.date), y: .value("ms", point.latency ?? 0), series: .value("Segment", item.segment))
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.6))
                    .interpolationMethod(.monotone)
            }
            ForEach(points.filter(\.failed)) { point in
                PointMark(x: .value("Time", point.date), y: .value("ms", 0))
                    .foregroundStyle(.red)
                    .symbolSize(18)
            }
            if let selected {
                RuleMark(x: .value("Time", selected.date))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selected.date.formatted(range == .day ? .dateTime.hour().minute() : .dateTime.day().month().hour()))
                                .font(.caption2).foregroundStyle(.secondary)
                            Text(selected.failed && selected.latency == nil ? L("Failed") : DurationFormatter.latency(selected.latency))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(selected.failed ? .red : .primary)
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.regularMaterial))
                    }
            }
        }
        .chartXScale(domain: start...Date())
        .chartYAxisLabel("ms")
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let frame = proxy.plotFrame else { return }
                            let x: CGFloat = location.x - geometry[frame].origin.x
                            guard let date: Date = proxy.value(atX: x) else { return }
                            selected = points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
                        case .ended:
                            selected = nil
                        }
                    }
            }
        }
    }
}

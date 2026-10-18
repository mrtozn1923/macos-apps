import SwiftUI

/// Tiny latency line for the last hour. Failed checks are drawn as red ticks.
struct Sparkline: View {
    let values: [Int?]

    var body: some View {
        Canvas { context, size in
            guard values.count >= 2 else {
                var baseline: Path = Path()
                baseline.move(to: CGPoint(x: 0, y: size.height - 1))
                baseline.addLine(to: CGPoint(x: size.width, y: size.height - 1))
                context.stroke(baseline, with: .color(.secondary.opacity(0.3)), lineWidth: 1)
                return
            }
            let latencies: [Int] = values.compactMap { $0 }
            let maxValue: Double = Double(max(latencies.max() ?? 1, 1))
            let step: CGFloat = size.width / CGFloat(values.count - 1)
            var path: Path = Path()
            var started: Bool = false
            for (index, value) in values.enumerated() {
                let x: CGFloat = CGFloat(index) * step
                guard let value else {
                    var tick: Path = Path()
                    tick.move(to: CGPoint(x: x, y: 0))
                    tick.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(tick, with: .color(.red.opacity(0.8)), lineWidth: 1.5)
                    started = false
                    continue
                }
                let y: CGFloat = size.height - 2 - CGFloat(Double(value) / maxValue) * (size.height - 4)
                if started { path.addLine(to: CGPoint(x: x, y: y)) } else { path.move(to: CGPoint(x: x, y: y)); started = true }
            }
            context.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

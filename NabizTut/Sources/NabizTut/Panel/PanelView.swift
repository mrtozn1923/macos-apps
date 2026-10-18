import SwiftUI

struct PanelActions {
    let openDetail: (UUID) -> Void
    let openSettings: () -> Void
    let refreshAll: () -> Void
    let finishEditing: () -> Void
}

struct PanelView: View {
    let state: AppState
    let actions: PanelActions

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            if state.monitors.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(state.sortedMonitors) { monitor in
                            MonitorRow(monitor: monitor, status: state.status(for: monitor.id),
                                       effectiveState: state.effectiveState(monitor), offline: state.offline)
                                .contentShape(Rectangle())
                                .onTapGesture { if !state.panelEditing { actions.openDetail(monitor.id) } }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.never)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(VisualEffectBackground().opacity(state.panelOpacity))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(state.panelEditing ? Color.accentColor : Color.primary.opacity(0.12),
                              style: StrokeStyle(lineWidth: state.panelEditing ? 2 : 1, dash: state.panelEditing ? [6, 4] : []))
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(overallColor).frame(width: 9, height: 9)
            Text(headerText).font(.system(size: 13, weight: .semibold))
            Spacer()
            if state.panelEditing {
                Text(L("Drag the edges to resize")).font(.caption2).foregroundStyle(.secondary)
                Button(L("Done"), action: actions.finishEditing)
                    .buttonStyle(.borderedProminent).controlSize(.small)
            } else {
                Button(action: actions.refreshAll) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help(L("Check now"))
                Button(action: actions.openSettings) { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless).help(L("Settings…"))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        // The header is the grab handle: dragging it moves the panel.
        .background(WindowDragArea())
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg").font(.title2).foregroundStyle(.secondary)
            Text(L("No monitors yet")).font(.callout.weight(.medium))
            Button(L("Add a site…"), action: actions.openSettings).controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var headerText: String {
        switch state.overall {
        case .offline: return L("Offline")
        case .empty: return state.monitors.isEmpty ? "NabızTut" : L("All monitors paused")
        default: return L("%ld/%ld up", state.upCount, state.activeMonitors.count)
        }
    }

    private var overallColor: Color {
        switch state.overall {
        case .allUp: return .green
        case .warning: return .yellow
        case .down: return .red
        case .offline, .empty: return .gray
        }
    }
}

/// Moves the hosting window when dragged. SwiftUI content swallows mouse-downs, so window background dragging
/// does not work on its own; this view starts the system window drag explicitly.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        // The panel is never the active window; the first click must already start the drag.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
    }

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view: NSVisualEffectView = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

import SwiftUI

struct MonitorListView: View {
    let controller: AppController
    @Bindable var navigation: SettingsNavigation

    private var state: AppState { controller.state }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: Binding(get: { navigation.newDraft == nil ? navigation.selectedID : nil },
                                        set: { id in
                                            navigation.newDraft = nil
                                            navigation.selectedID = id
                                        })) {
                    if navigation.newDraft != nil {
                        Label(L("New site"), systemImage: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    ForEach(state.monitors) { monitor in
                        HStack(spacing: 8) {
                            Circle().fill(StateStyle.color(state.effectiveState(monitor))).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(monitor.displayName).lineLimit(1)
                                Text(monitor.target).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                        }
                        .tag(monitor.id)
                    }
                    .onMove { controller.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.sidebar)

                HStack(spacing: 0) {
                    Button { navigation.newDraft = Monitor() } label: { Image(systemName: "plus").frame(width: 24, height: 20) }
                        .help(L("Add site"))
                    Button {
                        if let id = navigation.selectedID, var copy = state.monitors.first(where: { $0.id == id }) {
                            copy.id = UUID()
                            copy.name = L("%@ copy", copy.displayName)
                            for index in copy.headers.indices { copy.headers[index].id = UUID() }
                            navigation.newDraft = copy
                        }
                    } label: { Image(systemName: "plus.square.on.square").frame(width: 24, height: 20) }
                        .help(L("Duplicate"))
                        .disabled(navigation.selectedID == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(width: 240)

            Divider()

            Group {
                if let draft = navigation.newDraft {
                    MonitorFormView(controller: controller, original: draft, isNew: true) { saved in
                        navigation.newDraft = nil
                        navigation.selectedID = saved?.id ?? navigation.selectedID
                    }
                    .id(draft.id)
                } else if let id = navigation.selectedID, let monitor = state.monitors.first(where: { $0.id == id }) {
                    MonitorFormView(controller: controller, original: monitor, isNew: false) { saved in
                        if saved == nil { navigation.selectedID = state.monitors.first?.id }
                    }
                    .id(monitor.id)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "waveform.path.ecg").font(.largeTitle).foregroundStyle(.secondary)
                        Text(L("Add a website, API or server to start monitoring."))
                            .foregroundStyle(.secondary)
                        Button(L("Add site…")) { navigation.newDraft = Monitor() }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

import SwiftUI

/// Edits a copy of a monitor; nothing changes until Save.
struct MonitorFormView: View {
    let controller: AppController
    let original: Monitor
    let isNew: Bool
    /// Called after save (with the saved monitor), cancel of a new draft or delete (nil).
    let onFinish: (Monitor?) -> Void

    @State private var draft: Monitor
    @State private var testResult: CheckResult?
    @State private var testing: Bool = false
    @State private var confirmDelete: Bool = false

    init(controller: AppController, original: Monitor, isNew: Bool, onFinish: @escaping (Monitor?) -> Void) {
        self.controller = controller
        self.original = original
        self.isNew = isNew
        self.onFinish = onFinish
        _draft = State(initialValue: original)
    }

    private var hasChanges: Bool { isNew || draft != original }
    private var bodyAllowed: Bool { ![.get, .head].contains(draft.method) }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker(L("Type"), selection: $draft.kind) {
                        ForEach(MonitorKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    TextField(L("Name"), text: $draft.name, prompt: Text(L("Optional, e.g. Shop API")))
                    switch draft.kind {
                    case .http:
                        TextField(L("Address"), text: $draft.url, prompt: Text("https://example.com/health"))
                    case .ping:
                        TextField(L("Host"), text: $draft.host, prompt: Text("example.com / 192.168.1.10"))
                    case .tcp:
                        TextField(L("Host"), text: $draft.host, prompt: Text("db.example.com"))
                        TextField(L("Port"), value: $draft.port, format: .number.grouping(.never))
                    }
                    Picker(L("Check every"), selection: $draft.intervalMinutes) {
                        ForEach(Monitor.intervals, id: \.self) { Text(L("%ld min", $0)).tag($0) }
                    }
                    Stepper(value: $draft.timeoutSeconds, in: 1...60) {
                        LabeledContent(L("Timeout"), value: L("%ld s", draft.timeoutSeconds))
                    }
                    Toggle(L("Notify when it goes down or recovers"), isOn: $draft.notify)
                    Toggle(L("Paused"), isOn: $draft.paused)
                }

                if draft.kind == .http {
                    Section(L("HTTP")) {
                        Picker(L("Method"), selection: $draft.method) {
                            ForEach(HTTPMethod.allCases) { Text($0.rawValue).tag($0) }
                        }
                        TextField(L("Expected status codes"), text: $draft.expectedStatus, prompt: Text("200-299, 301"))
                        Toggle(L("Follow redirects"), isOn: $draft.followRedirects)
                        HStack {
                            Picker(L("Response body"), selection: $draft.keywordMode) {
                                ForEach(KeywordMode.allCases) { Text($0.title).tag($0) }
                            }
                            .fixedSize()
                            TextField("", text: $draft.keyword, prompt: Text(L("keyword (optional)")))
                                .labelsHidden()
                        }
                        Stepper(value: $draft.sslWarnDays, in: 1...90) {
                            LabeledContent(L("Warn before SSL expiry"), value: L("%ld days", draft.sslWarnDays))
                        }
                    }
                    Section(L("Headers")) {
                        ForEach($draft.headers) { $header in
                            HStack {
                                TextField(L("Name"), text: $header.name, prompt: Text("Authorization")).frame(maxWidth: 160)
                                if header.secret {
                                    SecureField(L("Value"), text: $header.value)
                                } else {
                                    TextField(L("Value"), text: $header.value)
                                }
                                Toggle(L("Secret"), isOn: $header.secret).toggleStyle(.checkbox)
                                    .help(L("Stored in the macOS Keychain instead of the settings file"))
                                Button { draft.headers.removeAll { $0.id == header.id } } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.borderless)
                            }
                            .labelsHidden()
                        }
                        Button(L("Add header"), systemImage: "plus") { draft.headers.append(HeaderField()) }
                            .buttonStyle(.borderless)
                    }
                    if bodyAllowed {
                        Section(L("Request body")) {
                            TextEditor(text: $draft.body)
                                .font(.system(.body, design: .monospaced))
                                .frame(minHeight: 70)
                        }
                    }
                }

                if let testResult {
                    Section(L("Test result")) {
                        TestResultView(result: testResult)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if !isNew {
                    Button(L("Delete…"), role: .destructive) { confirmDelete = true }
                }
                Button {
                    runTest()
                } label: {
                    if testing { ProgressView().controlSize(.small) } else { Text(L("Test")) }
                }
                .disabled(testing || draft.validationError != nil)
                Spacer()
                if let error = draft.validationError, hasChanges {
                    Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
                }
                Button(L("Cancel")) {
                    if isNew { onFinish(nil) } else { draft = original; testResult = nil }
                }
                .disabled(!hasChanges)
                .keyboardShortcut(.cancelAction)
                Button(L("Save")) {
                    var cleaned: Monitor = draft
                    cleaned.url = cleaned.url.trimmingCharacters(in: .whitespaces)
                    cleaned.host = cleaned.host.trimmingCharacters(in: .whitespaces)
                    cleaned.headers.removeAll { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }
                    controller.save(cleaned)
                    onFinish(cleaned)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!hasChanges || draft.validationError != nil)
            }
            .padding(12)
        }
        .confirmationDialog(L("Delete %@?", original.displayName), isPresented: $confirmDelete) {
            Button(L("Delete monitor and its history"), role: .destructive) {
                DetailWindowController.closeAll(for: original.id)
                controller.delete(original.id)
                onFinish(nil)
            }
        }
    }

    private func runTest() {
        testing = true
        testResult = nil
        let monitor: Monitor = draft
        Task {
            let result: CheckResult = await controller.test(monitor)
            testResult = result
            testing = false
        }
    }
}

struct TestResultView: View {
    let result: CheckResult

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: result.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(result.ok ? .green : .red)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(result.ok ? L("Up") : (result.error ?? L("Down"))).font(.callout.weight(.medium))
                HStack(spacing: 12) {
                    if let code = result.statusCode { Text("HTTP \(code)") }
                    if let latency = result.latencyMs { Text(DurationFormatter.latency(latency)) }
                    if let expiry = result.certExpiry {
                        Text(L("SSL until %@", expiry.formatted(date: .abbreviated, time: .omitted)))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

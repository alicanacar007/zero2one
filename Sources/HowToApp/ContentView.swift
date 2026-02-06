import SwiftUI
import AppKit

struct FloatingWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            if let screen = window.screen ?? NSScreen.main {
                let size = NSSize(width: 900, height: 500)
                let origin = NSPoint(
                    x: screen.visibleFrame.maxX - size.width,
                    y: screen.visibleFrame.minY
                )
                let frame = NSRect(origin: origin, size: size)
                window.setFrame(frame, display: true)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct ChatMessageView: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .assistant {
                VStack(alignment: .leading, spacing: 8) {
                    if !message.text.isEmpty {
                        Text(message.text)
                    }
                    if let data = message.imageData,
                       let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 200, maxHeight: 200)
                    }
                }
                .padding(12)
                .background(Color.accentColor.opacity(0.08))
                .cornerRadius(12)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 8) {
                    if !message.text.isEmpty {
                        Text(message.text)
                    }
                    if let data = message.imageData,
                       let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 200, maxHeight: 200)
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlAccentColor.withAlphaComponent(0.1)))
                .cornerRadius(12)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var logStore: LogStore
    @State private var chatInput: String = ""
    @State private var showLogs: Bool = false

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Video")
                    .font(.title3)
                    .fontWeight(.semibold)
                OdysseyStreamView(bridge: OdysseyBridge.shared)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 6)
            }
            .padding(16)
            .frame(width: 360)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Workflow")
                    .font(.title3)
                    .fontWeight(.semibold)
                if appState.workflowSteps.isEmpty {
                    Text("No workflow yet")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(appState.workflowSteps) { step in
                                Button(action: {
                                    appState.handleWorkflowStepTap(step)
                                }) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(step.title)
                                            .font(.subheadline)
                                            .bold()
                                        Text(step.detail)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(16)
            .frame(width: 300)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("AI Chat")
                    .font(.title3)
                    .fontWeight(.semibold)
                Picker("Provider", selection: $appState.chatProvider) {
                    ForEach(AppState.ChatProvider.allCases) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(appState.chatMessages) { message in
                                ChatMessageView(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(.vertical, 4)
                        .onChange(of: appState.chatMessages.count) { _ in
                            if let last = appState.chatMessages.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
                HStack(spacing: 8) {
                    Button(action: {
                        appState.addScreenshotMessage()
                    }) {
                        Text("Screenshot")
                    }
                    TextField("Ask anything about this workflow", text: $chatInput)
                        .textFieldStyle(.roundedBorder)
                    Button(action: {
                        let text = chatInput
                        chatInput = ""
                        appState.sendChat(message: text)
                    }) {
                        Text("Send")
                    }
                    .disabled(chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.top, 4)
            }
            .padding(16)
            .frame(minWidth: 320)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(FloatingWindowAccessor())
        .overlay(
            VStack {
                if appState.isProcessing {
                    ProgressView()
                }
                if let status = appState.statusText {
                    Text(status)
                        .font(.caption)
                        .padding(.top, 2)
                }
            }
            .padding(6),
            alignment: .bottomLeading
        )
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack {
                    TextField(
                        "Describe what you want to learn",
                        text: $appState.currentPrompt
                    )
                    .textFieldStyle(.roundedBorder)
                    Button(action: {
                        appState.handleUserPrompt()
                    }) {
                        Text("Generate")
                    }
                    .disabled(appState.isProcessing)
                    Button(action: {
                        showLogs = true
                    }) {
                        Text("Logs")
                    }
                }
                .frame(width: 500)
            }
        }
        .sheet(isPresented: $showLogs) {
            LogsView()
                .environmentObject(logStore)
                .frame(minWidth: 720, minHeight: 520)
        }
    }
}

struct LogsView: View {
    @EnvironmentObject var logStore: LogStore
    @State private var showErrorsOnly: Bool = true

    private var filteredEntries: [LogEntry] {
        if showErrorsOnly {
            return logStore.entries.filter { $0.level == .error }
        }
        return logStore.entries
    }

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Logs")
                    .font(.title2)
                    .fontWeight(.semibold)
                Toggle("Errors only", isOn: $showErrorsOnly)
                    .toggleStyle(.switch)
                Spacer()
                Button("Copy Errors") {
                    logStore.copyErrorsToPasteboard()
                }
                Button("Copy All") {
                    logStore.copyAllToPasteboard()
                }
                Button("Clear") {
                    logStore.clear()
                }
            }
            .padding(.bottom, 4)

            if filteredEntries.isEmpty {
                Text(showErrorsOnly ? "No errors yet." : "No logs yet.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                List(filteredEntries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(entry.service)
                                .font(.headline)
                            Text(entry.level.rawValue.uppercased())
                                .font(.caption)
                                .padding(.vertical, 2)
                                .padding(.horizontal, 6)
                                .background(entry.level == .error ? Color.red.opacity(0.15) : Color.blue.opacity(0.15))
                                .cornerRadius(6)
                            if let status = entry.statusCode {
                                Text("\(status)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(dateFormatter.string(from: entry.timestamp))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if let url = entry.url {
                            Text(url)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text(entry.message)
                            .font(.body)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
    }
}

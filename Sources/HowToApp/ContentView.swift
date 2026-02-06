import SwiftUI
import WebKit
import AppKit

struct VideoWebView: NSViewRepresentable {
    let url: URL?

    func makeNSView(context: Context) -> WKWebView {
        WKWebView()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard let url else {
            webView.loadHTMLString("", baseURL: nil)
            return
        }
        if webView.url != url {
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }
}

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
    @State private var chatInput: String = ""

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Video")
                    .font(.title3)
                    .fontWeight(.semibold)
                VideoWebView(url: appState.videoURL)
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
                }
                .frame(width: 500)
            }
        }
    }
}

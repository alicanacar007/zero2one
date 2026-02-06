import Foundation
import WebKit

enum OdysseyBridgeError: LocalizedError {
    case webViewNotReady
    case invalidResponse
    case javascriptError(message: String)

    var errorDescription: String? {
        switch self {
        case .webViewNotReady:
            return "Odyssey view not ready."
        case .invalidResponse:
            return "Invalid response from Odyssey view."
        case let .javascriptError(message):
            return "Odyssey JavaScript error: \(message)"
        }
    }
}

@MainActor
final class OdysseyBridge: ObservableObject {
    static let shared = OdysseyBridge()

    private weak var webView: WKWebView?
    private let logStore: LogStore

    private let apiKey: String
    private let sdkURL: String
    private let sdkMode: String
    private let sdkGlobal: String

    init(logStore: LogStore = .shared) {
        self.logStore = logStore
        let env = OdysseyBridge.loadEnvFromFile()
        let processEnv = ProcessInfo.processInfo.environment
        self.apiKey = processEnv["ODYSSEY_API_KEY"] ?? env.apiKey ?? ""
        self.sdkURL = processEnv["ODYSSEY_SDK_URL"] ?? env.sdkURL ?? "https://cdn.jsdelivr.net/npm/@odysseyml/odyssey@latest/dist/index.umd.js"
        self.sdkMode = processEnv["ODYSSEY_SDK_MODE"] ?? env.sdkMode ?? "auto"
        self.sdkGlobal = processEnv["ODYSSEY_SDK_GLOBAL"] ?? env.sdkGlobal ?? "Odyssey"
    }

    func attach(webView: WKWebView) {
        self.webView = webView
        loadHTML(in: webView)
    }

    func startStream(prompt: String, screenshotPNGData: Data?) async throws {
        let payload = buildPayload(prompt: prompt, screenshotPNGData: screenshotPNGData)
        _ = try await callJS(function: "startStream", payload: payload)
    }

    func interact(prompt: String, screenshotPNGData: Data?) async throws {
        let payload = buildPayload(prompt: prompt, screenshotPNGData: screenshotPNGData)
        _ = try await callJS(function: "interact", payload: payload)
    }

    func endStream() async throws {
        _ = try await callJS(function: "endStream", payload: nil)
    }

    private func buildPayload(prompt: String, screenshotPNGData: Data?) -> [String: Any] {
        var payload: [String: Any] = [
            "prompt": prompt
        ]
        if let screenshotPNGData {
            let base64 = screenshotPNGData.base64EncodedString()
            let dataURL = "data:image/png;base64,\(base64)"
            payload["screenshotDataUrl"] = dataURL
            Task { @MainActor in
                logStore.log(.info, service: "Odyssey", message: "Attached screenshot to request")
            }
        }
        return payload
    }

    func handleEvent(_ payload: [String: Any]) {
        if let level = payload["level"] as? String,
           let message = payload["message"] as? String {
            let statusCode = payload["statusCode"] as? Int
            let urlString = payload["url"] as? String
            let url = urlString.flatMap(URL.init(string:))
            if level.lowercased() == "error" {
                logStore.log(.error, service: "Odyssey", message: message, url: url, statusCode: statusCode)
            } else {
                logStore.log(.info, service: "Odyssey", message: message, url: url, statusCode: statusCode)
            }
        }
    }

    private func callJS(function: String, payload: [String: Any]?) async throws -> Any? {
        guard let webView else {
            throw OdysseyBridgeError.webViewNotReady
        }
        let payloadString: String
        if let payload {
            let data = try JSONSerialization.data(withJSONObject: payload)
            payloadString = String(data: data, encoding: .utf8) ?? "{}"
        } else {
            payloadString = "null"
        }
        let script = """
        (() => {
          try {
            const fn = window.odysseyBridge.\(function);
            if (typeof fn !== 'function') {
              window.odysseyBridge._reportError(new Error('Odyssey bridge not ready.'));
              return "error";
            }
            const promise = fn(\(payloadString));
            if (promise && typeof promise.catch === 'function') {
              promise.catch(err => window.odysseyBridge._reportError(err));
            }
            return "ok";
          } catch (err) {
            window.odysseyBridge._reportError(err);
            return "error";
          }
        })()
        """
        return try await evaluate(script: script, in: webView)
    }

    private func evaluate(script: String, in webView: WKWebView) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    private func loadHTML(in webView: WKWebView) {
        let html = """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <style>
            html, body { margin:0; padding:0; width:100%; height:100%; background:#0b0b0c; color:#fff; }
            #video { width:100%; height:100%; object-fit:cover; background:#000; }
            #status { position:absolute; top:12px; left:12px; font:12px system-ui; color:#cbd5f5; }
          </style>
        </head>
        <body>
          <div id="status">Odyssey loading...</div>
          <video id="video" autoplay muted playsinline></video>
          <script>
            const sdkUrl = "\(sdkURL)";
            const sdkMode = "\(sdkMode)";
            const sdkGlobal = "\(sdkGlobal)";
            const apiKey = "\(apiKey)";
            const statusEl = document.getElementById('status');
            const videoEl = document.getElementById('video');
            let client = null;

            function post(level, message, extra = {}) {
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.odysseyEvent) {
                window.webkit.messageHandlers.odysseyEvent.postMessage({
                  level,
                  message,
                  ...extra
                });
              }
            }

            function setStatus(text) {
              statusEl.textContent = text;
            }

            async function loadSdk() {
              post('info', 'Loading Odyssey SDK', { url: sdkUrl, mode: sdkMode, global: sdkGlobal });
              const tryModule = async () => {
                const mod = await import(sdkUrl);
                return mod.default || mod.Odyssey || mod.odyssey || mod;
              };
              const tryScript = async () => {
                return await new Promise((resolve, reject) => {
                  const script = document.createElement('script');
                  script.src = sdkUrl;
                  script.onload = () => {
                    const globalClient = window[sdkGlobal] || window.Odyssey || window.odyssey;
                    if (!globalClient) {
                      reject(new Error('SDK loaded but global not found.'));
                      return;
                    }
                    resolve(globalClient);
                  };
                  script.onerror = () => reject(new Error('Failed to load Odyssey SDK from ' + sdkUrl));
                  document.head.appendChild(script);
                });
              };
              if (sdkMode === 'module') {
                return await tryModule();
              }
              if (sdkMode === 'script') {
                return await tryScript();
              }
              try {
                return await tryModule();
              } catch (moduleErr) {
                post('error', moduleErr?.message || 'Module load failed, trying script');
                return await tryScript();
              }
            }

            async function ensureClient() {
              if (client) return client;
              if (!apiKey) {
                throw new Error('Missing ODYSSEY_API_KEY.');
              }
              const sdk = await loadSdk();
              if (typeof sdk === 'function') {
                client = new sdk({ apiKey });
              } else if (sdk && typeof sdk.Odyssey === 'function') {
                client = new sdk.Odyssey({ apiKey });
              } else if (sdk && typeof sdk.connect === 'function') {
                client = sdk;
              } else {
                throw new Error('Unsupported Odyssey SDK shape.');
              }
              setStatus('Odyssey ready');
              post('info', 'SDK ready');
              return client;
            }

            window.odysseyBridge = {
              _reportError(err) {
                post('error', err?.message || 'Odyssey error');
                setStatus('Error');
              },
              async startStream(payload) {
                try {
                  setStatus('Starting stream...');
                  const sdk = await ensureClient();
                  const connectOptions = {
                    onConnected: () => post('info', 'Connected'),
                    onDisconnected: () => post('info', 'Disconnected'),
                    onStreamStarted: (streamId) => post('info', 'Stream started', { streamId }),
                    onStreamEnded: () => post('info', 'Stream ended'),
                    onInteractAcknowledged: (prompt) => post('info', 'Interact acknowledged', { prompt }),
                    onStreamError: (reason, message) => post('error', message || 'Stream error', { reason }),
                    onError: (error, fatal) => post('error', error?.message || 'SDK error', { fatal }),
                    onStatusChange: (status, message) => post('info', message || 'Status change', { status })
                  };
                  if (apiKey) {
                    connectOptions.apiKey = apiKey;
                  }
                  const media = await sdk.connect(connectOptions);
                  if (sdk.attachToVideo) {
                    sdk.attachToVideo(videoEl);
                  } else if (media) {
                    videoEl.srcObject = media;
                  }
                  const options = { ...(payload || {}) };
                  if (options.screenshotDataUrl) {
                    options.image = options.image || options.screenshotDataUrl;
                    options.image_url = options.image_url || options.screenshotDataUrl;
                    options.input = options.input || {};
                    options.input.image = options.input.image || options.screenshotDataUrl;
                    options.input.image_url = options.input.image_url || options.screenshotDataUrl;
                    delete options.screenshotDataUrl;
                  }
                  if (apiKey && !options.apiKey) {
                    options.apiKey = apiKey;
                  }
                  const streamId = await sdk.startStream(options);
                  post('info', 'Start stream request sent', { streamId });
                  setStatus('Streaming');
                  return streamId;
                } catch (err) {
                  post('error', err?.message || 'Start stream failed');
                  setStatus('Error');
                  throw err;
                }
              },
              async interact(payload) {
                try {
                  const sdk = await ensureClient();
                  const options = { ...(payload || {}) };
                  if (options.screenshotDataUrl) {
                    options.image = options.image || options.screenshotDataUrl;
                    options.image_url = options.image_url || options.screenshotDataUrl;
                    options.input = options.input || {};
                    options.input.image = options.input.image || options.screenshotDataUrl;
                    options.input.image_url = options.input.image_url || options.screenshotDataUrl;
                    delete options.screenshotDataUrl;
                  }
                  if (apiKey && !options.apiKey) {
                    options.apiKey = apiKey;
                  }
                  const streamId = await sdk.interact(options);
                  post('info', 'Interact sent', { streamId });
                  return streamId;
                } catch (err) {
                  post('error', err?.message || 'Interact failed');
                  throw err;
                }
              },
              async endStream() {
                try {
                  const sdk = await ensureClient();
                  await sdk.endStream();
                  post('info', 'Stream ended');
                  setStatus('Ended');
                } catch (err) {
                  post('error', err?.message || 'End stream failed');
                  throw err;
                }
              }
            };
          </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    private static func loadEnvFromFile() -> (
        apiKey: String?,
        sdkURL: String?,
        sdkMode: String?,
        sdkGlobal: String?
    ) {
        let fileURL = URL(fileURLWithPath: #file)
        let packageRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let envURL = packageRoot.appendingPathComponent(".env")
        guard let data = try? Data(contentsOf: envURL),
              let content = String(data: data, encoding: .utf8) else {
            return (nil, nil, nil, nil)
        }
        var apiKey: String?
        var sdkURL: String?
        var sdkMode: String?
        var sdkGlobal: String?
        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0]
            let value = parts[1]
            switch key {
            case "ODYSSEY_API_KEY": apiKey = value
            case "ODYSSEY_SDK_URL": sdkURL = value
            case "ODYSSEY_SDK_MODE": sdkMode = value
            case "ODYSSEY_SDK_GLOBAL": sdkGlobal = value
            default: break
            }
        }
        return (apiKey, sdkURL, sdkMode, sdkGlobal)
    }
}

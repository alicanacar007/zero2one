import SwiftUI
import WebKit

struct OdysseyStreamView: NSViewRepresentable {
    let bridge: OdysseyBridge

    func makeCoordinator() -> Coordinator {
        Coordinator(bridge: bridge)
    }

    func makeNSView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "odysseyEvent")
        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        bridge.attach(webView: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKScriptMessageHandler {
        private let bridge: OdysseyBridge

        init(bridge: OdysseyBridge) {
            self.bridge = bridge
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "odysseyEvent" else { return }
            if let payload = message.body as? [String: Any] {
                bridge.handleEvent(payload)
            }
        }
    }
}

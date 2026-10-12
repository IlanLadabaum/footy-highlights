import SwiftUI
import WebKit

#if os(macOS)
    /// Hosts the controller's web view.
    struct PlayerWebViewRepresentable: NSViewRepresentable {
        let controller: PlayerController

        func makeNSView(context: Context) -> WKWebView { controller.webView }
        func updateNSView(_ nsView: WKWebView, context: Context) {}
    }
#else
    struct PlayerWebViewRepresentable: UIViewRepresentable {
        let controller: PlayerController

        func makeUIView(context: Context) -> WKWebView { controller.webView }
        func updateUIView(_ uiView: WKWebView, context: Context) {}
    }
#endif

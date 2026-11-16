import SwiftUI
import WebKit

#if os(macOS)
    /// Hosts the controller's web view inside a container of its own, so the same web view can move between
    /// the player screen and the mini player window without reloading (whichever container shows it last owns it).
    struct PlayerWebViewRepresentable: NSViewRepresentable {
        let controller: PlayerController

        func makeNSView(context: Context) -> NSView {
            let container = NSView()
            adopt(into: container)
            return container
        }

        /// Never takes the web view back on update: a screen that's on its way out would steal it from the new one.
        func updateNSView(_ container: NSView, context: Context) {}

        private func adopt(into container: NSView) {
            let webView = controller.webView
            webView.removeFromSuperview()
            webView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(webView)
            NSLayoutConstraint.activate([
                webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                webView.topAnchor.constraint(equalTo: container.topAnchor),
                webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }
    }
#else
    struct PlayerWebViewRepresentable: UIViewRepresentable {
        let controller: PlayerController

        func makeUIView(context: Context) -> WKWebView { controller.webView }
        func updateUIView(_ uiView: WKWebView, context: Context) {}
    }
#endif

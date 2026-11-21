import SwiftUI
import WebKit

#if os(macOS)
    /// Hosts the controller's web view inside a container of its own, so the same web view can move between
    /// the player screen and the mini player window without reloading (whichever container shows it last owns it).
    struct PlayerWebViewRepresentable: NSViewRepresentable {
        let controller: PlayerController

        #if DEBUG
            /// `--fullscreen-test`: how many times a player view was (re)created.
            nonisolated(unsafe) static var makeCount = 0
        #endif

        func makeNSView(context: Context) -> NSView {
            #if DEBUG
                Self.makeCount += 1
            #endif
            let container = NSView()
            adopt(into: container)
            return container
        }

        /// Never takes the web view back on update: a screen that's on its way out would steal it from the new one.
        func updateNSView(_ container: NSView, context: Context) {}

        /// Sized with autoresizing (not constraints): WebKit's full screen moves the web view into its own window
        /// and back, and only follows the window's size when the view uses autoresizing. With constraints, full
        /// screen could show a black picture while the audio kept playing.
        private func adopt(into container: NSView) {
            let webView = controller.webView
            webView.removeFromSuperview()
            webView.translatesAutoresizingMaskIntoConstraints = true
            webView.frame = container.bounds
            webView.autoresizingMask = [.width, .height]
            container.addSubview(webView)
        }
    }
#else
    struct PlayerWebViewRepresentable: UIViewRepresentable {
        let controller: PlayerController

        func makeUIView(context: Context) -> WKWebView { controller.webView }
        func updateUIView(_ uiView: WKWebView, context: Context) {}
    }
#endif

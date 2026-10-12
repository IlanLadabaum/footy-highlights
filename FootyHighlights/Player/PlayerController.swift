import Foundation
import Observation
import WebKit

/// Drives one YouTube player inside a WKWebView and mirrors its state for the SwiftUI controls.
@MainActor
@Observable
final class PlayerController: NSObject {
    enum Phase: Equatable {
        case loading
        case playing
        case paused
        case buffering
        /// The video ended and the player was destroyed (nothing queued after it).
        case finished
        /// YouTube reported an error (code), or -1 when the API couldn't load.
        case failed(Int)
    }

    private(set) var phase: Phase = .loading
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var volume: Double = 100
    private(set) var isMuted = false
    /// Debug/test hook: every message from the page, in order.
    var onEvent: ((String) -> Void)?
    /// Called when a video ends. Return the next video ID to keep playing (queue), or nil to finish.
    var nextVideo: (() -> String?)?

    let webView: WKWebView
    private(set) var videoId: String
    private let muted: Bool

    init(videoId: String, muted: Bool = false) {
        self.videoId = videoId
        self.muted = muted
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .default()
        // YouTube's own full-screen button.
        configuration.preferences.isElementFullscreenEnabled = true
        webView = PlayerWebView(frame: .zero, configuration: configuration)
        super.init()
        configuration.userContentController.add(WeakMessageHandler(self), name: "player")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        #if os(macOS)
            webView.setValue(false, forKey: "drawsBackground")
        #endif
    }

    /// Creates the YouTube player. Called when the user pressed Play, so no thumbnail is ever shown first.
    func start() {
        phase = .loading
        currentTime = 0
        webView.loadHTMLString(PlayerPage.html(videoId: videoId, muted: muted), baseURL: PlayerPage.baseURL)
    }

    /// Switches to another video in the same player (keeps YouTube's full screen between queued videos).
    func load(videoId: String) {
        self.videoId = videoId
        currentTime = 0
        duration = 0
        if playerGone {
            start()
        } else {
            phase = .loading
            call("footy.load('\(videoId.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" })')")
        }
    }

    /// The YouTube player was destroyed (ended or failed), so the page must be reloaded.
    private var playerGone: Bool {
        if case .failed = phase { return true }
        return phase == .finished
    }

    func togglePlay() {
        switch phase {
        case .playing, .buffering: call("footy.pause()")
        case .paused, .loading: call("footy.play()")
        case .finished: start()
        case .failed: break
        }
    }

    func seek(by seconds: Double) { call("footy.seekBy(\(seconds))") }

    func seek(to seconds: Double) {
        currentTime = seconds
        call("footy.seekTo(\(max(0, seconds)))")
    }

    func setVolume(_ value: Double) {
        volume = value
        isMuted = false
        call("footy.setVolume(\(Int(value)))")
    }

    func toggleMute() {
        isMuted.toggle()
        call("footy.mute(\(isMuted))")
    }

    func stop() {
        call("footy.destroy()")
        webView.loadHTMLString("", baseURL: nil)
    }

    private func call(_ script: String) {
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    fileprivate func handle(_ body: Any) {
        guard let message = body as? [String: Any], let type = message["type"] as? String else { return }
        switch type {
        case "state":
            let state = message["state"] as? Int ?? -1
            onEvent?("state:\(state)")
            switch state {
            case 1: phase = .playing
            case 2: phase = .paused
            case 3: phase = .buffering
            default: break
            }
        case "time":
            currentTime = message["current"] as? Double ?? currentTime
            duration = message["duration"] as? Double ?? duration
            if let volume = message["volume"] as? Double { self.volume = volume }
            if let muted = message["muted"] as? Bool { isMuted = muted }
        case "ended":
            onEvent?("ended")
            if let next = nextVideo?() {
                load(videoId: next)
            } else {
                call("footy.destroy()")
                phase = .finished
            }
        case "error":
            let code = message["code"] as? Int ?? -1
            onEvent?("error:\(code)")
            phase = .failed(code)
        case "ready":
            onEvent?("ready")
        default:
            break
        }
    }
}

extension PlayerController: WKNavigationDelegate, WKUIDelegate {
    /// The page itself and YouTube's embed frame load in place; anything else (e.g. the YouTube logo) opens in the browser.
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? false
        if isMainFrame, navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            openExternally(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url { openExternally(url) }
        return nil
    }

    private func openExternally(_ url: URL) {
        #if os(macOS)
            NSWorkspace.shared.open(url)
        #endif
    }
}

/// The player's web view. YouTube's controls handle the keyboard (space, arrows, F, C for captions).
final class PlayerWebView: WKWebView {}

/// WKUserContentController retains its handlers; this breaks the cycle.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: PlayerController?

    init(_ target: PlayerController) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body
        MainActor.assumeIsolated { target?.handle(body) }
    }
}

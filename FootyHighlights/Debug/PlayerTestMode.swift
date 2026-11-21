#if DEBUG && os(macOS)
    import AppKit
    import FootyKit
    import SwiftUI

    /// Developer tool: `--player-test` plays one highlight per channel from the local store, muted, in an
    /// offscreen window, then seeks to the last seconds to check the player is destroyed on end.
    /// Prints channel, video ID and player states only (no titles, nothing visual).
    @MainActor
    enum PlayerTestMode {
        static var enabled: Bool { fullscreenTest || miniTest || CommandLine.arguments.contains("--player-test") }
        static var miniTest: Bool { CommandLine.arguments.contains("--mini-test") }
        static var fullscreenTest: Bool { CommandLine.arguments.contains("--fullscreen-test") }

        /// `--fullscreen-test`: no YouTube video (nothing to spoil): a blank black page in the player's web view,
        /// hosted the way the player screen hosts it, goes full screen and back. Prints the web view's size and
        /// window at each step, to catch a full-screen video that ends up with no size (black picture).
        static func testFullscreen() async {
            // A non-football video by default (Big Buck Bunny), so nothing can be spoiled.
            let videoId = SnapshotMode.argument("--video") ?? "aqz-KE-bpKQ"
            let controller = PlayerController(videoId: videoId, muted: true)
            let key = MatchKey.fixture(1)
            let session = PlaybackSession(testing: controller, key: key)
            let model = AppModel(store: try! Store(inMemory: true), defaults: UserDefaults(suiteName: "fs-test")!)  // swiftlint:disable:this force_try
            model.playback = session
            let window = NSWindow(
                contentRect: CGRect(x: 200, y: 200, width: 900, height: 600), styleMask: [.titled, .resizable],
                backing: .buffered, defer: false)
            window.collectionBehavior = [.fullScreenPrimary]
            window.contentView = NSHostingView(rootView: PlayerScreen(mode: session.mode).environment(model))
            window.orderFrontRegardless()
            controller.start()
            for _ in 0..<80 where !(controller.phase == .playing && controller.currentTime > 1) {
                try? await Task.sleep(for: .milliseconds(250))
            }
            func state(_ label: String) -> String {
                let view = controller.webView
                return "\(label): \(Int(view.frame.width))×\(Int(view.frame.height)) "
                    + "inPlayerWindow=\(view.window === window) visible=\(view.window?.isVisible == true) "
                    + "phase=\(controller.phase) makes=\(PlayerWebViewRepresentable.makeCount)"
            }
            var report = state("playing")
            _ = try? await controller.webView.evaluateJavaScript(
                "document.querySelector('iframe').requestFullscreen(); 1")
            try? await Task.sleep(for: .seconds(3))
            report += "; " + state("fullscreen")
            controller.togglePlay()
            try? await Task.sleep(for: .seconds(2))
            report += "; " + state("fs-paused")
            controller.togglePlay()
            try? await Task.sleep(for: .seconds(3))
            report += "; " + state("fs-resumed")
            _ = try? await controller.webView.evaluateJavaScript("document.exitFullscreen(); 1")
            try? await Task.sleep(for: .seconds(3))
            report += "; " + state("after")
            controller.stop()
            print("FULLSCREEN-TEST \(report)")
            exit(0)
        }

        static func run() {
            if fullscreenTest {
                Task { await testFullscreen() }
                return
            }
            let model = AppModel()
            Task {
                await model.refresh()
                if miniTest { await testMiniPlayer(model) } else { pickAndTest(model) }
            }
        }

        // swiftlint:disable function_body_length
        /// `--mini-test`: plays one highlight muted offscreen, moves it into the mini player and back, and checks
        /// it keeps playing without reloading, and that the T and I keys work. Doesn't touch watched flags or the
        /// saved mini player frame.
        static func testMiniPlayer(_ model: AppModel) async {
            guard
                let entry = model.library.competitions.flatMap(\.rounds).filter({ $0.layout == .withTable })
                    .flatMap(\.matches).first(where: \.isPlayable),
                let video = entry.video
            else { return finish("no playable video") }
            let store = try! Store(inMemory: true)  // swiftlint:disable:this force_try
            let testModel = AppModel(store: store, defaults: UserDefaults(suiteName: "mini-test")!)
            let controller = PlayerController(videoId: video.id, muted: true)
            let main = NSWindow(
                contentRect: CGRect(x: -5000, y: -5000, width: 640, height: 400), styleMask: [.borderless],
                backing: .buffered, defer: false)
            main.contentView = NSHostingView(rootView: PlayerWebViewRepresentable(controller: controller))
            main.orderFrontRegardless()
            controller.start()
            func waitPlaying() async -> Bool {
                for _ in 0..<80 {
                    try? await Task.sleep(for: .milliseconds(250))
                    if controller.phase == .playing, controller.currentTime > 1 { return true }
                }
                return false
            }
            guard await waitPlaying() else { return finish("never played: \(controller.phase)") }
            var report = "playing in main"
            let session = PlaybackSession(testing: controller, key: entry.id)
            testModel.playback = session
            MiniPlayerWindow.offscreenForTesting = true
            let mini = MiniPlayerWindow.shared
            mini.show(model: testModel)
            try? await Task.sleep(for: .seconds(1))
            let panel = mini.testPanel
            let t1 = controller.currentTime
            try? await Task.sleep(for: .seconds(3))
            report += "; mini: inPanel=\(controller.webView.window === panel) isMini=\(session.isMini)"
            report += " phase=\(controller.phase) advanced=\(controller.currentTime > t1 + 1)"
            report += " floating=\(panel?.level == .floating) hidesOnDeactivate=\(panel?.hidesOnDeactivate ?? true)"
            if let panel {
                let size = mini.windowWillResize(panel, to: NSSize(width: 900, height: 300))
                let content = panel.contentRect(forFrameRect: NSRect(origin: .zero, size: size))
                report += " resize900→video \(Int(content.width))×\(Int(content.height - MiniPlayerWindow.barHeight))"
                let small = mini.windowWillResize(panel, to: NSSize(width: 100, height: 100))
                report += " min=\(Int(panel.contentRect(forFrameRect: NSRect(origin: .zero, size: small)).width))"
            }
            // Expand: the full player screen re-hosts the same web view.
            mini.expand()
            main.contentView = NSHostingView(rootView: PlayerWebViewRepresentable(controller: controller))
            try? await Task.sleep(for: .seconds(1))
            let t2 = controller.currentTime
            try? await Task.sleep(for: .seconds(3))
            report += "; expanded: inMain=\(controller.webView.window === main) isMini=\(session.isMini)"
            report +=
                " route=\(testModel.path.last == session.route) phase=\(controller.phase) advanced=\(controller.currentTime > t2 + 1)"
            report += " noReload=\(controller.currentTime > 6)"
            // Keys, on the real player screen (the real model only holds this playback; nothing is marked).
            testModel.playback = nil
            model.playback = session
            main.contentView = NSHostingView(rootView: PlayerScreen(mode: session.mode).environment(model))
            try? await Task.sleep(for: .seconds(1))
            func press(_ key: String, in window: NSWindow?) async {
                guard let window,
                    let event = NSEvent.keyEvent(
                        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                        windowNumber: window.windowNumber, context: nil, characters: key,
                        charactersIgnoringModifiers: key, isARepeat: false, keyCode: key == "t" ? 17 : 34)
                else { return }
                NSApp.sendEvent(event)
                try? await Task.sleep(for: .seconds(1))
            }
            func viewCount(_ view: NSView?) -> Int { (view?.subviews ?? []).reduce(1) { $0 + viewCount($1) } }
            let before = viewCount(main.contentView)
            await press("t", in: main)
            let withTable = viewCount(main.contentView)
            await press("t", in: main)
            report += "; keys: T opens=\(withTable > before) T closes=\(viewCount(main.contentView) < withTable)"
            await press("i", in: main)
            report += " I→mini=\(session.isMini && controller.webView.window === panel) \(controller.phase)"
            try? await Task.sleep(for: .seconds(2))
            report += "→\(controller.phase)"
            await press("i", in: panel)
            try? await Task.sleep(for: .seconds(2))
            report += " I→full=\(!session.isMini && controller.webView.window === main) phase=\(controller.phase)"
            // Back to mini, then Close: stops and clears the playback.
            mini.show(model: model)
            mini.close()
            report += "; closed: playback=\(model.playback == nil) panelVisible=\(panel?.isVisible ?? false)"
            finish(report)
        }

        // swiftlint:enable function_body_length

        private static func finish(_ text: String) {
            print("MINI-TEST \(text)")
            exit(0)
        }

        static func pickAndTest(_ model: AppModel) {
            var picks: [String: String] = [:]
            for competition in model.library.competitions {
                for entry in competition.rounds.flatMap(\.matches) {
                    if let video = entry.video, picks[video.channelKey] == nil { picks[video.channelKey] = video.id }
                }
            }
            if let id = SnapshotMode.argument("--video") { picks = ["manual": id] }
            print(
                "PLAYER-TEST picks: \(picks.count) channels, \(model.library.competitions.map(\.rounds.count)) rounds")
            Task {
                for (channel, id) in picks.sorted(by: { $0.key < $1.key }) {
                    let result = await test(id)
                    print("PLAYER-TEST \(channel) \(id): \(result)")
                }
                exit(0)
            }
        }

        static func test(_ videoId: String) async -> String {
            let controller = PlayerController(videoId: videoId, muted: true)
            var events: [String] = []
            controller.onEvent = { events.append($0) }
            let window = NSWindow(
                contentRect: CGRect(x: -5000, y: -5000, width: 640, height: 360), styleMask: [.borderless],
                backing: .buffered, defer: false)
            controller.webView.frame = CGRect(x: 0, y: 0, width: 640, height: 360)
            window.contentView = controller.webView
            window.orderFrontRegardless()
            controller.start()
            defer {
                controller.stop()
                window.orderOut(nil)
            }
            // Wait for playback (or an error).
            for _ in 0..<80 {
                try? await Task.sleep(for: .milliseconds(250))
                if case .failed = controller.phase { break }
                if controller.phase == .playing, controller.currentTime > 1 { break }
            }
            var summary = "phase=\(controller.phase) t=\(Int(controller.currentTime)) dur=\(Int(controller.duration))"
            guard controller.phase == .playing else { return summary + " events=\(events)" }
            // Pause / resume.
            controller.togglePlay()
            try? await Task.sleep(for: .seconds(1))
            let paused = controller.phase == .paused
            controller.togglePlay()
            try? await Task.sleep(for: .seconds(1))
            summary += " pause=\(paused) resume=\(controller.phase == .playing)"
            // Queue hand-off: at the end, load a second video into the same player, then let that one finish.
            var handedOff = false
            controller.nextVideo = {
                guard !handedOff else { return nil }
                handedOff = true
                return videoId
            }
            controller.seek(to: max(0, controller.duration - 3))
            for _ in 0..<160 {
                try? await Task.sleep(for: .milliseconds(250))
                if handedOff, controller.phase == .playing, controller.currentTime < 30 { break }
            }
            summary += " queueNext=\(handedOff && controller.phase == .playing)"
            // Jump to the end: the player should report ENDED and be destroyed.
            for _ in 0..<40 where controller.duration == 0 { try? await Task.sleep(for: .milliseconds(250)) }
            controller.seek(to: max(0, controller.duration - 3))
            for _ in 0..<160 {
                try? await Task.sleep(for: .milliseconds(250))
                if controller.phase == .finished { break }
            }
            return summary
                + " end=\(controller.phase == .finished) t_end=\(Int(controller.currentTime)) events=\(events)"
        }
    }
#endif

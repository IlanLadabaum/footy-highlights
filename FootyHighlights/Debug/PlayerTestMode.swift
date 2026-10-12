#if DEBUG && os(macOS)
    import AppKit
    import FootyKit
    import SwiftUI

    /// Developer tool: `--player-test` plays one highlight per channel from the local store, muted, in an
    /// offscreen window, then seeks to the last seconds to check the player is destroyed on end.
    /// Prints channel, video ID and player states only (no titles, nothing visual).
    @MainActor
    enum PlayerTestMode {
        static var enabled: Bool { CommandLine.arguments.contains("--player-test") }

        static func run() {
            let model = AppModel()
            Task {
                await model.refresh()
                pickAndTest(model)
            }
        }

        static func pickAndTest(_ model: AppModel) {
            var picks: [String: String] = [:]
            for competition in model.library.competitions {
                for entry in competition.rounds.flatMap(\.matches) {
                    if let video = entry.video, picks[video.channelKey] == nil { picks[video.channelKey] = video.id }
                }
            }
            if let id = SnapshotMode.argument("--video") { picks = ["manual": id] }
            print("PLAYER-TEST picks: \(picks.count) channels, \(model.library.competitions.map(\.rounds.count)) rounds")
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
            return summary + " end=\(controller.phase == .finished) t_end=\(Int(controller.currentTime)) events=\(events)"
        }
    }
#endif

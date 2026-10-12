import FootyKit
import SwiftUI

/// Dedicated player screen. The video sits at the top; every app control is in a bar *below* it
/// (never over it, per YouTube's terms), and keyboard shortcuts mean the mouse never needs to
/// hover over the video (which would show YouTube's title bar).
struct PlayerScreen: View {
    let matchKey: MatchKey
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(SettingsKeys.hideDurations) private var hideDurations = false
    @State private var controller: PlayerController?
    @State private var isFullScreen = false
    @State private var confirmOriginalTitle = false
    @State private var showOriginalTitle = false

    var body: some View {
        let entry = model.entry(matchKey)
        VStack(spacing: 0) {
            if !isFullScreen, let entry { header(entry) }
            ZStack {
                Color.black
                if let controller {
                    switch controller.phase {
                    case .finished:
                        FinishedPanel(replay: { controller.start() }, back: { dismiss() })
                    case .failed(let code):
                        ErrorPanel(code: code, video: entry?.video) { url in openURL(url) }
                    default:
                        PlayerWebViewRepresentable(controller: controller)
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .frame(minWidth: 480, minHeight: 270)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let controller {
                PlayerControls(
                    controller: controller, hideDurations: hideDurations, isFullScreen: isFullScreen,
                    toggleFullScreen: toggleFullScreen)
            }
        }
        .navigationTitle(entry.map { "\($0.homeName) v \($0.awayName)" } ?? "")
        .toolbar {
            if let entry {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(entry.flags.watched ? "Mark unwatched" : "Mark watched") {
                        model.setWatched([entry], !entry.flags.watched)
                    }
                }
            }
        }
        #if os(macOS)
            .toolbar(isFullScreen ? .hidden : .automatic, for: .windowToolbar)
        #endif
        .onAppear { start(entry) }
        .onDisappear {
            controller?.stop()
            if isFullScreen { toggleFullScreen() }
        }
        #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
                isFullScreen = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
                isFullScreen = false
            }
        #endif
        .confirmationDialog("Show the original YouTube title?", isPresented: $confirmOriginalTitle) {
            Button("Show Original Title") { showOriginalTitle = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Original titles can contain spoilers.")
        }
        .alert("Original title", isPresented: $showOriginalTitle) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(entry?.video?.originalTitle ?? "")
        }
    }

    private func header(_ entry: MatchEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.neutralTitle).font(.title2.weight(.semibold))
            HStack(spacing: 8) {
                if let video = entry.video {
                    Text("Match info by Footy Highlights · video from \(model.channelName(video)) on YouTube")
                }
                Button("Show original title…") { confirmOriginalTitle = true }
                    .buttonStyle(.link)
                if entry.spoilerProneTitle {
                    Label("May show spoiler at start", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func start(_ entry: MatchEntry?) {
        guard controller == nil, let entry, let video = entry.video else { return }
        // Watched works like email read status: opening the video marks it watched.
        if !entry.flags.watched { model.setWatched([entry], true) }
        let controller = PlayerController(videoId: video.id)
        self.controller = controller
        controller.start()
    }

    private func toggleFullScreen() {
        #if os(macOS)
            NSApp.keyWindow?.toggleFullScreen(nil)
        #endif
    }
}

/// App-drawn controls below the video.
struct PlayerControls: View {
    let controller: PlayerController
    let hideDurations: Bool
    let isFullScreen: Bool
    let toggleFullScreen: () -> Void
    @State private var scrubbing: Double?

    var body: some View {
        HStack(spacing: 14) {
            Button(action: controller.togglePlay) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill").frame(width: 20)
            }
            .keyboardShortcut(.space, modifiers: [])
            .help(isPlaying ? "Pause (Space)" : "Play (Space)")

            Button { controller.seek(by: -10) } label: { Image(systemName: "gobackward.10") }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .help("Back 10 seconds (←)")
            Button { controller.seek(by: 10) } label: { Image(systemName: "goforward.10") }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .help("Forward 10 seconds (→)")

            Text(timeText).monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 90, alignment: .leading)

            // Progress without previews. With durations hidden, the bar can't be shown without revealing the length.
            if !hideDurations, controller.duration > 0 {
                Slider(
                    value: Binding(get: { scrubbing ?? controller.currentTime }, set: { scrubbing = $0 }),
                    in: 0...controller.duration
                ) { editing in
                    if !editing, let target = scrubbing {
                        controller.seek(to: target)
                        scrubbing = nil
                    }
                }
            } else {
                Spacer()
            }

            Button(action: controller.toggleMute) {
                Image(systemName: controller.isMuted || controller.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .help("Mute")
            Slider(value: Binding(get: { controller.isMuted ? 0 : controller.volume }, set: controller.setVolume), in: 0...100)
                .frame(width: 90)

            Button(action: toggleFullScreen) {
                Image(systemName: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }
            .keyboardShortcut("f", modifiers: [])
            .help(isFullScreen ? "Exit full screen (F or Esc)" : "Full screen (F)")
            if isFullScreen {
                Button("", action: toggleFullScreen).keyboardShortcut(.escape, modifiers: []).hidden().frame(width: 0)
            }
        }
        .buttonStyle(.borderless)
        .font(.title3)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var isPlaying: Bool { controller.phase == .playing || controller.phase == .buffering }

    private var timeText: String {
        let elapsed = Formatting.duration(Int(scrubbing ?? controller.currentTime))
        guard !hideDurations, controller.duration > 0 else { return elapsed }
        return "\(elapsed) / \(Formatting.duration(Int(controller.duration)))"
    }
}

struct FinishedPanel: View {
    let replay: () -> Void
    let back: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle").font(.system(size: 44))
            Text("Finished").font(.title2)
            HStack {
                Button("Watch again", action: replay)
                Button("Back to round", action: back).keyboardShortcut(.defaultAction)
            }
        }
        .foregroundStyle(.white)
    }
}

struct ErrorPanel: View {
    let code: Int
    let video: Video?
    let open: (URL) -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 40))
            Text(message).multilineTextAlignment(.center).frame(maxWidth: 460)
            if let video {
                Button("Open on YouTube (may show score)") { open(Formatting.youTubeURL(video)) }
            }
        }
        .foregroundStyle(.white)
        .padding()
    }

    private var message: String {
        switch code {
        case 101, 150:
            "The owner of this video doesn't allow it to play inside other apps."
        case 152, 153:
            "YouTube refused to play this video inside the app."
        case 100:
            "This video is no longer available."
        case 2, 5:
            "YouTube couldn't play this video."
        case -1:
            "Couldn't load YouTube's player. Check your internet connection."
        default:
            "YouTube couldn't play this video (error \(code))."
        }
    }
}

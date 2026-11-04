import FootyKit
import SwiftUI

/// Dedicated player screen using YouTube's own controls (subtitles, quality, full screen, keyboard).
/// The app adds nothing on top of the video; its own controls sit in a bar below it.
struct PlayerScreen: View {
    enum Mode: Hashable {
        case single(MatchKey)
        /// Plays the queue from the top, continuing automatically.
        case queue
    }

    let mode: Mode
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var controller: PlayerController?
    /// The match currently loaded in the player.
    @State private var currentKey: MatchKey?
    @State private var confirmOriginalTitle = false
    @State private var showOriginalTitle = false
    @State private var showTable = false

    var body: some View {
        let entry = currentKey.flatMap { model.entry($0) }
        let tableRound = entry.flatMap { model.library.round($0.roundId) }.flatMap { $0.layout == .withTable ? $0 : nil }
        HStack(spacing: 0) {
            playerColumn(entry, tableRound: tableRound)
            if showTable, let tableRound, let competition = model.library.competition(tableRound.id.competitionId) {
                Divider()
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button {
                            showTable = false
                        } label: {
                            Label("Close table", systemImage: "xmark")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding([.top, .horizontal], 10)
                    LeagueTableView(
                        round: tableRound, competition: competition,
                        highlighted: entry?.fixture.map { [$0.home.id, $0.away.id] } ?? [])
                }
                .frame(width: 400)
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeOut(duration: 0.2), value: showTable)
        .navigationTitle(mode == .queue ? "Queue" : entry.map { "\($0.homeName) v \($0.awayName)" } ?? "")
        .toolbar {
            if let entry {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(entry.flags.watched ? "Mark unwatched" : "Mark watched") {
                        model.setWatched([entry], !entry.flags.watched)
                    }
                }
            }
        }
        .onAppear(perform: begin)
        .onDisappear { controller?.stop() }
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

    private func playerColumn(_ entry: MatchEntry?, tableRound: Round?) -> some View {
        VStack(spacing: 0) {
            if let entry { header(entry) }
            ZStack {
                Color.black
                if let controller {
                    switch controller.phase {
                    case .finished:
                        FinishedPanel(isQueue: mode == .queue, replay: { controller.start() }, back: { dismiss() })
                    case .failed(let code):
                        ErrorPanel(
                            code: code, video: entry?.video, open: { openURL($0) },
                            skip: mode == .queue && !model.queuedEntries.isEmpty ? { advance() } : nil)
                    default:
                        PlayerWebViewRepresentable(controller: controller)
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .frame(minWidth: 480, minHeight: 270)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomBar(hasTable: tableRound != nil)
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

    /// The app's own bar below the video (never over it): the table toggle, and in queue mode what's next.
    private func bottomBar(hasTable: Bool) -> some View {
        let upcoming = model.queuedEntries
        return HStack(spacing: 12) {
            if mode == .queue {
                if let next = upcoming.first {
                    Text("Up next: \(next.homeName) v \(next.awayName)").lineLimit(1)
                    if upcoming.count > 1 {
                        Text("+\(upcoming.count - 1) more").foregroundStyle(.secondary)
                    }
                } else {
                    Text("Last video in the queue").foregroundStyle(.secondary)
                }
            }
            Spacer()
            if hasTable {
                Button {
                    showTable.toggle()
                } label: {
                    Label(showTable ? "Hide table" : "Show table", systemImage: "tablecells")
                }
                .keyboardShortcut("t", modifiers: .command)
                .help("The table as it stood before this round (⌘T)")
            }
            if mode == .queue {
                QueueToolbarButton()
                Button {
                    advance()
                } label: {
                    Label("Next", systemImage: "forward.end.fill")
                }
                .disabled(upcoming.isEmpty)
                .help("Skip to the next video in the queue")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func begin() {
        guard controller == nil else { return }
        let first: MatchEntry?
        switch mode {
        case .single(let key):
            first = model.entry(key)
            // Watched works like email read status: opening the video marks it watched.
            if let first, !first.flags.watched { model.setWatched([first], true) }
            // Watching a queued match outside the queue takes it off the queue.
            if let first { model.dequeue(first.id) }
        case .queue:
            first = model.popQueue()
        }
        guard let first, let video = first.video else { return }
        currentKey = first.id
        let controller = PlayerController(videoId: video.id)
        if mode == .queue {
            // When a video ends, continue with the next one in the same player (keeps full screen).
            controller.nextVideo = { [model] in
                guard let next = model.popQueue(), let video = next.video else { return nil }
                currentKey = next.id
                return video.id
            }
        }
        self.controller = controller
        controller.start()
    }

    /// Skip: load the next queued video now. It's marked watched as it's reached.
    private func advance() {
        guard let controller, let next = model.popQueue(), let video = next.video else { return }
        currentKey = next.id
        controller.load(videoId: video.id)
    }
}

struct FinishedPanel: View {
    var isQueue = false
    let replay: () -> Void
    let back: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle").font(.system(size: 44))
            Text(isQueue ? "Queue finished" : "Finished").font(.title2)
            HStack {
                if !isQueue { Button("Watch again", action: replay) }
                Button("Back", action: back).keyboardShortcut(.defaultAction)
            }
        }
        .foregroundStyle(.white)
    }
}

struct ErrorPanel: View {
    let code: Int
    let video: Video?
    let open: (URL) -> Void
    var skip: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 40))
            Text(message).multilineTextAlignment(.center).frame(maxWidth: 460)
            HStack {
                if let video {
                    Button("Open on YouTube (may show score)") { open(Formatting.youTubeURL(video)) }
                }
                if let skip { Button("Skip to next", action: skip) }
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

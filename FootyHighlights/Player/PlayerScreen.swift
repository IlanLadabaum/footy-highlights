import FootyKit
import SwiftUI

/// Dedicated player screen using YouTube's own controls (subtitles, quality, full screen, keyboard).
/// The app adds nothing on top of the video; its own controls sit in a bar below it.
struct PlayerScreen: View {
    typealias Mode = PlaybackSession.Mode

    let mode: Mode
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var confirmOriginalTitle = false
    @State private var showOriginalTitle = false
    @State private var showTable = false
    @State private var showRestore = false

    /// This screen's playback (not while it's in the mini player).
    private var session: PlaybackSession? {
        guard let session = model.playback, session.mode == mode, !session.isMini else { return nil }
        return session
    }

    var body: some View {
        let entry = session.flatMap { model.entry($0.currentKey) }
        let tableRound = entry.flatMap { model.library.round($0.roundId) }.flatMap {
            $0.layout == .withTable ? $0 : nil
        }
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
        .onDisappear(perform: end)
        .confirmationDialog("Show the original YouTube title?", isPresented: $confirmOriginalTitle) {
            Button("Show Original Title") { showOriginalTitle = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Original titles can contain spoilers.")
        }
        .sheet(isPresented: $showRestore) {
            RestoreQueueSheet(
                entries: model.checkpointEntries,
                pick: { key in
                    showRestore = false
                    model.restoreQueue(from: key)
                    session?.advance(model: model)
                },
                cancel: { showRestore = false })
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
                if let controller = session?.controller {
                    switch controller.phase {
                    case .finished:
                        FinishedPanel(
                            isQueue: mode == .queue, replay: { controller.start() }, back: { dismiss() },
                            restore: mode == .queue && !model.checkpointEntries.isEmpty ? { showRestore = true } : nil)
                    case .failed(let code):
                        ErrorPanel(
                            code: code, video: entry?.video, open: { openURL($0) },
                            skip: mode == .queue && !model.queuedEntries.isEmpty
                                ? { session?.advance(model: model) } : nil)
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
            #if os(macOS)
                if let phase = session?.controller.phase, phase != .finished {
                    Button {
                        MiniPlayerWindow.shared.show(model: model)
                    } label: {
                        Label("Mini player", systemImage: "pip.enter")
                    }
                    .help("Keep watching in a small window while you browse")
                }
            #endif
            if mode == .queue {
                QueueToolbarButton()
                Button {
                    session?.advance(model: model)
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
        if let existing = model.playback {
            if existing.mode == mode {
                // Back from the mini player (or the same match opened again): keep playing here.
                if existing.isMini {
                    existing.isMini = false
                    #if os(macOS)
                        MiniPlayerWindow.shared.hide()
                    #endif
                }
                return
            }
            // Something else was playing in the mini player: only one video plays at a time.
            existing.stop()
            #if os(macOS)
                MiniPlayerWindow.shared.hide()
            #endif
        }
        model.playback = PlaybackSession(mode: mode, model: model)
    }

    /// Leaving the screen stops the video, unless it moved to the mini player.
    private func end() {
        guard let session else { return }
        session.stop()
        model.playback = nil
    }
}

struct FinishedPanel: View {
    var isQueue = false
    let replay: () -> Void
    let back: () -> Void
    /// Queue only: reopens the queue as it was when it was started (for when you dozed off).
    var restore: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle").font(.system(size: 44))
            Text(isQueue ? "Queue finished" : "Finished").font(.title2)
            HStack {
                if !isQueue { Button("Watch again", action: replay) }
                if let restore { Button("Restore queue…", action: restore) }
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

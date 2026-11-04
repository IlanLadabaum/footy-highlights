import FootyKit
import SwiftUI

/// A match in a round: neutral teams, watched checkbox, play / fallback actions, reveal checkbox.
/// Never shows the original title, a thumbnail or (unless revealed) the score.
struct MatchRow: View {
    let entry: MatchEntry
    /// The reveal checkbox also updates a table on this screen.
    let showsTableHint: Bool
    /// Played weeks before the rest of the round (brought forward), so already in the pre-round table.
    var countedInTable = false
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @AppStorage(SettingsKeys.hideDurations) private var hideDurations = false
    @State private var confirmOriginalTitle = false
    @State private var showOriginalTitle = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            watchedCheckbox
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(entry.homeName) v \(entry.awayName)")
                        .font(.headline)
                        .foregroundStyle(entry.flags.watched ? .secondary : .primary)
                    if entry.scoreVisible, let score = entry.fixture?.score {
                        Text(score.display)
                            .font(.headline.monospacedDigit())
                            .padding(.horizontal, 6)
                            .background(.yellow.opacity(0.25), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                details
                if entry.hasCutChoice { cutPicker }
                availabilityLine
                if countedInTable {
                    Text("Played earlier than the rest of the round, so it's already in the table")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let firstLeg = entry.firstLeg { FirstLegLine(info: firstLeg) }
                if entry.fixture?.score != nil {
                    Toggle(isOn: Binding(get: { entry.flags.revealed }, set: { model.setRevealed(entry, $0) })) {
                        Text(showsTableHint ? "Show score & update table" : "Show score").font(.caption)
                    }
                    .modifier(CheckboxStyle())
                }
            }
            Spacer(minLength: 8)
            actions
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .contextMenu { contextMenu }
        .confirmationDialog("Show the original YouTube title?", isPresented: $confirmOriginalTitle) {
            Button("Show Original Title") { showOriginalTitle = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Original titles can contain spoilers.")
        }
        .alert("Original title", isPresented: $showOriginalTitle) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(entry.video?.originalTitle ?? entry.browserFallbackVideo?.originalTitle ?? "")
        }
    }

    @ViewBuilder private var watchedCheckbox: some View {
        if entry.isPlayable {
            Toggle(isOn: Binding(get: { entry.flags.watched }, set: { model.setWatched([entry], $0) })) {
                EmptyView()
            }
            .modifier(CheckboxStyle())
            .labelsHidden()
            .help(entry.flags.watched ? "Watched" : "Not watched")
        } else {
            Color.clear.frame(width: 16, height: 16)
        }
    }

    private var details: some View {
        HStack(spacing: 6) {
            Text(Formatting.day(entry.date))
            if let seconds = entry.video?.durationSeconds, !hideDurations, !entry.hasCutChoice {
                Text("·")
                Label(Formatting.duration(seconds), systemImage: "film")
                    .labelStyle(.titleAndIcon)
                    .monospacedDigit()
                    .help("Video length")
            }
            if let channel = entry.channelName {
                Text("·")
                Text("\(channel) on YouTube")
            }
            if entry.spoilerProneTitle && entry.isPlayable {
                Label("May show spoiler at start", systemImage: "exclamationmark.triangle")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.orange)
                    .help(
                        "This channel's original titles sometimes hint at the result. "
                            + "YouTube shows the title for a few seconds when the video starts.")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// Extended / normal, when the source posted both. Shows the selected cut's length; queueing and Play use it.
    private var cutPicker: some View {
        HStack(spacing: 8) {
            Picker(
                "Version",
                selection: Binding(get: { entry.selectedCut ?? model.defaultCut }, set: { model.setCut(entry, $0) })
            ) {
                Text("Extended").tag(HighlightCut.extended)
                Text("Normal").tag(HighlightCut.normal)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .help("This match has a normal and an extended highlight. Play and Queue use the one selected here.")
            if let seconds = entry.video?.durationSeconds, !hideDurations {
                Label(Formatting.duration(seconds), systemImage: "film")
                    .labelStyle(.titleAndIcon)
                    .monospacedDigit()
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Length of the selected version")
            }
        }
    }

    @ViewBuilder private var availabilityLine: some View {
        switch entry.availability {
        case .playable:
            EmptyView()
        case .noHighlights:
            Text("No highlights available").font(.caption).foregroundStyle(.secondary)
        case .highlightsPending:
            Text("Highlights not available yet").font(.caption).foregroundStyle(.secondary)
        case .inProgress:
            Text("In progress").font(.caption).foregroundStyle(.secondary)
        case .upcoming(let date):
            Text("Kick-off \(Formatting.kickoff(date))").font(.caption).foregroundStyle(.secondary)
        case .notPlayed(let status):
            Text(Formatting.status(status)).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var actions: some View {
        if entry.isPlayable {
            HStack(spacing: 8) {
                let queued = model.isQueued(entry)
                Button {
                    model.toggleQueued(entry)
                } label: {
                    Label(queued ? "Queued" : "Queue", systemImage: queued ? "text.badge.checkmark" : "text.badge.plus")
                }
                .buttonStyle(.bordered)
                .help(queued ? "Remove from the queue" : "Add to the queue (it's marked watched only when it plays)")
                NavigationLink(value: Route.player(entry.id)) {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        } else if let fallback = entry.browserFallbackVideo {
            Button {
                openURL(Formatting.youTubeURL(fallback))
            } label: {
                Label("Open on YouTube (may show score)", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.bordered)
            .help(
                "This video can't play inside the app. YouTube shows its original title, which may include the score.")
        }
    }

    @ViewBuilder private var contextMenu: some View {
        if entry.isPlayable {
            Button(entry.flags.watched ? "Mark Unwatched" : "Mark Watched") {
                model.setWatched([entry], !entry.flags.watched)
            }
            Button(model.isQueued(entry) ? "Remove from Queue" : "Add to Queue") { model.toggleQueued(entry) }
        }
        if entry.video != nil || entry.browserFallbackVideo != nil {
            Button("Show Original Title…") { confirmOriginalTitle = true }
        }
        if let video = entry.video ?? entry.browserFallbackVideo {
            Button("Open on YouTube (may show score)") { openURL(Formatting.youTubeURL(video)) }
        }
    }
}

/// Second legs: the first-leg score, hidden until that match is watched or revealed.
struct FirstLegLine: View {
    let info: FirstLegInfo
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            if info.scoreVisible, let score = info.fixture.score {
                Text("1st leg: \(info.homeName) \(score.display) \(info.awayName)")
            } else {
                Text("1st leg: hidden ·")
                Button("Reveal") { model.revealFirstLeg(info) }
                    .buttonStyle(.link)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// Checkboxes on macOS; switches elsewhere (iPad later).
struct CheckboxStyle: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
            content.toggleStyle(.checkbox)
        #else
            content
        #endif
    }
}

enum SettingsKeys {
    static let hideDurations = "hideDurations"
}

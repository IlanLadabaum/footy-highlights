import FootyKit
import SwiftUI

/// Inside a competition: the latest round as the largest panel, earlier rounds below. No table here.
struct RoundsView: View {
    let competitionId: String
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @State private var undo = UndoState()

    var body: some View {
        let competition = model.library.competition(competitionId)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let competition {
                    if !competition.usesFixtureData, competition.config.footballDataCode != nil {
                        NoFixtureDataNote()
                    }
                    if competition.rounds.isEmpty {
                        Text(model.isRefreshing ? "Looking for highlights…" : "No highlights yet this season.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(Array(competition.rounds.enumerated()), id: \.element.id) { index, round in
                        RoundPanel(
                            round: round, isLatest: index == 0, markAll: { markAll(round) },
                            queueAll: { model.queueAllUnwatched(in: round) })
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle(competition?.config.name ?? "")
        .toolbar { RefreshToolbar() }
        .overlay(alignment: .bottom) {
            if let message = undo.message {
                UndoBanner(message: message, undo: { undo.undo(model: model) }, dismiss: { undo.message = nil })
            }
        }
    }

    private func markAll(_ round: Round) {
        let entries = round.matches.filter(\.isUnwatched)
        let previous = model.setWatched(entries, true)
        undo.offer("Marked \(entries.count) highlights in \(round.name) as watched",
                   previous: previous, undoManager: undoManager, model: model)
    }
}

struct RoundPanel: View {
    let round: Round
    let isLatest: Bool
    let markAll: () -> Void
    let queueAll: () -> Void

    var body: some View {
        NavigationLink(value: Route.round(round.id)) {
            VStack(alignment: .leading, spacing: isLatest ? 10 : 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(round.name).font(isLatest ? .title.weight(.semibold) : .headline)
                    Spacer()
                    UnwatchedBadge(count: round.unwatchedCount)
                }
                Text(Formatting.dateRange(round.start, round.end))
                    .font(isLatest ? .body : .subheadline)
                    .foregroundStyle(.secondary)
                Text(summary).font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(isLatest ? 24 : 14)
            .frame(maxWidth: .infinity, minHeight: isLatest ? 150 : 0, alignment: .topLeading)
            .background(.quaternary.opacity(isLatest ? 0.7 : 0.4), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomTrailing) {
            if round.unwatchedCount > 0 {
                HStack(spacing: 16) {
                    Button("Queue all unwatched", action: queueAll)
                    Button("Mark all as watched", action: markAll)
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .padding(isLatest ? 20 : 12)
            }
        }
    }

    private var summary: String {
        let playable = round.playableCount
        let total = round.matches.count
        if playable == total { return "\(total) highlight\(total == 1 ? "" : "s")" }
        return "\(playable) of \(total) matches have highlights"
    }
}

/// Shown where fixture data would add round numbers, "no highlights" rows and tables.
struct NoFixtureDataNote: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
            Text("Add a football-data.org key in Settings to see round numbers, matches without highlights and league tables.")
            Spacer()
            #if os(macOS)
                SettingsLink { Text("Open Settings") }
            #endif
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(12)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }
}

import FootyKit
import SwiftUI

/// One round: fixtures on one side, the league table on the other (or full-width fixtures for cups/knockouts).
struct RoundView: View {
    let roundId: RoundID
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @State private var undo = UndoState()
    /// Teams of the match row under the mouse, highlighted in the table.
    @State private var hoveredTeams: Set<Int> = []

    var body: some View {
        let round = model.library.round(roundId)
        let competition = model.library.competition(roundId.competitionId)
        Group {
            if let round, let competition {
                switch round.layout {
                case .fullWidth:
                    fixtures(round, competition: competition)
                case .withTable, .tableNeedsKey:
                    HStack(alignment: .top, spacing: 0) {
                        fixtures(round, competition: competition)
                            .frame(minWidth: 420, maxWidth: .infinity)
                        Divider()
                        TablePanel(round: round, competition: competition, highlighted: hoveredTeams)
                            .frame(minWidth: 330, idealWidth: 400, maxWidth: 480)
                    }
                }
            } else {
                Text("This round is no longer available.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(round.map { "\(competition?.config.name ?? "") · \($0.name)" } ?? "")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let round, round.unwatchedCount > 0 {
                    Button("Queue all unwatched") { model.queueAllUnwatched(in: round) }
                        .help("Add this round's unwatched highlights to the queue, in order")
                    Button("Mark all as watched") { markAll(round) }
                }
            }
            RefreshToolbar()
        }
        .overlay(alignment: .bottom) {
            if let message = undo.message {
                UndoBanner(message: message, undo: { undo.undo(model: model) }, dismiss: { undo.message = nil })
            }
        }
    }

    private func fixtures(_ round: Round, competition: CompetitionSummary) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text(Formatting.dateRange(round.start, round.end))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                ForEach(round.matches) { entry in
                    MatchRow(
                        entry: entry, showsTableHint: round.layout == .withTable,
                        countedInTable: round.layout == .withTable
                            && (entry.fixture.map { fixture in round.earliestKickoff.map { fixture.utcDate < $0 } ?? false } ?? false))
                        .onHover { hovering in
                            guard let fixture = entry.fixture else { return }
                            if hovering {
                                hoveredTeams = [fixture.home.id, fixture.away.id]
                            } else if hoveredTeams == [fixture.home.id, fixture.away.id] {
                                hoveredTeams = []
                            }
                        }
                    Divider().padding(.leading, 20)
                }
            }
            .padding(.bottom, 60)
        }
    }

    private func markAll(_ round: Round) {
        let entries = round.matches.filter(\.isUnwatched)
        let previous = model.setWatched(entries, true)
        undo.offer("Marked \(entries.count) highlights as watched", previous: previous, undoManager: undoManager, model: model)
    }
}

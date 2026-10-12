import FootyKit
import SwiftUI

/// The pre-round table: standings before the round's first kickoff, plus only the results the user
/// revealed in this round. Never current standings, never form.
struct LeagueTableView: View {
    let round: Round
    let competition: CompetitionSummary
    let highlighted: Set<Int>
    @Environment(AppModel.self) private var model
    @State private var confirmRevealAll = false

    var body: some View {
        if let table = model.table(for: round) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header(table)
                        columnHeader
                        ForEach(table.rows) { row in
                            TableRowView(row: row, name: model.displayName(row.team), isHighlighted: highlighted.contains(row.id))
                                .id(row.id)
                        }
                        ForEach(table.deductionNotes, id: \.self) { note in
                            Text(note).font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.top, 6)
                        }
                    }
                    .padding(.bottom, 20)
                }
                .onChange(of: highlighted) { _, teams in
                    if let first = table.rows.first(where: { teams.contains($0.id) }) {
                        withAnimation { proxy.scrollTo(first.id, anchor: .center) }
                    }
                }
            }
        } else {
            Text("No table for this round.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ table: AppModel.RoundTable) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            revealAllButton
                .padding(.bottom, 8)
            Text("Table before \(round.name)").font(.headline)
            Text(table.revealedCount == 0
                 ? "Tick “Show score & update table” on a match to add its result."
                 : "Including \(table.revealedCount) revealed result\(table.revealedCount == 1 ? "" : "s") from this \(noun).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    /// Reveals every finished match of the round at once (asks first, since it shows all their scores).
    @ViewBuilder private var revealAllButton: some View {
        let revealable = model.revealableMatches(in: round)
        let live = model.library.round(round.id) ?? round
        let allRevealed = !revealable.isEmpty && model.revealableMatches(in: live).allSatisfy(\.flags.revealed)
        if !revealable.isEmpty {
            if allRevealed {
                Button("Hide this \(noun)'s scores again") { model.setAllRevealed(in: live, false) }
                    .buttonStyle(.link)
                    .font(.caption)
            } else {
                Button {
                    confirmRevealAll = true
                } label: {
                    Label("Update table with all scores from this \(noun)", systemImage: "eye")
                }
                .controlSize(.small)
                .confirmationDialog(
                    "Show all \(revealable.count) scores from \(round.name)?", isPresented: $confirmRevealAll
                ) {
                    Button("Show All Scores") { model.setAllRevealed(in: live, true) }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Every finished match in this \(noun) will show its score and count in the table.")
                }
            }
        }
    }

    /// "matchweek" (Premier League), "matchday" (other leagues), "round" otherwise.
    private var noun: String {
        competition.config.effectiveRoundStyle == .league ? (competition.config.roundNoun ?? "round").lowercased() : "round"
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("#").frame(width: 28, alignment: .trailing)
            Text("Team").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 10)
            ForEach(["P", "W", "D", "L", "GD"], id: \.self) { Text($0).frame(width: 30, alignment: .trailing) }
            Text("Pts").frame(width: 36, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

struct TableRowView: View {
    let row: StandingsEntry
    let name: String
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 0) {
            Text("\(row.position)").frame(width: 28, alignment: .trailing).foregroundStyle(.secondary)
            Text(name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 10)
            Group {
                Text("\(row.played)").frame(width: 30, alignment: .trailing)
                Text("\(row.won)").frame(width: 30, alignment: .trailing)
                Text("\(row.drawn)").frame(width: 30, alignment: .trailing)
                Text("\(row.lost)").frame(width: 30, alignment: .trailing)
                Text(row.goalDifference > 0 ? "+\(row.goalDifference)" : "\(row.goalDifference)")
                    .frame(width: 30, alignment: .trailing)
            }
            .foregroundStyle(.secondary)
            Text("\(row.points)").fontWeight(.semibold).frame(width: 36, alignment: .trailing)
        }
        .font(.callout.monospacedDigit())
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(isHighlighted ? Color.accentColor.opacity(0.22) : Color.clear)
        .animation(.easeOut(duration: 0.15), value: isHighlighted)
    }
}

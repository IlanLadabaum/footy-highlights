import FootyKit
import SwiftUI

/// The pre-round table: standings before the round's first kickoff, plus only the results the user
/// revealed in this round. Never current standings, never form.
struct LeagueTableView: View {
    let round: Round
    let competition: CompetitionSummary
    let highlighted: Set<Int>
    /// In the player: the match being watched. Its own score toggle replaces "update table with all scores".
    var currentMatch: MatchKey?
    @Environment(AppModel.self) private var model
    @State private var confirmRevealAll = false
    /// Team whose previous results box is open.
    @State private var selectedTeam: Int?

    var body: some View {
        if let table = model.table(for: round) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header(table)
                        columnHeader
                        ForEach(table.rows) { row in
                            TableRowView(
                                row: row, name: model.displayName(row.team),
                                isHighlighted: highlighted.contains(row.id),
                                zone: competition.config.zone(forPosition: row.position)
                            )
                            .id(row.id)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedTeam = row.id }
                            .help("Show \(model.displayName(row.team))'s previous results")
                            .popover(
                                isPresented: Binding(
                                    get: { selectedTeam == row.id }, set: { if !$0 { selectedTeam = nil } }),
                                arrowEdge: .leading
                            ) {
                                TeamResultsBox(team: row.team, round: round) { selectedTeam = nil }
                                    .environment(model)
                            }
                        }
                        ZoneKey(config: competition.config, rowCount: table.rows.count)
                        ForEach(table.deductionNotes, id: \.self) { note in
                            Text(note).font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 12).padding(
                                .top, 6)
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
            Text("No table for this round.").foregroundStyle(.secondary).frame(
                maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ table: AppModel.RoundTable) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Group {
                if let currentMatch { currentMatchToggle(currentMatch) } else { revealAllButton }
            }
            .padding(.bottom, 8)
            Text("Table before \(round.name)").font(.headline)
            Text(
                table.revealedCount == 0
                    ? "Tick “Show score & update table” on a match to add its result."
                    : "Including \(table.revealedCount) revealed result\(table.revealedCount == 1 ? "" : "s") from this \(noun)."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    /// The player's table: shows or hides only the current match's score (same as its row's checkbox).
    @ViewBuilder private func currentMatchToggle(_ key: MatchKey) -> some View {
        if let entry = model.entry(key), entry.fixture?.score != nil, entry.fixture?.status.isFinal == true {
            Toggle(
                isOn: Binding(get: { entry.flags.revealed }, set: { model.setRevealed(entry, $0) })
            ) {
                Text("Show this match's score & update table").font(.caption)
            }
            .modifier(CheckboxStyle())
        }
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
        competition.config.effectiveRoundStyle == .league
            ? (competition.config.roundNoun ?? "round").lowercased() : "round"
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
    var zone: TableZoneKind?

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
        // The highlight (blue) wins over the zone tint; the zone's edge bar stays.
        .background(isHighlighted ? Color.accentColor.opacity(0.22) : zone?.color.opacity(0.13) ?? Color.clear)
        .overlay(alignment: .leading) {
            if let zone { Rectangle().fill(zone.color).frame(width: 3) }
        }
        .animation(.easeOut(duration: 0.15), value: isHighlighted)
    }
}

/// Compact key under the table for the zones the table actually shows.
struct ZoneKey: View {
    let config: CompetitionConfig
    let rowCount: Int

    var body: some View {
        let kinds = (config.tableZones ?? []).filter { $0.from <= rowCount }.map(\.kind)
        if !kinds.isEmpty {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 3
            ) {
                ForEach(kinds, id: \.self) { kind in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(kind.color).frame(width: 9, height: 9)
                        Text(kind.label)
                    }
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
    }
}

extension TableZoneKind {
    /// Greens for good outcomes (darkest = best), reds for bad ones; none of them close to the highlight blue.
    var color: Color {
        switch self {
        case .championsLeague, .knockouts, .promotion: Color(red: 0.10, green: 0.55, blue: 0.25)
        case .championsLeagueQualifying: Color(red: 0.22, green: 0.66, blue: 0.30)
        case .europaLeague, .knockoutPlayoff, .promotionPlayoff: Color(red: 0.42, green: 0.74, blue: 0.24)
        case .conferenceLeague: Color(red: 0.66, green: 0.80, blue: 0.26)
        case .relegationPlayoff: Color(red: 0.93, green: 0.48, blue: 0.24)
        case .relegation, .eliminated: Color(red: 0.84, green: 0.19, blue: 0.19)
        }
    }
}

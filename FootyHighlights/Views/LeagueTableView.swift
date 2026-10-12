import FootyKit
import SwiftUI

/// Placeholder until the league table milestone (M4).
struct LeagueTableView: View {
    let round: Round
    let competition: CompetitionSummary
    let highlighted: Set<Int>

    var body: some View {
        Text("League table").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

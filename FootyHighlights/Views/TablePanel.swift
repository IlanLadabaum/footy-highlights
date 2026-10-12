import FootyKit
import SwiftUI

/// The round screen's table side. Without a football-data key it's a greyed prompt.
struct TablePanel: View {
    let round: Round
    let competition: CompetitionSummary
    let highlighted: Set<Int>

    var body: some View {
        switch round.layout {
        case .tableNeedsKey, .fullWidth:
            KeyPromptPanel()
        case .withTable:
            LeagueTableView(round: round, competition: competition, highlighted: highlighted)
        }
    }
}

struct KeyPromptPanel: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tablecells")
                .font(.system(size: 36))
            Text("Add a football-data.org key in Settings to see league tables and round numbers.")
                .multilineTextAlignment(.center)
            #if os(macOS)
                SettingsLink { Text("Open Settings") }
            #endif
        }
        .foregroundStyle(.secondary)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.quaternary.opacity(0.3))
    }
}

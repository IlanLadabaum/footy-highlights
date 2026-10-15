import FootyKit
import SwiftUI

/// A team's previous results in this competition, newest first: only what the round's table already counts.
struct TeamResultsBox: View {
    let team: Team
    let round: Round
    let close: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let results = model.teamResults(team.id, round: round)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(model.displayName(team)): results before \(round.name)").font(.headline)
                Spacer()
                Button(action: close) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                    .help("Close")
            }
            .padding(12)
            Divider()
            if results.isEmpty {
                Text("No results yet this season.").foregroundStyle(.secondary).padding(16)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(results) { fixture in
                            ResultLine(fixture: fixture, teamId: team.id)
                            Divider()
                        }
                    }
                }
                // About 8 lines visible; scroll for the rest of the season.
                .frame(height: min(CGFloat(results.count), 8) * ResultLine.height)
            }
        }
        .frame(width: 400)
    }
}

/// `date  Home v Away  [score]`, the score boxed in green / gold / red for the selected team.
struct ResultLine: View {
    static let height: CGFloat = 34
    let fixture: Fixture
    let teamId: Int
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Text(fixture.utcDate.formatted(.dateTime.day().month(.abbreviated)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)
            HStack(spacing: 4) {
                teamName(fixture.home)
                Text("v").foregroundStyle(.secondary)
                teamName(fixture.away)
            }
            .lineLimit(1)
            Spacer(minLength: 6)
            if let score = fixture.score {
                Text(score.display)
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(color, in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: Self.height)
    }

    private func teamName(_ team: Team) -> some View {
        Text(model.displayName(team)).fontWeight(team.id == teamId ? .semibold : .regular)
    }

    private var color: Color {
        switch TeamResults.outcome(of: fixture, for: teamId) {
        case .win: Color(red: 0.16, green: 0.62, blue: 0.29)
        case .draw: Color(red: 0.85, green: 0.63, blue: 0.08)
        case .loss: Color(red: 0.80, green: 0.20, blue: 0.18)
        case nil: .gray
        }
    }
}

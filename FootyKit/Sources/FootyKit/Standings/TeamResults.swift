import Foundation

/// A team's previous results in one competition, with the same spoiler rule as the pre-round table:
/// only matches the table counts (kickoff before the cut-off, plus ones revealed in the round).
public enum TeamResults {
    public enum Outcome: Sendable {
        case win, draw, loss
    }

    /// Newest first.
    public static func results(
        for teamId: Int, in fixtures: [Fixture], before cutoff: Date, applying revealed: Set<Int> = []
    ) -> [Fixture] {
        fixtures
            .filter { $0.home.id == teamId || $0.away.id == teamId }
            .filter { $0.status.isFinal && $0.score != nil && ($0.utcDate < cutoff || revealed.contains($0.id)) }
            .sorted { $0.utcDate > $1.utcDate }
    }

    /// From `teamId`'s point of view. Shoot-out winners count as a win.
    public static func outcome(of fixture: Fixture, for teamId: Int) -> Outcome? {
        guard let score = fixture.score else { return nil }
        var (ours, theirs) = fixture.home.id == teamId
            ? (score.goals.home, score.goals.away) : (score.goals.away, score.goals.home)
        if ours == theirs, let penalties = score.penalties {
            (ours, theirs) = fixture.home.id == teamId ? (penalties.home, penalties.away) : (penalties.away, penalties.home)
        }
        if ours > theirs { return .win }
        if ours < theirs { return .loss }
        return .draw
    }
}

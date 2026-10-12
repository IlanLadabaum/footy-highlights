import Foundation

/// Links a parsed highlight video to a fixture by (competition, date window, team names).
/// Teams and home/away then come from the fixture, which fixes reversed titles and odd spellings.
public struct FixtureMatcher: Sendable {
    /// A video is expected within this long after kickoff.
    public static let windowAfterKickoff: TimeInterval = 5 * 86_400
    /// Small allowance for clock skew / early publishing.
    public static let windowBeforeKickoff: TimeInterval = 3600

    let names: TeamNames

    public init(names: TeamNames) {
        self.names = names
    }

    /// `fixtures` should be the competition's fixtures, any order.
    public func match(home: String, away: String, publishedAt: Date, in fixtures: [Fixture]) -> Fixture? {
        let candidates = fixtures.filter { fixture in
            let delta = publishedAt.timeIntervalSince(fixture.utcDate)
            return delta >= -Self.windowBeforeKickoff && delta <= Self.windowAfterKickoff
                && !(fixture.status == .postponed || fixture.status == .cancelled)
        }
        guard !candidates.isEmpty else { return nil }

        var scored: [(fixture: Fixture, score: Int)] = []
        for fixture in candidates {
            let straight = pairScore(home, away, fixture.home, fixture.away)
            let reversed = pairScore(home, away, fixture.away, fixture.home)
            let best = max(straight, reversed)
            if best > 0 { scored.append((fixture, best)) }
        }
        if let top = scored.max(by: { rank($0, publishedAt) < rank($1, publishedAt) }) {
            let tied = scored.filter { $0.score == top.score && $0.fixture.id != top.fixture.id }
            // Two different fixtures equally good is ambiguous unless one is clearly nearer in time.
            if tied.isEmpty || tied.allSatisfy({ abs($0.fixture.utcDate.timeIntervalSince(top.fixture.utcDate)) > 86_400 }) {
                return top.fixture
            }
            return nil
        }

        // One side recognised strongly and that team plays only once in the window.
        for side in [home, away] {
            let hits = candidates.filter { fixture in
                names.matchScore(videoName: side, team: fixture.home) >= 2
                    || names.matchScore(videoName: side, team: fixture.away) >= 2
            }
            if hits.count == 1 { return hits[0] }
        }
        return nil
    }

    /// Both names must match something; returns the summed strength or 0.
    private func pairScore(_ videoHome: String, _ videoAway: String, _ teamA: Team, _ teamB: Team) -> Int {
        let first = names.matchScore(videoName: videoHome, team: teamA)
        let second = names.matchScore(videoName: videoAway, team: teamB)
        return first > 0 && second > 0 ? first + second : 0
    }

    private func rank(_ entry: (fixture: Fixture, score: Int), _ publishedAt: Date) -> Double {
        // Higher score first; among equals, the kickoff closest before publishing.
        Double(entry.score) * 1_000_000 - abs(publishedAt.timeIntervalSince(entry.fixture.utcDate)) / 60
    }
}

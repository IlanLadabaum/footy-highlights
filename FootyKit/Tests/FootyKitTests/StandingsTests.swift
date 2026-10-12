import Foundation
import Testing
@testable import FootyKit

struct StandingsTests {
    struct OfficialRow: Decodable {
        var position: Int
        var teamId: Int
        var played: Int
        var points: Int
        var gd: Int
        var gf: Int
    }

    /// M4 "done when": the computed pre-round table matches the official table for that point.
    /// Premier League 2025-26, before matchday 11 == football-data's table after matchday 10.
    @Test func premierLeagueBeforeMatchday11MatchesOfficialTable() throws {
        let fixtures = TestData.fixtures("PL", competitionId: "PL")
        let cutoff = fixtures.filter { $0.matchday == 11 }.map(\.utcDate).min()!
        let table = StandingsCalculator(rule: .premierLeague).table(fixtures: fixtures, before: cutoff)
        let official = try JSONDecoder().decode(
            [OfficialRow].self, from: Data(contentsOf: TestData.url("standings_PL_2025_md10.json")))
        #expect(table.count == official.count)
        for (computed, expected) in zip(table, official) {
            #expect(computed.team.id == expected.teamId, "position \(expected.position)")
            #expect(computed.points == expected.points)
            #expect(computed.goalDifference == expected.gd)
            #expect(computed.goalsFor == expected.gf)
            #expect(computed.played == expected.played)
        }
    }

    @Test func revealingAppliesOnlyThatResult() {
        let a = TestData.team(1, "Alpha"), b = TestData.team(2, "Bravo"), c = TestData.team(3, "Charlie"),
            d = TestData.team(4, "Delta")
        let fixtures = [
            TestData.fixture(10, a, b, "2025-08-16T14:00:00Z", matchday: 1, score: (1, 0)),
            TestData.fixture(11, c, d, "2025-08-16T14:00:00Z", matchday: 1, score: (0, 0)),
            TestData.fixture(20, b, c, "2025-08-23T14:00:00Z", matchday: 2, score: (3, 0)),
            TestData.fixture(21, d, a, "2025-08-23T14:00:00Z", matchday: 2, score: (2, 2)),
        ]
        let calc = StandingsCalculator(rule: .premierLeague)
        let cutoff = TestData.date("2025-08-23T14:00:00Z")
        let before = calc.table(fixtures: fixtures, before: cutoff)
        #expect(before.map(\.team.id) == [1, 3, 4, 2])
        #expect(before.allSatisfy { $0.played == 1 })
        let revealed = calc.table(fixtures: fixtures, before: cutoff, applying: [20])
        #expect(revealed.first { $0.team.id == 2 }?.points == 3)
        #expect(revealed.first { $0.team.id == 1 }?.played == 1)  // match 21 not revealed
        #expect(revealed.map(\.team.id) == [2, 1, 4, 3])
    }

    @Test func headToHeadOnlyOnceBothMeetingsArePlayed() {
        let a = TestData.team(1, "Alpha"), b = TestData.team(2, "Bravo"), c = TestData.team(3, "Charlie")
        // A and B level on points; B has the better goal difference, A won the head-to-head both times.
        let fixtures = [
            TestData.fixture(1, a, b, "2025-08-16T14:00:00Z", score: (1, 0)),
            TestData.fixture(2, b, c, "2025-08-23T14:00:00Z", score: (5, 0)),
            TestData.fixture(3, c, a, "2025-08-30T14:00:00Z", score: (1, 0)),
            TestData.fixture(4, b, a, "2025-09-06T14:00:00Z", score: (0, 1)),
            TestData.fixture(5, b, c, "2025-09-13T14:00:00Z", score: (4, 0)),
        ]
        let late = TestData.date("2026-01-01T00:00:00Z")
        let laLiga = StandingsCalculator(rule: .headToHeadFirst).table(fixtures: fixtures, before: late)
        let pl = StandingsCalculator(rule: .premierLeague).table(fixtures: fixtures, before: late)
        #expect(laLiga.first?.team.id == 1)  // head-to-head
        #expect(pl.first?.team.id == 2)  // goal difference
        // After only one meeting, La Liga falls back to goal difference.
        let early = StandingsCalculator(rule: .headToHeadFirst).table(
            fixtures: Array(fixtures.prefix(3)) + [TestData.fixture(5, b, c, "2025-09-13T14:00:00Z", score: (4, 0))],
            before: late)
        #expect(early.first?.team.id == 2)
    }

    @Test func deductionsReducePoints() {
        let a = TestData.team(1, "Alpha"), b = TestData.team(2, "Bravo")
        let fixtures = [TestData.fixture(1, a, b, "2025-08-16T14:00:00Z", score: (1, 0))]
        let table = StandingsCalculator(rule: .premierLeague).table(
            fixtures: fixtures, before: TestData.date("2026-01-01T00:00:00Z"), deductions: [1: 6])
        #expect(table.first { $0.team.id == 1 }?.points == -3)
        #expect(table.first?.team.id == 2)
    }

    @Test func knockoutMatchesAreIgnored() {
        let fixtures = TestData.fixtures("CL", competitionId: "UCL")
        let table = StandingsCalculator(rule: .ucl).table(fixtures: fixtures, before: TestData.date("2026-12-01T00:00:00Z"))
        #expect(table.count == 36)
        #expect(table.allSatisfy { $0.played == 8 })
    }
}

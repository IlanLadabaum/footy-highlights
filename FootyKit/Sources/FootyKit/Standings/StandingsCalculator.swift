import Foundation

public struct TableRow: Hashable, Sendable, Identifiable {
    public var team: Team
    public var position: Int
    public var played: Int
    public var won: Int
    public var drawn: Int
    public var lost: Int
    public var goalsFor: Int
    public var goalsAgainst: Int
    public var awayGoalsFor: Int
    public var awayWins: Int
    /// Points deducted (subtracted from `points`). 0 unless deductions are applied.
    public var deduction: Int

    public var id: Int { team.id }
    public var goalDifference: Int { goalsFor - goalsAgainst }
    public var points: Int { won * 3 + drawn - deduction }

    init(team: Team) {
        self.team = team
        position = 0
        played = 0
        won = 0
        drawn = 0
        lost = 0
        goalsFor = 0
        goalsAgainst = 0
        awayGoalsFor = 0
        awayWins = 0
        deduction = 0
    }
}

/// Builds league tables from results, so the table can be shown "as it stood" at any point
/// and revealed results can be applied one by one. Football-data's own historical tables are
/// computed the same way (results only).
public struct StandingsCalculator: Sendable {
    let rule: TiebreakRule
    let sortName: @Sendable (Team) -> String

    public init(rule: TiebreakRule, sortName: @escaping @Sendable (Team) -> String = { $0.shortName }) {
        self.rule = rule
        self.sortName = sortName
    }

    /// League-phase/regular-season fixtures only. `cutoff`: matches kicking off before it count.
    /// `revealed`: extra fixtures (from the round being viewed) to apply on top.
    public func table(
        fixtures: [Fixture], before cutoff: Date, applying revealed: Set<Int> = [], deductions: [Int: Int] = [:]
    ) -> [TableRow] {
        let league = fixtures.filter { !$0.isKnockout }
        var rows: [Int: TableRow] = [:]
        for fixture in league {
            rows[fixture.home.id] = rows[fixture.home.id] ?? TableRow(team: fixture.home)
            rows[fixture.away.id] = rows[fixture.away.id] ?? TableRow(team: fixture.away)
        }
        let counted = league.filter { fixture in
            fixture.score != nil && fixture.status.isFinal && (fixture.utcDate < cutoff || revealed.contains(fixture.id))
        }
        for fixture in counted { Self.apply(fixture, to: &rows) }
        for (teamId, points) in deductions where rows[teamId] != nil { rows[teamId]!.deduction = points }

        var ordered = order(Array(rows.values), steps: steps, matches: counted)
        for index in ordered.indices { ordered[index].position = index + 1 }
        return ordered
    }

    static func apply(_ fixture: Fixture, to rows: inout [Int: TableRow]) {
        guard let goals = fixture.score?.goals else { return }
        var home = rows[fixture.home.id]!
        var away = rows[fixture.away.id]!
        home.played += 1
        away.played += 1
        home.goalsFor += goals.home
        home.goalsAgainst += goals.away
        away.goalsFor += goals.away
        away.goalsAgainst += goals.home
        away.awayGoalsFor += goals.away
        if goals.home > goals.away {
            home.won += 1
            away.lost += 1
        } else if goals.home < goals.away {
            away.won += 1
            away.awayWins += 1
            home.lost += 1
        } else {
            home.drawn += 1
            away.drawn += 1
        }
        rows[fixture.home.id] = home
        rows[fixture.away.id] = away
    }

    // MARK: - Tiebreakers

    enum Step {
        case points, goalDifference, goalsFor, awayGoals, wins, awayWins
        /// Head-to-head among the tied teams. `requireComplete`: only once every pair has met home and away.
        case h2hPoints(requireComplete: Bool)
        case h2hGoalDifference(requireComplete: Bool)
        case h2hGoalsFor
        case h2hAwayGoals
    }

    var steps: [Step] {
        switch rule {
        case .premierLeague:
            [.points, .goalDifference, .goalsFor, .h2hPoints(requireComplete: false), .h2hAwayGoals]
        case .headToHeadFirst:
            [.points, .h2hPoints(requireComplete: true), .h2hGoalDifference(requireComplete: true), .goalDifference,
             .goalsFor]
        case .bundesliga:
            [.points, .goalDifference, .goalsFor, .h2hPoints(requireComplete: false), .h2hAwayGoals, .awayGoals]
        case .ligue1:
            [.points, .goalDifference, .h2hPoints(requireComplete: false), .h2hGoalDifference(requireComplete: false),
             .h2hGoalsFor, .goalsFor]
        case .ucl:
            [.points, .goalDifference, .goalsFor, .awayGoals, .wins, .awayWins]
        }
    }

    /// Sort by the first step, split ties into groups and resolve each group with the remaining steps
    /// (head-to-head steps are computed among the group's teams only). Final fallback: name.
    func order(_ rows: [TableRow], steps: [Step], matches: [Fixture]) -> [TableRow] {
        guard rows.count > 1 else { return rows }
        guard let step = steps.first else {
            return rows.sorted { sortName($0.team).localizedCompare(sortName($1.team)) == .orderedAscending }
        }
        let values = value(of: step, for: rows, matches: matches)
        let sorted = rows.sorted { values[$0.id]! > values[$1.id]! }
        var result: [TableRow] = []
        var group: [TableRow] = []
        for row in sorted {
            if let last = group.last, values[last.id] != values[row.id] {
                result += order(group, steps: Array(steps.dropFirst()), matches: matches)
                group = []
            }
            group.append(row)
        }
        result += order(group, steps: Array(steps.dropFirst()), matches: matches)
        return result
    }

    private func value(of step: Step, for rows: [TableRow], matches: [Fixture]) -> [Int: Int] {
        func each(_ body: (TableRow) -> Int) -> [Int: Int] {
            Dictionary(uniqueKeysWithValues: rows.map { ($0.id, body($0)) })
        }
        switch step {
        case .points: return each(\.points)
        case .goalDifference: return each(\.goalDifference)
        case .goalsFor: return each(\.goalsFor)
        case .awayGoals: return each(\.awayGoalsFor)
        case .wins: return each(\.won)
        case .awayWins: return each(\.awayWins)
        case .h2hPoints(let complete), .h2hGoalDifference(let complete):
            let mini = headToHead(rows, matches: matches, requireComplete: complete)
            guard let mini else { return each { _ in 0 } }
            if case .h2hPoints = step { return mini.mapValues(\.points) }
            return mini.mapValues(\.goalDifference)
        case .h2hGoalsFor:
            return (headToHead(rows, matches: matches, requireComplete: false) ?? [:]).mapValues(\.goalsFor)
                .merging(each { _ in 0 }) { first, _ in first }
        case .h2hAwayGoals:
            return (headToHead(rows, matches: matches, requireComplete: false) ?? [:]).mapValues(\.awayGoalsFor)
                .merging(each { _ in 0 }) { first, _ in first }
        }
    }

    /// Mini-table of matches among `rows`' teams. Nil when `requireComplete` and some pair hasn't met twice.
    private func headToHead(_ rows: [TableRow], matches: [Fixture], requireComplete: Bool) -> [Int: TableRow]? {
        let ids = Set(rows.map(\.id))
        let mutual = matches.filter { ids.contains($0.home.id) && ids.contains($0.away.id) }
        if requireComplete, mutual.count < ids.count * (ids.count - 1) { return nil }
        var mini = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, TableRow(team: $0.team)) })
        for fixture in mutual { Self.apply(fixture, to: &mini) }
        return mini
    }
}

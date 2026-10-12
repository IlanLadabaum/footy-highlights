import Foundation

public struct RoundID: Hashable, Sendable, Codable {
    public var competitionId: String
    /// "md:<stage>:<matchday>", "title:<round>" or "date:<yyyy-MM-dd>".
    public var key: String

    public init(competitionId: String, key: String) {
        self.competitionId = competitionId
        self.key = key
    }
}

/// What a match row can offer the user.
public enum Availability: Hashable, Sendable {
    /// A highlight video plays in the app.
    case playable
    /// Played, but no in-app highlight exists.
    case noHighlights
    /// Played recently; the highlight usually appears within a day or two.
    case highlightsPending
    case inProgress
    case upcoming(Date)
    /// Postponed, cancelled or suspended (not a result spoiler).
    case notPlayed(MatchStatus)
}

public struct MatchEntry: Identifiable, Hashable, Sendable {
    public var id: MatchKey
    public var competitionId: String
    public var roundId: RoundID
    public var fixture: Fixture?
    /// The video played in the app (extended cut preferred).
    public var video: Video?
    /// Non-embeddable video offered only as "Open on YouTube (may show score)".
    public var browserFallbackVideo: Video?
    public var homeName: String
    public var awayName: String
    /// Teams + competition + round where known. Never the original title.
    public var neutralTitle: String
    /// Kickoff for fixtures, publish time for videos without one.
    public var date: Date
    public var flags: MatchFlags
    /// Every match key whose flags feed this entry (fixture + any video keys), so updates stay consistent.
    public var flagKeys: [MatchKey]
    public var availability: Availability
    public var channelName: String?
    /// The video's channel sometimes puts spoilers in its titles, which can flash in the player.
    public var spoilerProneTitle: Bool
    /// For a second leg: the first-leg fixture and whether its score may be shown.
    public var firstLeg: FirstLegInfo?

    public var isPlayable: Bool { availability == .playable && video != nil }
    public var isUnwatched: Bool { isPlayable && !flags.watched }
    /// The score may be shown (the user revealed it). Watching alone doesn't show it in the list.
    public var scoreVisible: Bool { flags.revealed && fixture?.score != nil }
}

public struct FirstLegInfo: Hashable, Sendable {
    public var fixture: Fixture
    public var homeName: String
    public var awayName: String
    public var flags: MatchFlags
    /// Shown automatically once the first leg is watched or revealed.
    public var scoreVisible: Bool { (flags.watched || flags.revealed) && fixture.score != nil }
}

public enum RoundLayout: Hashable, Sendable {
    /// League-style round with fixture data: fixtures beside the pre-round table.
    case withTable
    /// League-style round without a football-data key: greyed "add key" panel.
    case tableNeedsKey
    /// Cups and knockout rounds: fixtures use the full width.
    case fullWidth
}

public struct Round: Identifiable, Hashable, Sendable {
    public var id: RoundID
    public var name: String
    public var start: Date
    public var end: Date
    public var matches: [MatchEntry]
    public var layout: RoundLayout
    /// Fixture-based rounds: the earliest kickoff of the round's main block of dates (the "before the round"
    /// cut-off for the table). A match brought forward weeks earlier counts as already played.
    public var earliestKickoff: Date?

    public var unwatchedCount: Int { matches.filter(\.isUnwatched).count }
    public var playableCount: Int { matches.filter(\.isPlayable).count }
}

public struct CompetitionSummary: Identifiable, Hashable, Sendable {
    public var config: CompetitionConfig
    /// Newest first.
    public var rounds: [Round]
    public var usesFixtureData: Bool

    public var id: String { config.id }
    public var unwatchedCount: Int { rounds.reduce(0) { $0 + $1.unwatchedCount } }
}

public struct Library: Hashable, Sendable {
    /// In priority order.
    public var competitions: [CompetitionSummary]
    /// All fixtures by competition, for standings.
    public var fixturesByCompetition: [String: [Fixture]]

    public static let empty = Library(competitions: [], fixturesByCompetition: [:])

    /// "New stuff to watch" section, then "Nothing new"; priority order within each.
    public var newStuff: [CompetitionSummary] { competitions.filter { $0.unwatchedCount > 0 } }
    public var nothingNew: [CompetitionSummary] { competitions.filter { $0.unwatchedCount == 0 } }

    public func competition(_ id: String) -> CompetitionSummary? { competitions.first { $0.id == id } }

    public func round(_ id: RoundID) -> Round? {
        competition(id.competitionId)?.rounds.first { $0.id == id }
    }
}

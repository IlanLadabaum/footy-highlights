import Foundation

public struct Team: Codable, Hashable, Sendable {
    public var id: Int
    public var name: String
    public var shortName: String
    public var tla: String

    public init(id: Int, name: String, shortName: String, tla: String) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.tla = tla
    }
}

public enum MatchStatus: String, Codable, Sendable {
    case scheduled = "SCHEDULED"
    case timed = "TIMED"
    case inPlay = "IN_PLAY"
    case paused = "PAUSED"
    case extraTime = "EXTRA_TIME"
    case penaltyShootout = "PENALTY_SHOOTOUT"
    case finished = "FINISHED"
    case suspended = "SUSPENDED"
    case postponed = "POSTPONED"
    case cancelled = "CANCELLED"
    case awarded = "AWARDED"
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MatchStatus(rawValue: raw) ?? .unknown
    }

    /// The match has a final result ("No highlights available" applies only to these).
    public var isFinal: Bool { self == .finished || self == .awarded }
    public var isLive: Bool { [.inPlay, .paused, .extraTime, .penaltyShootout].contains(self) }
    public var isUpcoming: Bool { self == .scheduled || self == .timed }
}

public struct ScorePair: Codable, Hashable, Sendable {
    public var home: Int
    public var away: Int

    public init(home: Int, away: Int) {
        self.home = home
        self.away = away
    }
}

/// A final result. Never displayed unless the user has watched or revealed the match.
public struct MatchScore: Codable, Hashable, Sendable {
    public enum Duration: String, Codable, Sendable {
        case regular = "REGULAR"
        case extraTime = "EXTRA_TIME"
        case penaltyShootout = "PENALTY_SHOOTOUT"
    }

    /// Goals at the end of play (after extra time if played), excluding shoot-out penalties.
    public var goals: ScorePair
    public var penalties: ScorePair?
    public var duration: Duration

    public init(goals: ScorePair, penalties: ScorePair? = nil, duration: Duration = .regular) {
        self.goals = goals
        self.penalties = penalties
        self.duration = duration
    }

    /// e.g. "2–1", "1–1 a.e.t.", "1–1 a.e.t., 4–3 pens".
    public var display: String {
        var text = "\(goals.home)–\(goals.away)"
        switch duration {
        case .regular: break
        case .extraTime: text += " a.e.t."
        case .penaltyShootout:
            text += " a.e.t."
            if let penalties { text += ", \(penalties.home)–\(penalties.away) pens" }
        }
        return text
    }
}

public struct Fixture: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var competitionId: String
    public var season: Int
    public var utcDate: Date
    public var status: MatchStatus
    /// football-data stage, e.g. REGULAR_SEASON, LEAGUE_STAGE, LAST_16.
    public var stage: String
    /// Matchday for leagues; leg number (1/2) for knockout stages; nil for finals.
    public var matchday: Int?
    public var home: Team
    public var away: Team
    public var score: MatchScore?

    public init(
        id: Int, competitionId: String, season: Int, utcDate: Date, status: MatchStatus, stage: String,
        matchday: Int?, home: Team, away: Team, score: MatchScore?
    ) {
        self.id = id
        self.competitionId = competitionId
        self.season = season
        self.utcDate = utcDate
        self.status = status
        self.stage = stage
        self.matchday = matchday
        self.home = home
        self.away = away
        self.score = score
    }

    public var isKnockout: Bool {
        !["REGULAR_SEASON", "LEAGUE_STAGE", "GROUP_STAGE"].contains(stage)
    }
}

/// A highlight video from YouTube. The original title is kept only for parsing and the
/// explicit "show original title" action; the app's list never shows it by default.
public struct Video: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var channelKey: String
    public var originalTitle: String
    public var publishedAt: Date
    public var durationSeconds: Int?

    public init(id: String, channelKey: String, originalTitle: String, publishedAt: Date, durationSeconds: Int? = nil) {
        self.id = id
        self.channelKey = channelKey
        self.originalTitle = originalTitle
        self.publishedAt = publishedAt
        self.durationSeconds = durationSeconds
    }
}

/// Per-match user state. Keyed by fixture ID when the match is known, otherwise by video ID.
public struct MatchFlags: Codable, Hashable, Sendable {
    public var watched: Bool
    public var revealed: Bool

    public init(watched: Bool = false, revealed: Bool = false) {
        self.watched = watched
        self.revealed = revealed
    }
}

public enum MatchKey: Hashable, Sendable, Codable, CustomStringConvertible {
    case fixture(Int)
    case video(String)

    public var description: String {
        switch self {
        case .fixture(let id): "f:\(id)"
        case .video(let id): "v:\(id)"
        }
    }

    public init?(string: String) {
        if string.hasPrefix("f:"), let id = Int(string.dropFirst(2)) {
            self = .fixture(id)
        } else if string.hasPrefix("v:") {
            self = .video(String(string.dropFirst(2)))
        } else {
            return nil
        }
    }
}

public enum Season {
    /// The season that `date` belongs to, named by its starting year (2026 = 2026-27). Seasons roll over on 1 July.
    public static func year(containing date: Date, calendar: Calendar = .utc) -> Int {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return comps.month! >= 7 ? comps.year! : comps.year! - 1
    }

    /// How far back the YouTube scan goes for a season: 1 August of its starting year (UTC).
    public static func scanCutoff(forSeason season: Int) -> Date {
        Calendar.utc.date(from: DateComponents(year: season, month: 8, day: 1))!
    }
}

extension Calendar {
    public static let utc: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()
}

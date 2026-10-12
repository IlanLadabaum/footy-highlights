import Foundation

/// Static configuration: which competitions exist, where their highlights come from and how
/// to read the titles. Loaded from `competitions.json`, so adding a competition is a config change.
public struct AppConfig: Codable, Sendable {
    public var channels: [String: ChannelConfig]
    public var competitions: [CompetitionConfig]
    /// football-data `shortName` → name shown in the app (e.g. "Nottingham" → "Nottingham Forest").
    public var teamDisplayNames: [String: String]
    /// Normalised alias → normalised canonical name, used when matching video titles to fixtures.
    public var teamAliases: [String: String]

    public static func bundled() -> AppConfig {
        guard let url = Bundle.module.url(forResource: "competitions", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else { fatalError("competitions.json missing from FootyKit resources") }
        do {
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            fatalError("competitions.json is invalid: \(error)")
        }
    }

    public func competition(id: String) -> CompetitionConfig? {
        competitions.first { $0.id == id }
    }

    public var competitionsByPriority: [CompetitionConfig] {
        competitions.sorted { $0.priority < $1.priority }
    }
}

public struct ChannelConfig: Codable, Sendable, Hashable {
    public var channelId: String
    public var name: String
    /// Regex with named groups `home`, `away` and optionally `label` (the competition/round part).
    public var titlePattern: String
    /// If set, titles matching this are the extended cut. If nil, every match from this channel counts as one version.
    public var extendedPattern: String?
    /// The channel's original titles can contain spoilers (teasers or scores). They can flash in the player.
    public var spoilerProneTitles: Bool?
    /// Strip teaser prefixes like "LATE DRAMA ‼️ " from the home-team part.
    public var stripTeaserPrefix: Bool?

    public var uploadsPlaylistId: String { "UU" + channelId.dropFirst(2) }
}

public enum SourceRole: String, Codable, Sendable {
    /// Plays in the app.
    case primary
    /// Can't be embedded; only offered as "Open on YouTube (may show score)" for matches without a primary video.
    case browserFallback
}

public struct SourceConfig: Codable, Sendable, Hashable {
    /// Key into `AppConfig.channels`.
    public var channel: String
    /// Regex applied to the title's `label` group. It may capture a `round` group. Nil = accept every parsed title.
    public var label: String?
    public var role: SourceRole?

    public var effectiveRole: SourceRole { role ?? .primary }
}

public enum RoundStyle: String, Codable, Sendable {
    case league
    case ucl
}

public enum TiebreakRule: String, Codable, Sendable {
    /// Points, goal difference, goals for, then head-to-head.
    case premierLeague
    /// Points, head-to-head (once the teams have met twice), then goal difference, goals for (La Liga, Serie A).
    case headToHeadFirst
    /// Points, goal difference, goals for, head-to-head, away goals.
    case bundesliga
    /// Points, goal difference, head-to-head, goals for.
    case ligue1
    /// Points, goal difference, goals for, away goals, wins, away wins (UCL league phase).
    case ucl
}

public struct CompetitionConfig: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var priority: Int
    /// Nil when football-data's free tier doesn't cover the competition (always uses the no-key behaviour).
    public var footballDataCode: String?
    public var roundStyle: RoundStyle?
    public var roundNoun: String?
    public var tiebreak: TiebreakRule?
    public var isCup: Bool?
    public var sources: [SourceConfig]

    public var effectiveRoundStyle: RoundStyle { roundStyle ?? .league }
    public var cup: Bool { isCup ?? false }
}

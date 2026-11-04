import Foundation

/// Team-name normalisation, aliasing and display names.
public struct TeamNames: Sendable {
    /// Club-form words that carry no identity ("FC", "Calcio", founding years…).
    static let noiseTokens: Set<String> = [
        "fc", "afc", "cf", "sc", "ac", "as", "ssc", "us", "cd", "ud", "rcd", "sv", "acf", "bc", "cfc", "osc",
        "calcio", "futbol", "balompie", "de", "the", "and", "club", "1", "04", "05", "07", "29", "1899", "1901",
        "1907", "1909", "1913", "fsv", "tsg", "sco", "ogc", "aj", "es", "hac", "kv",
    ]
    /// Tokens too common to identify a team on their own ("Real", "United"…).
    static let genericTokens: Set<String> = [
        "real", "united", "city", "athletic", "atletico", "sporting", "racing", "olympique", "stade", "inter",
        "borussia", "eintracht", "hotspur", "town", "wanderers", "albion", "rovers", "county", "paris", "red",
        "bull", "saint", "st", "fk", "sk", "madrid", "milan", "milano", "rc", "nk", "ca", "vfl", "vfb", "manchester",
        "man", "sheffield", "bayer", "dynamo", "lisboa", "clube", "olympiakos",
    ]

    public let aliases: [String: String]
    public let displayOverrides: [String: String]

    public init(config: AppConfig) {
        var aliases: [String: String] = [:]
        for (alias, canonical) in config.teamAliases {
            aliases[Self.normalize(alias)] = Self.normalize(canonical)
        }
        self.aliases = aliases
        self.displayOverrides = config.teamDisplayNames
    }

    /// Lowercase, strip accents and punctuation, drop noise tokens: "1. FC Köln" → "koln".
    public static func normalize(_ raw: String) -> String {
        tokens(raw).joined(separator: " ")
    }

    static func tokens(_ raw: String) -> [String] {
        let folded = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
            .lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "ø", with: "o")
            .replacingOccurrences(of: "ß", with: "ss")
        let parts = folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let kept = parts.filter { !noiseTokens.contains($0) }
        return kept.isEmpty ? parts : kept
    }

    /// The name shown in the app: football-data's short name, with a few readability overrides.
    public func displayName(for team: Team) -> String {
        displayOverrides[team.shortName] ?? team.shortName
    }

    /// Every normalised form a fixture team can be recognised by.
    func candidateNames(for team: Team) -> Set<String> {
        var names: Set<String> = [Self.normalize(team.name), Self.normalize(team.shortName)]
        if let display = displayOverrides[team.shortName] { names.insert(Self.normalize(display)) }
        return names.filter { !$0.isEmpty }
    }

    /// How well a team name parsed from a video title matches a fixture team. 0 = no match.
    /// 3 = exact (after normalisation/aliasing), 2 = one name's distinctive words contain the other's.
    public func matchScore(videoName: String, team: Team) -> Int {
        let raw = Self.normalize(videoName)
        guard !raw.isEmpty else { return 0 }
        let videoForms: Set<String> = [raw, aliases[raw]].compactMap { $0 }.reduce(into: []) { $0.insert($1) }
        let teamForms = candidateNames(for: team)
        if !videoForms.isDisjoint(with: teamForms) { return 3 }
        // Alias applied to a team's own name too (e.g. "Bayern" short name vs "bayern munchen").
        if teamForms.contains(where: { aliases[$0].map(videoForms.contains) ?? false }) { return 3 }

        var best = 0
        for videoForm in videoForms {
            let videoTokens = Set(videoForm.split(separator: " ").map(String.init))
            for teamForm in teamForms {
                let teamTokens = Set(teamForm.split(separator: " ").map(String.init))
                let shared = videoTokens.intersection(teamTokens)
                guard !shared.isEmpty, !shared.isSubset(of: Self.genericTokens) else { continue }
                if videoTokens.isSubset(of: teamTokens) || teamTokens.isSubset(of: videoTokens) {
                    best = max(best, 2)
                } else if Double(shared.count) / Double(max(videoTokens.count, teamTokens.count)) >= 0.5 {
                    best = max(best, 1)
                }
            }
        }
        return best
    }

    /// Whether a free-form title names the team (any of its names or aliases, as whole words).
    public func mentions(_ text: String, team: Team) -> Bool {
        let words = Self.tokens(text)
        var forms = candidateNames(for: team)
        for (alias, canonical) in aliases where forms.contains(canonical) { forms.insert(alias) }
        return forms.contains { form in
            let phrase = form.split(separator: " ").map(String.init)
            guard !phrase.isEmpty, phrase.count <= words.count else { return false }
            return (0...(words.count - phrase.count)).contains { Array(words[$0..<$0 + phrase.count]) == phrase }
        }
    }

    /// Tidy a team name parsed from a title for display when there's no fixture: trims and drops trailing "(edited)".
    public static func cleanParsed(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasSuffix(".") { name.removeLast() }
        return name
    }
}

import Foundation

/// What the app reads out of an original YouTube title. Scores are never extracted.
public struct ParsedTitle: Hashable, Sendable {
    public var competitionId: String
    public var role: SourceRole
    public var home: String
    public var away: String
    /// Round text from the title when the channel includes one (e.g. "League Phase MD 1", "Third Round").
    public var titleRound: String?
    public var isExtended: Bool
    /// For channels matched by the teams a free-form title mentions: the title to search (home/away are empty).
    public var mentionText: String?
}

/// Classifies a video into a competition and pulls out the team names, using the per-channel
/// patterns in `competitions.json`. Titles that don't match any pattern aren't match highlights.
public struct TitleParser: Sendable {
    struct Rule: Sendable {
        var competitionId: String
        var role: SourceRole
        var title: NSRegularExpression
        var label: NSRegularExpression?
        var extended: NSRegularExpression?
        var stripTeaser: Bool
        var byMentions: Bool
    }

    let rulesByChannel: [String: [Rule]]

    public init(config: AppConfig) {
        var rules: [String: [Rule]] = [:]
        for competition in config.competitionsByPriority {
            for source in competition.sources {
                guard let channel = config.channels[source.channel] else {
                    assertionFailure("Unknown channel \(source.channel)")
                    continue
                }
                let rule = Rule(
                    competitionId: competition.id,
                    role: source.effectiveRole,
                    title: Self.regex(channel.titlePattern),
                    label: source.label.map(Self.regex),
                    extended: channel.extendedPattern.map(Self.regex),
                    stripTeaser: channel.stripTeaserPrefix ?? false,
                    byMentions: channel.matchByMentions ?? false
                )
                rules[source.channel, default: []].append(rule)
            }
        }
        rulesByChannel = rules
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are bundled config (covered by tests); a bad one is a programming error.
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    public func parse(title: String, channelKey: String) -> ParsedTitle? {
        // Channels sometimes use non-breaking or doubled spaces.
        let title = title.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        for rule in rulesByChannel[channelKey] ?? [] {
            if rule.byMentions {
                guard rule.title.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil
                else { continue }
                return ParsedTitle(
                    competitionId: rule.competitionId, role: rule.role, home: "", away: "", titleRound: nil,
                    isExtended: false, mentionText: title)
            }
            guard let match = rule.title.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
                var home = Self.group("home", match, title),
                let away = Self.group("away", match, title)
            else { continue }

            var round: String?
            if let labelRegex = rule.label {
                guard let label = Self.group("label", match, title),
                    let labelMatch = labelRegex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label))
                else { continue }
                round = Self.group("round", labelMatch, label)?.trimmingCharacters(in: .whitespaces)
                if round?.isEmpty == true { round = nil }
            }
            if rule.stripTeaser { home = Self.stripTeaserPrefix(home) }

            let extended =
                rule.extended.map { $0.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil }
                ?? false
            let cleanedHome = TeamNames.cleanParsed(home)
            let cleanedAway = TeamNames.cleanParsed(away)
            guard !cleanedHome.isEmpty, !cleanedAway.isEmpty else { continue }
            return ParsedTitle(
                competitionId: rule.competitionId, role: rule.role, home: cleanedHome, away: cleanedAway,
                titleRound: round, isExtended: extended)
        }
        return nil
    }

    private static func group(_ name: String, _ match: NSTextCheckingResult, _ string: String) -> String? {
        let range = match.range(withName: name)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: string) else { return nil }
        return String(string[swiftRange])
    }

    /// ESPN FC prefixes some titles with a teaser ("LATE DRAMA ‼️ Sevilla vs. …"). Keep only the team.
    static func stripTeaserPrefix(_ text: String) -> String {
        // 1. Anything up to the last emoji/symbol run.
        if let lastSymbol = text.lastIndex(where: { $0.isTeaserSymbol }) {
            let rest = text[text.index(after: lastSymbol)...].trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { return rest }
        }
        // 2. A leading run of ALL-CAPS words followed by a normal-case word.
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        var firstNormal = 0
        while firstNormal < words.count, words[firstNormal].isAllCapsWord { firstNormal += 1 }
        if firstNormal >= 2, firstNormal < words.count {
            return words[firstNormal...].joined(separator: " ")
        }
        return text
    }
}

extension Character {
    fileprivate var isTeaserSymbol: Bool {
        unicodeScalars.contains { scalar in
            (scalar.properties.isEmoji && scalar.value > 0x238C) || scalar.value == 0x203C || scalar.value == 0x2049
        }
    }
}

extension Substring {
    fileprivate var isAllCapsWord: Bool {
        let letters = filter(\.isLetter)
        return !letters.isEmpty && letters.allSatisfy(\.isUppercase) || allSatisfy { !$0.isLetter }
    }
}

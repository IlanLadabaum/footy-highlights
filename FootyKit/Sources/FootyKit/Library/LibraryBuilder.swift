import Foundation

/// Pure function from (config, fixtures, videos, flags) to the screens' data. No I/O, fully testable.
public struct LibraryBuilder: Sendable {
    /// After this long without a video, a finished match shows "No highlights available" instead of "not yet".
    public static let highlightGrace: TimeInterval = 36 * 3600

    let config: AppConfig
    let names: TeamNames
    let parser: TitleParser
    let matcher: FixtureMatcher
    let calendar: Calendar

    public init(config: AppConfig, calendar: Calendar = .current) {
        self.config = config
        self.names = TeamNames(config: config)
        self.parser = TitleParser(config: config)
        self.matcher = FixtureMatcher(names: names)
        self.calendar = calendar
    }

    public func build(
        fixtures: [Fixture], videos: [Video], flags: [MatchKey: MatchFlags], now: Date = Date()
    ) -> Library {
        let fixturesByCompetition = Dictionary(grouping: fixtures, by: \.competitionId)
        var parsedByCompetition: [String: [(Video, ParsedTitle)]] = [:]
        for video in videos {
            if let parsed = parser.parse(title: video.originalTitle, channelKey: video.channelKey) {
                parsedByCompetition[parsed.competitionId, default: []].append((video, parsed))
            }
        }

        let summaries = config.competitionsByPriority.map { competition in
            let compFixtures = competition.footballDataCode == nil ? [] : (fixturesByCompetition[competition.id] ?? [])
            let parsed = parsedByCompetition[competition.id] ?? []
            let rounds =
                compFixtures.isEmpty
                ? videoOnlyRounds(competition: competition, parsed: parsed, flags: flags)
                : fixtureRounds(competition: competition, fixtures: compFixtures, parsed: parsed, flags: flags, now: now)
            return CompetitionSummary(
                config: competition,
                rounds: rounds.sorted { $0.start > $1.start },
                usesFixtureData: !compFixtures.isEmpty)
        }
        return Library(competitions: summaries, fixturesByCompetition: fixturesByCompetition)
    }

    // MARK: - With fixture data

    /// Everything a fixture-based round needs to build its entries.
    struct FixtureContext {
        var competition: CompetitionConfig
        var fixtures: [Fixture]
        var primaryByFixture: [Int: [Video]]
        var fallbackByFixture: [Int: [Video]]
        var extendedIds: Set<String>
        var flags: [MatchKey: MatchFlags]
        var now: Date
    }

    private func fixtureRounds(
        competition: CompetitionConfig, fixtures: [Fixture], parsed: [(Video, ParsedTitle)],
        flags: [MatchKey: MatchFlags], now: Date
    ) -> [Round] {
        var primaryByFixture: [Int: [Video]] = [:]
        var fallbackByFixture: [Int: [Video]] = [:]
        var extendedIds: Set<String> = []
        var unmatched: [(Video, ParsedTitle)] = []
        for (video, title) in parsed {
            if title.isExtended { extendedIds.insert(video.id) }
            guard let fixture = matcher.match(home: title.home, away: title.away, publishedAt: video.publishedAt, in: fixtures)
            else {
                if title.role == .primary { unmatched.append((video, title)) }
                continue
            }
            switch title.role {
            case .primary: primaryByFixture[fixture.id, default: []].append(video)
            case .browserFallback: fallbackByFixture[fixture.id, default: []].append(video)
            }
        }

        let context = FixtureContext(
            competition: competition, fixtures: fixtures, primaryByFixture: primaryByFixture,
            fallbackByFixture: fallbackByFixture, extendedIds: extendedIds, flags: flags, now: now)
        let groups = Dictionary(grouping: fixtures) { roundKey(for: $0) }
        var rounds: [Round] = []
        for (key, roundFixtures) in groups {
            // Only rounds that have started (or have a highlight) are listed.
            let started = roundFixtures.contains { $0.utcDate <= now || primaryByFixture[$0.id] != nil }
            guard started else { continue }
            let roundId = RoundID(competitionId: competition.id, key: key)
            let name = roundName(competition: competition, fixture: roundFixtures[0])
            let entries = roundFixtures.sorted { ($0.utcDate, $0.id) < ($1.utcDate, $1.id) }.map { fixture in
                fixtureEntry(fixture, roundId: roundId, roundName: name, context: context)
            }
            let cluster = Self.mainCluster(roundFixtures.map(\.utcDate))
            let leagueStage = roundFixtures.allSatisfy { !$0.isKnockout }
            rounds.append(
                Round(
                    id: roundId, name: name, start: cluster.lowerBound, end: cluster.upperBound, matches: entries,
                    layout: leagueStage && !competition.cup ? .withTable : .fullWidth,
                    earliestKickoff: cluster.lowerBound))
        }

        // Videos that couldn't be matched still show (teams from the title, no round in the name),
        // unless neither team plays in this competition: that's a channel mislabelling another league's video.
        let seasonTeams = Array(Set(fixtures.flatMap { [$0.home, $0.away] }))
        let plausible = unmatched.filter { _, title in
            [title.home, title.away].contains { name in
                seasonTeams.contains { names.matchScore(videoName: name, team: $0) >= 2 }
            }
        }
        for (video, title) in dedupe(plausible) {
            let entry = videoEntry(video, title, competition: competition, roundId: nil, titleRoundName: nil, flags: flags)
            if let index = bestRoundIndex(for: video.publishedAt, in: rounds) {
                var round = rounds[index]
                var placed = entry
                placed.roundId = round.id
                round.matches.append(placed)
                rounds[index] = round
            } else {
                let window = dateWindow(for: video.publishedAt)
                let id = RoundID(competitionId: competition.id, key: "date:\(dayKey(window.start))")
                var placed = entry
                placed.roundId = id
                if let index = rounds.firstIndex(where: { $0.id == id }) {
                    rounds[index].matches.append(placed)
                    rounds[index].end = max(rounds[index].end, video.publishedAt)
                } else {
                    rounds.append(
                        Round(
                            id: id, name: window.name, start: video.publishedAt, end: video.publishedAt,
                            matches: [placed], layout: .fullWidth, earliestKickoff: nil))
                }
            }
        }
        // Chronological top to bottom (unmatched videos were appended above).
        for index in rounds.indices { rounds[index].matches.sort { $0.date < $1.date } }
        return rounds
    }

    private func fixtureEntry(_ fixture: Fixture, roundId: RoundID, roundName: String, context: FixtureContext)
        -> MatchEntry
    {
        let competition = context.competition
        let flags = context.flags
        let now = context.now
        let videos = context.primaryByFixture[fixture.id] ?? []
        let fallbacks = context.fallbackByFixture[fixture.id] ?? []
        let video = preferred(videos, extendedIds: context.extendedIds)
        let keys = [MatchKey.fixture(fixture.id)] + videos.map { MatchKey.video($0.id) }
        let availability: Availability
        if video != nil {
            availability = .playable
        } else if fixture.status.isFinal {
            availability = now.timeIntervalSince(fixture.utcDate) < Self.highlightGrace ? .highlightsPending : .noHighlights
        } else if fixture.status.isLive {
            availability = .inProgress
        } else if fixture.status.isUpcoming {
            availability = fixture.utcDate < now ? .inProgress : .upcoming(fixture.utcDate)
        } else {
            availability = .notPlayed(fixture.status)
        }
        let home = names.displayName(for: fixture.home)
        let away = names.displayName(for: fixture.away)
        let channel = video.flatMap { config.channels[$0.channelKey] }
        return MatchEntry(
            id: .fixture(fixture.id), competitionId: competition.id, roundId: roundId, fixture: fixture, video: video,
            browserFallbackVideo: video == nil ? fallbacks.max { $0.publishedAt < $1.publishedAt } : nil,
            homeName: home, awayName: away,
            neutralTitle: "\(home) v \(away) · \(competition.name) · \(roundName)",
            date: fixture.utcDate, flags: merged(keys, flags), flagKeys: keys, availability: availability,
            channelName: channel?.name, spoilerProneTitle: channel?.spoilerProneTitles ?? false,
            firstLeg: firstLeg(of: fixture, in: context.fixtures, flags: flags))
    }

    private func firstLeg(of fixture: Fixture, in fixtures: [Fixture], flags: [MatchKey: MatchFlags]) -> FirstLegInfo? {
        guard fixture.isKnockout, fixture.matchday == 2 else { return nil }
        guard
            let first = fixtures.first(where: {
                $0.stage == fixture.stage && $0.matchday == 1 && $0.home.id == fixture.away.id
                    && $0.away.id == fixture.home.id
            })
        else { return nil }
        return FirstLegInfo(
            fixture: first, homeName: names.displayName(for: first.home), awayName: names.displayName(for: first.away),
            flags: flags[.fixture(first.id)] ?? MatchFlags())
    }

    private func bestRoundIndex(for date: Date, in rounds: [Round]) -> Int? {
        let candidates = rounds.indices.filter { index in
            guard rounds[index].earliestKickoff != nil else { return false }
            return date >= rounds[index].start.addingTimeInterval(-86_400)
                && date <= rounds[index].end.addingTimeInterval(FixtureMatcher.windowAfterKickoff)
        }
        return candidates.max { rounds[$0].start < rounds[$1].start }
    }

    // MARK: - Without fixture data

    private func videoOnlyRounds(
        competition: CompetitionConfig, parsed: [(Video, ParsedTitle)], flags: [MatchKey: MatchFlags]
    ) -> [Round] {
        var rounds: [RoundID: Round] = [:]
        for (video, title) in dedupe(parsed.filter { $0.1.role == .primary }) {
            let id: RoundID
            let name: String
            let layout: RoundLayout
            if let titleRound = title.titleRound, let pretty = Self.prettyTitleRound(titleRound) {
                id = RoundID(competitionId: competition.id, key: "title:\(TeamNames.normalize(pretty))")
                name = pretty
                let knockout = !pretty.localizedCaseInsensitiveContains("league phase")
                layout = competition.cup || knockout ? .fullWidth : .tableNeedsKey
            } else {
                let window = dateWindow(for: video.publishedAt)
                id = RoundID(competitionId: competition.id, key: "date:\(dayKey(window.start))")
                name = window.name
                layout = competition.cup ? .fullWidth : .tableNeedsKey
            }
            let entry = videoEntry(
                video, title, competition: competition, roundId: id,
                titleRoundName: id.key.hasPrefix("title:") ? name : nil, flags: flags)
            if var round = rounds[id] {
                round.matches.append(entry)
                round.start = min(round.start, video.publishedAt)
                round.end = max(round.end, video.publishedAt)
                rounds[id] = round
            } else {
                rounds[id] = Round(
                    id: id, name: name, start: video.publishedAt, end: video.publishedAt, matches: [entry],
                    layout: layout, earliestKickoff: nil)
            }
        }
        return rounds.values.map { round in
            var round = round
            round.matches.sort { $0.date < $1.date }
            if round.id.key.hasPrefix("date:") { round.name = dateWindowName(start: round.start, end: round.end) }
            return round
        }
    }

    /// `titleRoundName`: the round read from the title, included in the neutral title when present.
    private func videoEntry(
        _ video: Video, _ title: ParsedTitle, competition: CompetitionConfig, roundId: RoundID?, titleRoundName: String?,
        flags: [MatchKey: MatchFlags]
    ) -> MatchEntry {
        let channel = config.channels[video.channelKey]
        let neutral: String
        if title.home.isEmpty || title.away.isEmpty {
            neutral = "\(competition.name) highlight · \(Self.shortDate(video.publishedAt, calendar: calendar))"
        } else if let titleRoundName {
            neutral = "\(title.home) v \(title.away) · \(competition.name) · \(titleRoundName)"
        } else {
            neutral = "\(title.home) v \(title.away) · \(competition.name)"
        }
        let key = MatchKey.video(video.id)
        return MatchEntry(
            id: key, competitionId: competition.id,
            roundId: roundId ?? RoundID(competitionId: competition.id, key: ""), fixture: nil, video: video,
            browserFallbackVideo: nil, homeName: title.home, awayName: title.away, neutralTitle: neutral,
            date: video.publishedAt, flags: flags[key] ?? MatchFlags(), flagKeys: [key], availability: .playable,
            channelName: channel?.name, spoilerProneTitle: channel?.spoilerProneTitles ?? false, firstLeg: nil)
    }

    // MARK: - Helpers

    /// The dates where most of a round is played: within 4 days of the median kickoff. Matches brought
    /// forward or postponed by weeks are left out, so ordering and the "before the round" cut-off follow
    /// the real round (e.g. a matchweek with one game moved to February and one to May).
    static func mainCluster(_ dates: [Date]) -> ClosedRange<Date> {
        let sorted = dates.sorted()
        let median = sorted[sorted.count / 2]
        let inCluster = sorted.filter { abs($0.timeIntervalSince(median)) <= 4 * 86_400 }
        return inCluster.first!...inCluster.last!
    }

    /// One entry per match: collapse uploads of the same pairing within 4 days, keeping the preferred version.
    private func dedupe(_ items: [(Video, ParsedTitle)]) -> [(Video, ParsedTitle)] {
        let extendedIds = Set(items.filter { $0.1.isExtended }.map(\.0.id))
        var groups: [[(Video, ParsedTitle)]] = []
        for item in items.sorted(by: { $0.0.publishedAt < $1.0.publishedAt }) {
            let pair = Set([TeamNames.normalize(item.1.home), TeamNames.normalize(item.1.away)])
            if let index = groups.firstIndex(where: { group in
                let first = group[0]
                return Set([TeamNames.normalize(first.1.home), TeamNames.normalize(first.1.away)]) == pair
                    && item.0.publishedAt.timeIntervalSince(first.0.publishedAt) < 4 * 86_400
            }) {
                groups[index].append(item)
            } else {
                groups.append([item])
            }
        }
        return groups.compactMap { group in
            guard let best = preferred(group.map(\.0), extendedIds: extendedIds) else { return nil }
            return group.first { $0.0.id == best.id }
        }
    }

    /// Extended cut first, then the longest, then the newest.
    private func preferred(_ videos: [Video], extendedIds: Set<String>) -> Video? {
        videos.max { lhs, rhs in
            let left = (extendedIds.contains(lhs.id) ? 1 : 0, lhs.durationSeconds ?? 0, lhs.publishedAt)
            let right = (extendedIds.contains(rhs.id) ? 1 : 0, rhs.durationSeconds ?? 0, rhs.publishedAt)
            return left < right
        }
    }

    private func merged(_ keys: [MatchKey], _ flags: [MatchKey: MatchFlags]) -> MatchFlags {
        keys.reduce(MatchFlags()) { result, key in
            let flag = flags[key] ?? MatchFlags()
            return MatchFlags(watched: result.watched || flag.watched, revealed: result.revealed || flag.revealed)
        }
    }

    func roundKey(for fixture: Fixture) -> String {
        "md:\(fixture.stage):\(fixture.matchday.map(String.init) ?? "-")"
    }

    func roundName(competition: CompetitionConfig, fixture: Fixture) -> String {
        let leg = fixture.isKnockout && fixture.stage != "FINAL" ? fixture.matchday.flatMap(Self.legSuffix) : nil
        let base: String
        switch fixture.stage {
        case "REGULAR_SEASON":
            base = "\(competition.roundNoun ?? "Matchday") \(fixture.matchday ?? 0)"
        case "LEAGUE_STAGE":
            base = "League Phase MD \(fixture.matchday ?? 0)"
        case "PLAYOFFS": base = "Knockout Play-offs"
        case "LAST_32": base = "Round of 32"
        case "LAST_16": base = "Round of 16"
        case "QUARTER_FINALS": base = "Quarter-finals"
        case "SEMI_FINALS": base = "Semi-finals"
        case "FINAL": base = "Final"
        default: base = fixture.stage.replacingOccurrences(of: "_", with: " ").capitalized
        }
        return leg.map { "\(base) · \($0)" } ?? base
    }

    static func legSuffix(_ leg: Int) -> String? {
        switch leg {
        case 1: "1st leg"
        case 2: "2nd leg"
        default: nil
        }
    }

    /// "Round of 16 - Leg 1" → "Round of 16 · 1st leg"; "Third Round" stays; empty → nil.
    static func prettyTitleRound(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let legPatterns: [(String, String)] = [
            (#"\s*-?\s*Leg\s*1$"#, " · 1st leg"), (#"\s*-?\s*Leg\s*2$"#, " · 2nd leg"),
            (#"\s*-?\s*1st Leg$"#, " · 1st leg"), (#"\s*-?\s*2nd Leg$"#, " · 2nd leg"),
        ]
        for (pattern, replacement) in legPatterns {
            if let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                text.replaceSubrange(range, with: replacement)
                break
            }
        }
        text = text.replacingOccurrences(of: #"MD\s*(\d+)"#, with: "MD $1", options: .regularExpression)
        return text
    }

    struct Window {
        var start: Date
        var name: String
    }

    /// Weekend (Fri–Mon) or midweek (Tue–Thu) window containing `date`, in the user's time zone.
    func dateWindow(for date: Date) -> Window {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)  // 1 = Sunday
        // Days back to the window's first day: Friday for Fri–Mon, Tuesday for Tue–Thu.
        let back: Int
        switch weekday {
        case 6: back = 0  // Fri
        case 7: back = 1  // Sat
        case 1: back = 2  // Sun
        case 2: back = 3  // Mon
        case 3: back = 0  // Tue
        case 4: back = 1  // Wed
        default: back = 2  // Thu
        }
        let start = calendar.date(byAdding: .day, value: -back, to: day)!
        return Window(start: start, name: dateWindowName(start: date, end: date))
    }

    /// "Weekend of 10–11 Oct" / "Midweek of 14–15 Oct", from the actual dates in the group.
    func dateWindowName(start: Date, end: Date) -> String {
        let weekday = calendar.component(.weekday, from: start)
        let kind = [3, 4, 5].contains(weekday) ? "Midweek" : "Weekend"
        return "\(kind) of \(Self.dayRange(start, end, calendar: calendar))"
    }

    static func dayRange(_ start: Date, _ end: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_GB")
        let startDay = calendar.component(.day, from: start)
        let endDay = calendar.component(.day, from: end)
        formatter.dateFormat = "MMM"
        let startMonth = formatter.string(from: start)
        let endMonth = formatter.string(from: end)
        if calendar.isDate(start, inSameDayAs: end) { return "\(startDay) \(startMonth)" }
        if startMonth == endMonth { return "\(startDay)–\(endDay) \(endMonth)" }
        return "\(startDay) \(startMonth) – \(endDay) \(endMonth)"
    }

    static func shortDate(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date)
    }

    func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

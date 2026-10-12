import Foundation
import Testing
@testable import FootyKit

struct LibraryBuilderTests {
    let builder = LibraryBuilder(config: TestData.config, calendar: .utc)
    let arsenal = TestData.team(57, "Arsenal FC", short: "Arsenal")
    let chelsea = TestData.team(61, "Chelsea FC", short: "Chelsea")
    let leeds = TestData.team(341, "Leeds United FC", short: "Leeds United")
    let forest = TestData.team(351, "Nottingham Forest FC", short: "Nottingham")

    func nbc(_ id: String, _ home: String, _ away: String, _ published: String, duration: Int = 600) -> Video {
        Video(id: id, channelKey: "nbc", originalTitle: "\(home) v. \(away) | PREMIER LEAGUE HIGHLIGHTS | 1/1/2026 | NBC Sports",
              publishedAt: TestData.date(published), durationSeconds: duration)
    }

    @Test func fixtureRoundsWithNeutralTitlesAndAvailability() {
        let fixtures = [
            TestData.fixture(1, arsenal, chelsea, "2025-10-04T14:00:00Z", matchday: 7),
            TestData.fixture(2, leeds, forest, "2025-10-04T14:00:00Z", matchday: 7),
            TestData.fixture(5, forest, arsenal, "2025-10-10T19:00:00Z", matchday: 8),
            TestData.fixture(3, chelsea, leeds, "2025-10-11T14:00:00Z", matchday: 8, status: .timed, score: nil),
            TestData.fixture(4, arsenal, leeds, "2025-10-25T14:00:00Z", matchday: 9, status: .timed, score: nil),
        ]
        let videos = [nbc("v1", "Arsenal", "Chelsea", "2025-10-04T17:00:00Z")]
        let library = builder.build(fixtures: fixtures, videos: videos, flags: [:], now: TestData.date("2025-10-11T12:00:00Z"))
        let pl = library.competition("PL")!
        #expect(pl.usesFixtureData)
        // Matchweek 9 hasn't started; newest first.
        #expect(pl.rounds.map(\.name) == ["Matchweek 8", "Matchweek 7"])
        let mw7 = pl.rounds[1]
        #expect(mw7.layout == .withTable)
        #expect(mw7.matches[0].neutralTitle == "Arsenal v Chelsea · Premier League · Matchweek 7")
        #expect(mw7.matches[0].availability == .playable)
        #expect(mw7.matches[1].neutralTitle == "Leeds United v Nottingham Forest · Premier League · Matchweek 7")
        #expect(mw7.matches[1].availability == .noHighlights)
        #expect(mw7.unwatchedCount == 1)
        #expect(pl.rounds[0].matches[1].availability == .upcoming(TestData.date("2025-10-11T14:00:00Z")))
        #expect(library.newStuff.map(\.id) == ["PL"])
    }

    @Test func recentFinishedMatchIsPendingNotMissing() {
        let fixtures = [TestData.fixture(1, arsenal, chelsea, "2025-10-04T14:00:00Z", matchday: 7)]
        let library = builder.build(fixtures: fixtures, videos: [], flags: [:], now: TestData.date("2025-10-04T18:00:00Z"))
        #expect(library.competition("PL")!.rounds[0].matches[0].availability == .highlightsPending)
    }

    @Test func extendedCutPreferredAndOneEntryPerMatch() {
        let psg = TestData.team(524, "Paris Saint-Germain FC", short: "PSG")
        let lens = TestData.team(546, "Racing Club de Lens", short: "RC Lens")
        let fixtures = [TestData.fixture(1, psg, lens, "2025-10-04T19:00:00Z", competition: "LIGUE1")]
        let normal = Video(id: "n", channelKey: "bein", originalTitle: "PSG vs Lens | HIGHLIGHTS Ligue 1 | 10/04/2025 | beIN SPORTS USA",
                           publishedAt: TestData.date("2025-10-04T21:30:00Z"), durationSeconds: 660)
        let extended = Video(id: "e", channelKey: "bein",
                             originalTitle: "PSG vs Lens | EXTENDED HIGHLIGHTS Ligue 1 | 10/04/2025 | beIN SPORTS USA",
                             publishedAt: TestData.date("2025-10-05T09:00:00Z"), durationSeconds: 1300)
        let library = builder.build(fixtures: fixtures, videos: [normal, extended], flags: [.video("n"): MatchFlags(watched: true)],
                                    now: TestData.date("2025-10-06T00:00:00Z"))
        let round = library.competition("LIGUE1")!.rounds[0]
        #expect(round.matches.count == 1)
        #expect(round.matches[0].video?.id == "e")
        #expect(round.matches[0].neutralTitle == "PSG v Lens · Ligue 1 · Matchday 1")
        // Watched state recorded against the other version still counts.
        #expect(round.matches[0].flags.watched)
    }

    @Test func secondLegShowsFirstLegOnlyWhenWatchedOrRevealed() {
        let a = TestData.team(5, "FC Bayern München", short: "Bayern")
        let b = TestData.team(81, "FC Barcelona", short: "Barça")
        let first = TestData.fixture(100, a, b, "2026-03-10T20:00:00Z", matchday: 1, stage: "LAST_16", score: (2, 1), competition: "UCL")
        let second = TestData.fixture(101, b, a, "2026-03-17T20:00:00Z", matchday: 2, stage: "LAST_16", score: (1, 1), competition: "UCL")
        let now = TestData.date("2026-03-20T00:00:00Z")
        var library = builder.build(fixtures: [first, second], videos: [], flags: [:], now: now)
        let rounds = library.competition("UCL")!.rounds
        #expect(rounds.map(\.name) == ["Round of 16 · 2nd leg", "Round of 16 · 1st leg"])
        #expect(rounds[0].layout == .fullWidth)
        let leg = rounds[0].matches[0].firstLeg
        #expect(leg?.fixture.id == 100)
        #expect(leg?.scoreVisible == false)
        library = builder.build(fixtures: [first, second], videos: [], flags: [.fixture(100): MatchFlags(watched: true)], now: now)
        #expect(library.competition("UCL")!.rounds[0].matches[0].firstLeg?.scoreVisible == true)
        #expect(library.competition("UCL")!.rounds[0].matches[0].neutralTitle == "Barcelona v Bayern Munich · Champions League · Round of 16 · 2nd leg")
    }

    @Test func withoutFixtureDataRoundsComeFromTitlesOrDates() {
        let videos = [
            Video(id: "c1", channelKey: "cbs", originalTitle: "Wigan vs. Wycombe: Extended Highlights | Carabao Cup Third Round | CBS Sports Golazo",
                  publishedAt: TestData.date("2025-09-23T22:00:00Z")),
            Video(id: "c2", channelKey: "cbs", originalTitle: "Leeds vs. Hull: Extended Highlights | Carabao Cup | CBS Sports Golazo",
                  publishedAt: TestData.date("2025-08-13T22:00:00Z")),
            nbc("p1", "Arsenal", "Chelsea", "2025-10-04T17:00:00Z"),  // Saturday
            nbc("p2", "Leeds United", "Nottingham Forest", "2025-10-05T17:00:00Z"),  // Sunday
            nbc("p3", "Chelsea", "Leeds United", "2025-10-08T20:00:00Z"),  // Wednesday
        ]
        let library = builder.build(fixtures: [], videos: videos, flags: [:])
        let carabao = library.competition("CARABAO")!
        #expect(carabao.rounds.map(\.name) == ["Third Round", "Midweek of 13 Aug"])
        #expect(carabao.rounds.allSatisfy { $0.layout == .fullWidth })
        #expect(carabao.rounds[0].matches[0].neutralTitle == "Wigan v Wycombe · Carabao Cup · Third Round")
        let pl = library.competition("PL")!
        #expect(!pl.usesFixtureData)
        #expect(pl.rounds.map(\.name) == ["Midweek of 8 Oct", "Weekend of 4–5 Oct"])
        #expect(pl.rounds[1].layout == .tableNeedsKey)
        #expect(pl.rounds[1].matches.map(\.neutralTitle) == [
            "Arsenal v Chelsea · Premier League", "Leeds United v Nottingham Forest · Premier League",
        ])
    }

    @Test func unmatchedVideoStillShowsInNearestRound() {
        let fixtures = [TestData.fixture(1, arsenal, chelsea, "2025-10-04T14:00:00Z", matchday: 7)]
        let videos = [nbc("x", "Mystery Town", "Unknown Rovers", "2025-10-05T17:00:00Z")]
        let library = builder.build(fixtures: fixtures, videos: videos, flags: [:], now: TestData.date("2025-10-10T00:00:00Z"))
        let round = library.competition("PL")!.rounds[0]
        #expect(round.matches.count == 2)
        #expect(round.matches.contains { $0.neutralTitle == "Mystery Town v Unknown Rovers · Premier League" })
    }

    @Test func browserFallbackOfferedOnlyWithoutPrimary() {
        let real = TestData.team(86, "Real Madrid CF", short: "Real Madrid")
        let sevilla = TestData.team(559, "Sevilla FC", short: "Sevilla FC")
        let fixtures = [TestData.fixture(1, real, sevilla, "2025-10-04T19:00:00Z", competition: "LALIGA")]
        let official = Video(id: "o", channelKey: "laliga", originalTitle: "REAL MADRID 1-0 SEVILLA FC | RESUMEN LALIGA EA SPORTS",
                             publishedAt: TestData.date("2025-10-04T22:00:00Z"))
        let library = builder.build(fixtures: fixtures, videos: [official], flags: [:], now: TestData.date("2025-10-08T00:00:00Z"))
        let entry = library.competition("LALIGA")!.rounds[0].matches[0]
        #expect(entry.availability == .noHighlights)
        #expect(entry.browserFallbackVideo?.id == "o")
        #expect(entry.neutralTitle == "Real Madrid v Sevilla · La Liga · Matchday 1")
        #expect(library.competition("LALIGA")!.unwatchedCount == 0)
    }

    @Test func roundWithMovedMatchesUsesItsMainDates() {
        let fixtures = TestData.fixtures("PL", competitionId: "PL")
        let library = builder.build(fixtures: fixtures, videos: [], flags: [:], now: TestData.date("2026-07-01T00:00:00Z"))
        let rounds = library.competition("PL")!.rounds
        #expect(rounds.map(\.name) == (1...38).reversed().map { "Matchweek \($0)" })
        let mw31 = rounds.first { $0.name == "Matchweek 31" }!
        #expect(mw31.matches.count == 10)
        #expect(mw31.earliestKickoff! > TestData.date("2026-03-19T00:00:00Z"))
    }

    @Test func prettyTitleRounds() {
        #expect(LibraryBuilder.prettyTitleRound("Round of 16 - Leg 1") == "Round of 16 · 1st leg")
        #expect(LibraryBuilder.prettyTitleRound("Knockout Play-offs - Leg 2") == "Knockout Play-offs · 2nd leg")
        #expect(LibraryBuilder.prettyTitleRound("League Phase MD1") == "League Phase MD 1")
        #expect(LibraryBuilder.prettyTitleRound("Semifinal Leg 2") == "Semifinal · 2nd leg")
        #expect(LibraryBuilder.prettyTitleRound("") == nil)
    }

    @Test func scoreDisplay() {
        #expect(MatchScore(goals: ScorePair(home: 2, away: 1)).display == "2–1")
        #expect(MatchScore(goals: ScorePair(home: 1, away: 1), penalties: ScorePair(home: 4, away: 3), duration: .penaltyShootout)
            .display == "1–1 a.e.t., 4–3 pens")
    }
}

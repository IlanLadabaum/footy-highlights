import Foundation
import Testing
@testable import FootyKit

struct MatchingTests {
    let names = TeamNames(config: TestData.config)

    @Test func normalisation() {
        #expect(TeamNames.normalize("1. FC Köln") == "koln")
        #expect(TeamNames.normalize("Brighton & Hove Albion FC") == "brighton hove albion")
        #expect(TeamNames.normalize("Club Atlético de Madrid") == "atletico madrid")
    }

    @Test func aliasesAndSubsets() {
        let wolves = TestData.team(76, "Wolverhampton Wanderers FC", short: "Wolverhampton")
        let city = TestData.team(65, "Manchester City FC", short: "Man City")
        let united = TestData.team(66, "Manchester United FC", short: "Man United")
        let koln = TestData.team(1, "1. FC Köln", short: "1. FC Köln")
        let atleti = TestData.team(78, "Club Atlético de Madrid", short: "Atleti")
        #expect(names.matchScore(videoName: "Wolves", team: wolves) == 3)
        #expect(names.matchScore(videoName: "Manchester City", team: city) >= 2)
        #expect(names.matchScore(videoName: "Manchester City", team: united) == 0)
        #expect(names.matchScore(videoName: "FC Cologne", team: koln) == 3)
        #expect(names.matchScore(videoName: "Atletico Madrid", team: atleti) == 3)
        #expect(names.matchScore(videoName: "Real Madrid", team: atleti) == 0)
    }

    /// Real 2025-26 titles against real 2025-26 fixtures: nearly every highlight finds its fixture,
    /// and no fixture is claimed by two different pairings.
    @Test(arguments: [
        ("nbc", "PL", "PL"), ("cbs", "CL", "UCL"), ("cbs", "SA", "SERIEA"), ("bein", "FL1", "LIGUE1"),
        ("espnfc", "PD", "LALIGA"), ("laliga", "PD", "LALIGA"),
    ])
    func realMatchRate(channel: String, code: String, competitionId: String) {
        let parser = TitleParser(config: TestData.config)
        let matcher = FixtureMatcher(names: names)
        let fixtures = TestData.fixtures(code, competitionId: competitionId)
        let parsed = TestData.videos(channel).compactMap { video -> (Video, ParsedTitle)? in
            guard let title = parser.parse(title: video.originalTitle, channelKey: channel),
                title.competitionId == competitionId,
                video.publishedAt >= fixtures.map(\.utcDate).min()!
            else { return nil }
            return (video, title)
        }
        #expect(parsed.count > 20)
        var matched = 0
        var unmatchedNames: [String] = []
        for (video, title) in parsed {
            if let fixture = matcher.match(home: title.home, away: title.away, publishedAt: video.publishedAt, in: fixtures) {
                matched += 1
                // The fixture's teams must be the ones in the title (either order).
                let straight = names.matchScore(videoName: title.home, team: fixture.home) > 0
                    || names.matchScore(videoName: title.away, team: fixture.away) > 0
                let reversed = names.matchScore(videoName: title.home, team: fixture.away) > 0
                    || names.matchScore(videoName: title.away, team: fixture.home) > 0
                #expect(straight || reversed)
            } else {
                unmatchedNames.append("\(title.home) | \(title.away)")
            }
        }
        let rate = Double(matched) / Double(parsed.count)
        #expect(rate >= 0.95, "\(channel)/\(code): \(matched)/\(parsed.count); unmatched team names: \(unmatchedNames.prefix(15))")
    }

    @Test func reversedHomeAwayStillMatches() {
        let a = TestData.team(4, "Borussia Dortmund", short: "Dortmund")
        let b = TestData.team(12, "SV Werder Bremen", short: "Bremen")
        let fixture = TestData.fixture(1, a, b, "2025-09-20T13:30:00Z", competition: "BUNDESLIGA")
        let matcher = FixtureMatcher(names: names)
        let found = matcher.match(home: "SV Werder Bremen", away: "Borussia Dortmund",
                                  publishedAt: TestData.date("2025-09-20T18:00:00Z"), in: [fixture])
        #expect(found?.id == 1)
        let tooLate = matcher.match(home: "SV Werder Bremen", away: "Borussia Dortmund",
                                    publishedAt: TestData.date("2025-10-20T18:00:00Z"), in: [fixture])
        #expect(tooLate == nil)
    }
}

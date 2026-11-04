import Foundation
import Testing

@testable import FootyKit

/// Extended / normal choice and per-competition source order. Titles are synthetic (no real results).
struct SourcesAndCutsTests {
    let builder = LibraryBuilder(config: TestData.config, calendar: .utc)
    let now = TestData.date("2025-10-08T00:00:00Z")

    // MARK: Extended / normal

    let psg = TestData.team(524, "Paris Saint-Germain FC", short: "PSG")
    let lens = TestData.team(546, "Racing Club de Lens", short: "RC Lens")

    func bein(_ id: String, extended: Bool, duration: Int) -> Video {
        Video(
            id: id, channelKey: "bein",
            originalTitle:
                "PSG vs Lens | \(extended ? "EXTENDED " : "")HIGHLIGHTS Ligue 1 | 10/04/2025 | beIN SPORTS USA",
            publishedAt: TestData.date("2025-10-04T22:00:00Z"), durationSeconds: duration)
    }

    func ligue1Entry(_ videos: [Video], options: LibraryOptions = LibraryOptions()) -> MatchEntry {
        let fixtures = [TestData.fixture(1, psg, lens, "2025-10-04T19:00:00Z", competition: "LIGUE1")]
        return builder.build(fixtures: fixtures, videos: videos, flags: [:], options: options, now: now)
            .competition("LIGUE1")!.rounds[0].matches[0]
    }

    @Test func bothCutsOfferTheToggleWithTheDefaultSelected() {
        let videos = [bein("n", extended: false, duration: 660), bein("e", extended: true, duration: 1300)]
        let entry = ligue1Entry(videos)
        #expect(entry.hasCutChoice)
        #expect(entry.selectedCut == .extended)
        #expect(entry.video?.id == "e")
        #expect(entry.cutOptions[.normal]?.id == "n")

        let normalByDefault = ligue1Entry(videos, options: LibraryOptions(defaultCut: .normal))
        #expect(normalByDefault.video?.id == "n")
    }

    @Test func perMatchChoiceOverridesTheDefault() {
        let videos = [bein("n", extended: false, duration: 660), bein("e", extended: true, duration: 1300)]
        let entry = ligue1Entry(videos, options: LibraryOptions(cutChoices: [.fixture(1): .normal]))
        #expect(entry.selectedCut == .normal)
        #expect(entry.video?.id == "n")
    }

    @Test func oneCutMeansNoToggle() {
        let entry = ligue1Entry(
            [bein("n", extended: false, duration: 660)], options: LibraryOptions(defaultCut: .extended))
        #expect(!entry.hasCutChoice)
        #expect(entry.selectedCut == nil)
        #expect(entry.video?.id == "n")
    }

    // MARK: La Liga source order

    let sevilla = TestData.team(559, "Sevilla FC", short: "Sevilla FC")
    let betis = TestData.team(90, "Real Betis Balompié", short: "Real Betis")
    let girona = TestData.team(298, "Girona FC", short: "Girona")
    let celta = TestData.team(558, "RC Celta de Vigo", short: "Celta")

    var laLigaFixtures: [Fixture] {
        [
            TestData.fixture(10, sevilla, betis, "2025-10-04T19:00:00Z", competition: "LALIGA"),
            TestData.fixture(11, girona, celta, "2025-10-05T14:00:00Z", competition: "LALIGA"),
        ]
    }

    func espnfc(_ id: String, _ home: String, _ away: String) -> Video {
        Video(
            id: id, channelKey: "espnfc", originalTitle: "\(home) vs. \(away) | LALIGA Highlights | ESPN FC",
            publishedAt: TestData.date("2025-10-05T20:00:00Z"), durationSeconds: 700)
    }

    func deportes(_ id: String, _ title: String, duration: Int = 800, published: String = "2025-10-05T18:00:00Z")
        -> Video
    {
        Video(
            id: id, channelKey: "espndeportes", originalTitle: title, publishedAt: TestData.date(published),
            durationSeconds: duration)
    }

    var videos: [Video] {
        [
            espnfc("fc1", "Sevilla", "Real Betis"),
            deportes("d1", "El Sevilla y el Betis animaron el derbi de la jornada | LaLiga"),
            deportes("d2", "Girona y Celta de Vigo, un partido de ida y vuelta | LaLiga"),
            // A short clip and a different competition are ignored.
            deportes("clip", "La previa: Girona recibe al Celta | LaLiga", duration: 120),
            deportes("mx", "Girona y Celta en la Liga MX", duration: 800),
        ]
    }

    func laLiga(_ options: LibraryOptions) -> [Int: MatchEntry] {
        let matches = builder.build(fixtures: laLigaFixtures, videos: videos, flags: [:], options: options, now: now)
            .competition("LALIGA")!.rounds.flatMap(\.matches)
        return Dictionary(uniqueKeysWithValues: matches.map { ($0.fixture!.id, $0) })
    }

    @Test func firstSourceWinsAndTheSecondFillsGaps() {
        let entries = laLiga(LibraryOptions())
        #expect(entries[10]?.video?.id == "fc1")
        #expect(entries[11]?.video?.id == "d2")
        #expect(entries[11]?.spoilerProneTitle == true)
        // Watching either source's video counts for the match.
        #expect(entries[10]?.flagKeys.contains(.video("d1")) == true)
    }

    @Test func reversedOrderAndSingleSource() {
        let reversed = laLiga(LibraryOptions(sourceOrder: ["LALIGA": ["espndeportes", "espnfc"]]))
        #expect(reversed[10]?.video?.id == "d1")
        let fcOnly = laLiga(LibraryOptions(sourceOrder: ["LALIGA": ["espnfc"]]))
        #expect(fcOnly[11]?.isPlayable == false)
        let deportesOnly = laLiga(LibraryOptions(sourceOrder: ["LALIGA": ["espndeportes"]]))
        #expect(deportesOnly[10]?.video?.id == "d1")
    }

    @Test func freeFormTitlesNeedFixtureData() {
        let options = LibraryOptions(hasFixtureData: false)
        #expect(
            options.channels(for: TestData.config.competition(id: "LALIGA")!, config: TestData.config) == ["espnfc"])
        let library = builder.build(fixtures: [], videos: videos, flags: [:], options: options, now: now)
        let ids = library.competition("LALIGA")!.rounds.flatMap(\.matches).compactMap(\.video?.id)
        #expect(ids == ["fc1"])
    }

    @Test func titleNamingTwoFixturesIsLeftOut() {
        let matcher = FixtureMatcher(names: TeamNames(config: TestData.config))
        let text = "Sevilla, Betis, Girona y Celta: lo mejor de la jornada | LaLiga"
        #expect(
            matcher.match(mentionsIn: text, publishedAt: TestData.date("2025-10-05T18:00:00Z"), in: laLigaFixtures)
                == nil)
    }

    @Test func settingsOffersEveryOrderAndEachSourceAlone() {
        let options = TestData.config.competition(id: "LALIGA")!.sourceOrderOptions
        #expect(options == [["espnfc", "espndeportes"], ["espndeportes", "espnfc"], ["espnfc"], ["espndeportes"]])
        #expect(TestData.config.competition(id: "PL")!.sourceOrderOptions.isEmpty)
    }
}

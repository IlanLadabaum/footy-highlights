import Foundation
import Testing
@testable import FootyKit

struct TitleParserTests {
    let parser = TitleParser(config: TestData.config)

    @Test func nbcPremierLeague() {
        let parsed = parser.parse(title: "Leeds United v. Chelsea | PREMIER LEAGUE HIGHLIGHTS | 12/3/2025 | NBC Sports", channelKey: "nbc")
        #expect(parsed?.competitionId == "PL")
        #expect(parsed?.home == "Leeds United")
        #expect(parsed?.away == "Chelsea")
        #expect(parsed?.isExtended == false)
        let edited = parser.parse(title: "Wolves v. Leeds United | PREMIER LEAGUE HIGHLIGHTS | 9/20/2025 | NBC Sports (edited)", channelKey: "nbc")
        #expect(edited?.home == "Wolves")
    }

    @Test func nbcRejectsNonHighlights() {
        for title in [
            "Top Premier League highlights from Matchweek 5 | Netbusters | NBC Sports",
            "Towson Tigers vs. Maryland Terrapins | COLLEGE FOOTBALL HIGHLIGHTS | 9/13/2025 | NBC Sports",
            "Arsenal v. Chelsea | FULL MATCH | 1/1/2026 | NBC Sports",
        ] {
            #expect(parser.parse(title: title, channelKey: "nbc") == nil, "\(title)")
        }
    }

    @Test func cbsRoutesByLabel() {
        let ucl = parser.parse(title: "Napoli vs. Arsenal: Extended Highlights | UCL League Phase MD 1 | CBS Sports Golazo", channelKey: "cbs")
        #expect(ucl?.competitionId == "UCL")
        #expect(ucl?.titleRound == "League Phase MD 1")
        #expect(ucl?.isExtended == true)
        let serieA = parser.parse(title: "Inter vs. Parma | Extended Highlights | Serie A | CBS Sports Golazo", channelKey: "cbs")
        #expect(serieA?.competitionId == "SERIEA")
        #expect(serieA?.home == "Inter")
        let carabao = parser.parse(title: "Wigan vs. Wycombe: Extended Highlights | Carabao Cup Third Round | CBS Sports Golazo", channelKey: "cbs")
        #expect(carabao?.competitionId == "CARABAO")
        #expect(carabao?.titleRound == "Third Round")
        let carabaoNoRound = parser.parse(title: "A vs. B: Extended Highlights | Carabao Cup | CBS Sports Golazo", channelKey: "cbs")
        #expect(carabaoNoRound?.competitionId == "CARABAO")
        #expect(carabaoNoRound?.titleRound == nil)
        for title in [
            "Celtic vs. Kairat: Extended Highlights | UCL Qualifiers - Play-off Leg 1 | CBS Sports Golazo",
            "Leeds vs. Derby: Extended Highlights | EFL Championship | CBS Sports Golazo",
            "1964 FINAL | Mazzola vs. Puskás",
        ] {
            #expect(parser.parse(title: title, channelKey: "cbs") == nil, "\(title)")
        }
    }

    @Test func beinExtendedAndNormal() {
        let normal = parser.parse(title: "Metz vs Brest | HIGHLIGHTS Ligue 1 | 03/01/2026 | beIN SPORTS USA", channelKey: "bein")
        #expect(normal?.competitionId == "LIGUE1")
        #expect(normal?.isExtended == false)
        let extended = parser.parse(title: "PSG vs Le Mans | EXTENDED HIGHLIGHTS Ligue 1 | 10/10/2026 | beIN SPORTS USA", channelKey: "bein")
        #expect(extended?.isExtended == true)
        let other = parser.parse(title: "Lille vs Stade Rennes | Ligue 1 HIGHLIGHTS | 01/03/2026 beIN SPORTS USA", channelKey: "bein")
        #expect(other?.away == "Stade Rennes")
        #expect(parser.parse(title: "Metz vs Lyon | RESUMEN Ligue 1 | 01/25/2026 | beIN SPORTS USA", channelKey: "bein") == nil)
    }

    @Test func usaSportsFormats() {
        for title in [
            "Borussia Dortmund v. SV Werder Bremen | BUNDESLIGA HIGHLIGHTS | USA Sports",
            "Borussia Dortmund vs SV Werder Bremen | BUNDESLIGA HIGHLIGHTS 9/9/2026 | USA Sports",
            "Borussia Dortmund v. SV Werder Bremen | BUNDESLIGA HIGHLIGHTS | 9/9/2026 | USA Sports",
        ] {
            let parsed = parser.parse(title: title, channelKey: "usa")
            #expect(parsed?.competitionId == "BUNDESLIGA", "\(title)")
            #expect(parsed?.home == "Borussia Dortmund")
            #expect(parsed?.away == "SV Werder Bremen")
        }
    }

    @Test func espnTeaserPrefixesAreStripped() {
        let cases = [
            ("LEWANDOWSKI & YAMAL SCORE 💥 Barcelona vs. Mallorca | LALIGA Highlights | ESPN FC", "Barcelona"),
            ("UCL IMPLICATIONS 👀 Girona vs. Real Betis | LALIGA Highlights | ESPN FC", "Girona"),
            ("RED CARD DRAMA ‼️ Sevilla vs. Barcelona | LALIGA Highlights | ESPN FC", "Sevilla"),
            ("LATE WINNER Real Madrid vs. Sevilla | LALIGA Highlights | ESPN FC", "Real Madrid"),
            ("Athletic Club vs. Girona | LALIGA Highlights | ESPN FC", "Athletic Club"),
        ]
        for (title, home) in cases {
            let parsed = parser.parse(title: title, channelKey: "espnfc")
            #expect(parsed?.competitionId == "LALIGA")
            #expect(parsed?.home == home, "\(title)")
            #expect(parsed?.role == .primary)
        }
        #expect(parser.parse(title: "Real Madrid vs. Sevilla | ESPN FC", channelKey: "espnfc") == nil)
    }

    @Test func laLigaOfficialIsFallbackOnly() {
        let parsed = parser.parse(title: "VILLARREAL CF 2-1 ATLÉTICO DE MADRID | RESUMEN LALIGA EA SPORTS", channelKey: "laliga")
        #expect(parsed?.role == .browserFallback)
        #expect(parsed?.home == "VILLARREAL CF")
        #expect(parsed?.away == "ATLÉTICO DE MADRID")
    }

    /// Every real past-season title in the standard format parses; nothing else from those channels does.
    @Test func realTitleCoverage() {
        let standard: [String: String] = [
            "nbc": #"\| PREMIER LEAGUE HIGHLIGHTS \|"#,
            "bein": #"\| (EXTENDED )?HIGHLIGHTS Ligue 1 \|"#,
            "espnfc": #"\| LALIGA Highlights \| ESPN FC$"#,
            "laliga": #"\| RESUMEN LALIGA EA SPORTS$"#,
        ]
        for (channel, pattern) in standard {
            let all = TestData.titles[channel] ?? []
            let expected = all.filter { item in
                item.title.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
                    && item.title.range(of: #" vs?\.? |\d+\s*-\s*\d+"#, options: .regularExpression) != nil
            }
            let parsed = expected.filter { parser.parse(title: $0.title, channelKey: channel) != nil }
            #expect(!expected.isEmpty, "\(channel)")
            #expect(Double(parsed.count) / Double(expected.count) >= 0.98, "\(channel): \(parsed.count)/\(expected.count)")
        }
        // CBS: every "<A> vs. <B>: Extended Highlights | Serie A/UCL…/Carabao Cup…" parses.
        let cbs = (TestData.titles["cbs"] ?? []).filter {
            $0.title.range(of: #"Extended Highlights \| (Serie A|UCL (League|Round|Knockout|Quarter|Semi|Final)|Carabao Cup)"#,
                           options: .regularExpression) != nil
        }
        let cbsParsed = cbs.filter { parser.parse(title: $0.title, channelKey: "cbs") != nil }
        #expect(Double(cbsParsed.count) / Double(cbs.count) >= 0.98, "cbs: \(cbsParsed.count)/\(cbs.count)")
    }
}

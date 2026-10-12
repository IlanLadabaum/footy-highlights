import Foundation
@testable import FootyKit

enum TestData {
    static let config = AppConfig.bundled()

    static func url(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
    }

    struct RawTitle: Decodable {
        var id: String
        var title: String
        var published: Date
    }

    /// Real past-season (2025-26) uploads per channel key.
    static let titles: [String: [RawTitle]] = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode([String: [RawTitle]].self, from: Data(contentsOf: url("titles_2025.json")))
    }()

    static func videos(_ channel: String) -> [Video] {
        (titles[channel] ?? []).map { Video(id: $0.id, channelKey: channel, originalTitle: $0.title, publishedAt: $0.published) }
    }

    /// Real 2025-26 fixtures (past season, results are fine in tests).
    static func fixtures(_ code: String, competitionId: String) -> [Fixture] {
        try! FootballDataClient.decodeMatches(Data(contentsOf: url("matches_\(code)_2025.json")), competitionId: competitionId)
    }

    static func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    static func team(_ id: Int, _ name: String, short: String? = nil) -> Team {
        Team(id: id, name: name, shortName: short ?? name, tla: String(name.prefix(3)).uppercased())
    }

    static func fixture(
        _ id: Int, _ home: Team, _ away: Team, _ kickoff: String, matchday: Int? = 1, stage: String = "REGULAR_SEASON",
        status: MatchStatus = .finished, score: (Int, Int)? = (1, 0), competition: String = "PL"
    ) -> Fixture {
        Fixture(
            id: id, competitionId: competition, season: 2025, utcDate: date(kickoff), status: status, stage: stage,
            matchday: matchday, home: home, away: away,
            score: score.map { MatchScore(goals: ScorePair(home: $0.0, away: $0.1)) })
    }
}

/// Canned HTTP responses for client tests.
final class FakeHTTP: HTTPClient, @unchecked Sendable {
    var responses: [(status: Int, body: Data, headers: [String: String])]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [(Int, Data, [String: String])]) {
        self.responses = responses.map { (status: $0.0, body: $0.1, headers: $0.2) }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let next = responses.isEmpty ? (status: 500, body: Data(), headers: [:]) : responses.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: next.status, httpVersion: nil, headerFields: next.headers)!
        return (next.body, response)
    }
}

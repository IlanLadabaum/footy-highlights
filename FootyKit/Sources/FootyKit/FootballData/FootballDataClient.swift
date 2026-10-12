import Foundation

public enum FootballDataError: Error, LocalizedError, Equatable {
    case invalidKey
    case restricted(String)
    case rateLimited
    case http(status: Int, message: String?)

    public var errorDescription: String? {
        switch self {
        case .invalidKey: "The football-data.org key was rejected. Check it in Settings."
        case .restricted(let code): "football-data.org's free plan doesn't include \(code)."
        case .rateLimited: "football-data.org rate limit reached. The app will retry on the next refresh."
        case .http(let status, let message): "football-data.org request failed (\(status)\(message.map { ", \($0)" } ?? ""))."
        }
    }
}

/// A row of a current-standings table, used only to detect point deductions. Never shown.
public struct StandingsRow: Hashable, Sendable, Codable {
    public var teamId: Int
    public var won: Int
    public var draw: Int
    public var points: Int

    /// Points missing compared with 3 per win and 1 per draw (a deduction), or 0.
    public var deduction: Int { max(0, won * 3 + draw - points) }
}

/// football-data.org v4. Every request goes through the shared `RequestThrottle`.
public struct FootballDataClient: Sendable {
    let apiKey: String
    let http: HTTPClient
    let throttle: RequestThrottle
    let base = URL(string: "https://api.football-data.org/v4/")!

    public init(apiKey: String, throttle: RequestThrottle, http: HTTPClient = URLSessionHTTPClient()) {
        self.apiKey = apiKey
        self.http = http
        self.throttle = throttle
    }

    /// All of a season's matches for one competition in a single request.
    public func matches(code: String, season: Int, competitionId: String) async throws -> [Fixture] {
        let data = try await get("competitions/\(code)/matches", query: ["season": String(season)], code: code)
        return try Self.decodeMatches(data, competitionId: competitionId)
    }

    /// Current standings (season always sent). Only used for deduction detection.
    public func currentStandings(code: String, season: Int) async throws -> [StandingsRow] {
        let data = try await get("competitions/\(code)/standings", query: ["season": String(season)], code: code)
        let body = try JSONDecoder().decode(StandingsBody.self, from: data)
        let total = body.standings.first { $0.type == "TOTAL" } ?? body.standings.first
        return total?.table.map { StandingsRow(teamId: $0.team.id, won: $0.won, draw: $0.draw, points: $0.points) } ?? []
    }

    private func get(_ path: String, query: [String: String], code: String) async throws -> Data {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.setValue(apiKey, forHTTPHeaderField: "X-Auth-Token")
        request.timeoutInterval = 30
        let http = self.http
        let (data, response) = try await throttle.perform { [request] in try await http.send(request) }
        switch response.statusCode {
        case 200: return data
        case 400, 401:
            throw FootballDataError.invalidKey
        case 403:
            let message = (try? JSONDecoder().decode(MessageBody.self, from: data))?.message ?? ""
            if message.localizedCaseInsensitiveContains("token") || message.localizedCaseInsensitiveContains("key") {
                throw FootballDataError.invalidKey
            }
            throw FootballDataError.restricted(code)
        case 429: throw FootballDataError.rateLimited
        default:
            let message = (try? JSONDecoder().decode(MessageBody.self, from: data))?.message
            throw FootballDataError.http(status: response.statusCode, message: message)
        }
    }

    public static func decodeMatches(_ data: Data, competitionId: String) throws -> [Fixture] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let body = try decoder.decode(MatchesBody.self, from: data)
        return body.matches.compactMap { $0.fixture(competitionId: competitionId) }
    }
}

private struct MessageBody: Decodable { var message: String? }

private struct StandingsBody: Decodable {
    struct Table: Decodable {
        struct Row: Decodable {
            struct TeamRef: Decodable { var id: Int }
            var team: TeamRef
            var won: Int
            var draw: Int
            var points: Int
        }
        var type: String
        var table: [Row]
    }
    var standings: [Table]
}

struct MatchesBody: Decodable {
    struct APIMatch: Decodable {
        struct APISeason: Decodable { var startDate: String }
        struct APITeam: Decodable {
            var id: Int?
            var name: String?
            var shortName: String?
            var tla: String?
        }
        struct APIScore: Decodable {
            struct Pair: Decodable {
                var home: Int?
                var away: Int?
            }
            var duration: String?
            var fullTime: Pair?
            var regularTime: Pair?
            var extraTime: Pair?
            var penalties: Pair?
        }
        var id: Int
        var utcDate: Date
        var status: MatchStatus
        var stage: String?
        var matchday: Int?
        var season: APISeason
        var homeTeam: APITeam
        var awayTeam: APITeam
        var score: APIScore?

        func fixture(competitionId: String) -> Fixture? {
            // Knockout matches can be listed before their teams are known.
            guard let home = homeTeam.team, let away = awayTeam.team,
                let seasonYear = Int(season.startDate.prefix(4))
            else { return nil }
            return Fixture(
                id: id, competitionId: competitionId, season: seasonYear, utcDate: utcDate, status: status,
                stage: stage ?? "REGULAR_SEASON", matchday: matchday, home: home, away: away,
                score: status.isFinal ? score?.matchScore : nil)
        }
    }
    var matches: [APIMatch]
}

extension MatchesBody.APIMatch.APITeam {
    fileprivate var team: Team? {
        guard let id, let name else { return nil }
        return Team(id: id, name: name, shortName: shortName ?? name, tla: tla ?? "")
    }
}

extension MatchesBody.APIMatch.APIScore {
    fileprivate var matchScore: MatchScore? {
        let kind = MatchScore.Duration(rawValue: duration ?? "REGULAR") ?? .regular
        let penaltiesPair = penalties.flatMap { pair -> ScorePair? in
            guard let home = pair.home, let away = pair.away else { return nil }
            return ScorePair(home: home, away: away)
        }
        if kind != .regular, let regular = regularTime, let rh = regular.home, let ra = regular.away {
            // fullTime includes shoot-out penalties for PENALTY_SHOOTOUT; rebuild from regular + extra time.
            let eh = extraTime?.home ?? 0
            let ea = extraTime?.away ?? 0
            return MatchScore(goals: ScorePair(home: rh + eh, away: ra + ea), penalties: penaltiesPair, duration: kind)
        }
        guard let home = fullTime?.home, let away = fullTime?.away else { return nil }
        return MatchScore(goals: ScorePair(home: home, away: away), penalties: penaltiesPair, duration: kind)
    }
}

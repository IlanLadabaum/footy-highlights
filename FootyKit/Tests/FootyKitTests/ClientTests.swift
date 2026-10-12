import Foundation
import Testing
@testable import FootyKit

final class Clock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_000_000)
    var slept: [TimeInterval] = []
}

struct ThrottleTests {
    func ok(_ available: Int?, reset: Int = 30) -> (Int, Data, [String: String]) {
        var headers = ["X-RequestCounter-Reset": "\(reset)"]
        if let available { headers["x-requests-available-minute"] = "\(available)" }
        return (200, Data("{}".utf8), headers)
    }

    @Test func waitsForResetWhenHeadersSayNoneLeft() async throws {
        let clock = Clock()
        let throttle = RequestThrottle(now: { clock.now }, sleep: { seconds in
            clock.slept.append(seconds)
            clock.now += seconds
        })
        let http = FakeHTTP([ok(1), ok(0, reset: 42), ok(9)])
        let request = URLRequest(url: URL(string: "https://example.com")!)
        for _ in 0..<3 { _ = try await throttle.perform { try await http.send(request) } }
        #expect(clock.slept == [42])
    }

    @Test func countsLocallyWhenHeadersAreMissing() async throws {
        let clock = Clock()
        let throttle = RequestThrottle(limitPerMinute: 3, now: { clock.now }, sleep: { seconds in
            clock.slept.append(seconds)
            clock.now += seconds
        })
        let http = FakeHTTP(Array(repeating: ok(nil), count: 4))
        let request = URLRequest(url: URL(string: "https://example.com")!)
        for _ in 0..<4 { _ = try await throttle.perform { try await http.send(request) } }
        #expect(clock.slept == [60])
    }

    @Test func retriesOnceAfter429() async throws {
        let clock = Clock()
        let throttle = RequestThrottle(now: { clock.now }, sleep: { seconds in
            clock.slept.append(seconds)
            clock.now += seconds
        })
        let http = FakeHTTP([(429, Data(), ["X-RequestCounter-Reset": "17"]), ok(5)])
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let (_, response) = try await throttle.perform { try await http.send(request) }
        #expect(response.statusCode == 200)
        #expect(clock.slept == [17])
        #expect(http.requests.count == 2)
    }
}

struct FootballDataClientTests {
    @Test func sendsSeasonAndToken() async throws {
        let body = try Data(contentsOf: TestData.url("matches_PL_2025.json"))
        let http = FakeHTTP([(200, body, ["x-requests-available-minute": "9"])])
        let client = FootballDataClient(apiKey: "test-token", throttle: RequestThrottle(), http: http)
        let fixtures = try await client.matches(code: "PL", season: 2025, competitionId: "PL")
        #expect(fixtures.count == 380)
        #expect(fixtures.allSatisfy { $0.season == 2025 && $0.score != nil })
        let request = try #require(http.requests.first)
        #expect(request.value(forHTTPHeaderField: "X-Auth-Token") == "test-token")
        #expect(request.url?.query?.contains("season=2025") == true)
    }

    @Test func mapsErrors() async {
        let http = FakeHTTP([(403, Data(#"{"message":"The resource you are looking for is restricted."}"#.utf8), [:])])
        let client = FootballDataClient(apiKey: "k", throttle: RequestThrottle(), http: http)
        await #expect(throws: FootballDataError.restricted("FLC")) {
            _ = try await client.matches(code: "FLC", season: 2025, competitionId: "CARABAO")
        }
    }

    @Test func penaltyScoresExcludeShootoutFromGoals() {
        let fixtures = TestData.fixtures("CL", competitionId: "UCL")
        for fixture in fixtures where fixture.score?.duration == .penaltyShootout {
            #expect(fixture.score?.penalties != nil)
            #expect(fixture.score!.goals.home == fixture.score!.goals.away)
        }
    }
}

struct YouTubeClientTests {
    @Test func isoDurations() {
        #expect(YouTubeClient.parseISODuration("PT9M41S") == 581)
        #expect(YouTubeClient.parseISODuration("PT1H2M3S") == 3723)
        #expect(YouTubeClient.parseISODuration("PT45S") == 45)
        #expect(YouTubeClient.parseISODuration("P0D") == 0)
        #expect(YouTubeClient.parseISODuration("garbage") == nil)
    }

    @Test func scanStopsAtCutoff() async throws {
        func page(_ items: [(String, String)], next: String?) -> Data {
            let entries = items.map { id, date in
                #"{"snippet":{"title":"T \#(id)","publishedAt":"\#(date)"},"contentDetails":{"videoId":"\#(id)","videoPublishedAt":"\#(date)"}}"#
            }
            let token = next.map { #","nextPageToken":"\#($0)""# } ?? ""
            return Data(#"{"items":[\#(entries.joined(separator: ","))]\#(token)}"#.utf8)
        }
        let http = FakeHTTP([
            (200, page([("a", "2026-10-10T10:00:00Z"), ("b", "2026-09-01T10:00:00Z")], next: "p2"), [:]),
            (200, page([("c", "2026-08-02T10:00:00Z"), ("d", "2026-07-20T10:00:00Z")], next: "p3"), [:]),
            (200, page([("e", "2026-07-01T10:00:00Z")], next: nil), [:]),
        ])
        let client = YouTubeClient(apiKey: "k", http: http)
        let uploads = try await client.uploads(playlistId: "UUx", since: TestData.date("2026-08-01T00:00:00Z"))
        #expect(uploads.map(\.videoId) == ["a", "b", "c"])
        #expect(http.requests.count == 2)
    }

    @Test func errorMapping() {
        let quota = Data(#"{"error":{"errors":[{"reason":"quotaExceeded"}]}}"#.utf8)
        #expect(YouTubeClient.error(status: 403, body: quota) == .quotaExceeded)
        let bad = Data(#"{"error":{"message":"API key not valid. Please pass a valid API key.","errors":[{"reason":"badRequest"}]}}"#.utf8)
        #expect(YouTubeClient.error(status: 400, body: bad) == .invalidKey)
    }
}

import Foundation
import Testing
@testable import FootyKit

@MainActor
struct StoreTests {
    @Test func flagsRoundTripAndUndo() throws {
        let store = try Store(inMemory: true)
        let keys: [MatchKey] = [.fixture(1), .video("abc")]
        let previous = store.setFlags(keys, watched: true)
        #expect(store.flags()[.fixture(1)]?.watched == true)
        #expect(store.flags()[.video("abc")]?.watched == true)
        store.setFlags([.fixture(1)], revealed: true)
        #expect(store.flags()[.fixture(1)] == MatchFlags(watched: true, revealed: true))
        store.restoreFlags(previous)
        #expect(store.flags()[.fixture(1)] == MatchFlags(watched: false, revealed: false))
    }

    @Test func fixturesReplacePerCompetitionSeason() throws {
        let store = try Store(inMemory: true)
        let a = TestData.team(1, "A"), b = TestData.team(2, "B")
        store.replaceFixtures([TestData.fixture(1, a, b, "2025-08-16T14:00:00Z"), TestData.fixture(2, b, a, "2025-08-23T14:00:00Z")],
                              competitionId: "PL", season: 2025)
        store.replaceFixtures([TestData.fixture(3, a, b, "2025-08-16T14:00:00Z", competition: "SERIEA")],
                              competitionId: "SERIEA", season: 2025)
        store.replaceFixtures([TestData.fixture(1, a, b, "2025-08-16T14:00:00Z", status: .awarded)], competitionId: "PL", season: 2025)
        let fixtures = store.fixtures().sorted { $0.id < $1.id }
        #expect(fixtures.map(\.id) == [1, 3])
        #expect(fixtures[0].status == .awarded)
    }

    @Test func fullRescanRemovesVanishedVideosAndStaleDataIsPurged() throws {
        let store = try Store(inMemory: true)
        let now = TestData.date("2026-10-01T00:00:00Z")
        let v1 = Video(id: "1", channelKey: "nbc", originalTitle: "t1", publishedAt: now)
        let v2 = Video(id: "2", channelKey: "nbc", originalTitle: "t2", publishedAt: now)
        let v3 = Video(id: "3", channelKey: "cbs", originalTitle: "t3", publishedAt: now)
        store.upsertVideos([v1, v2, v3], seenAt: now)
        store.upsertVideos([v1], seenAt: now, replacingChannel: "nbc")
        #expect(Set(store.videos().map(\.id)) == ["1", "3"])
        store.upsertVideos([v1], seenAt: now.addingTimeInterval(31 * 86_400))
        store.purgeStaleVideos(now: now.addingTimeInterval(31 * 86_400))
        #expect(store.videos().map(\.id) == ["1"])
    }

    @Test func deductionsFromStandings() throws {
        let store = try Store(inMemory: true)
        store.setStandings([StandingsRow(teamId: 7, won: 5, draw: 2, points: 7), StandingsRow(teamId: 8, won: 1, draw: 1, points: 4)],
                           code: "PL", season: 2026, at: Date())
        #expect(store.deductions(code: "PL", season: 2026) == [7: 10])
    }

    @Test func fixtureRefreshPolicy() {
        let now = TestData.date("2026-10-10T20:00:00Z")
        let a = TestData.team(1, "A"), b = TestData.team(2, "B")
        let finished = TestData.fixture(1, a, b, "2026-10-10T12:00:00Z")
        let overdue = TestData.fixture(2, a, b, "2026-10-10T14:00:00Z", status: .timed, score: nil)
        #expect(Refresher.fixturesNeedRefresh(last: nil, stored: [], now: now))
        #expect(!Refresher.fixturesNeedRefresh(last: now.addingTimeInterval(-3600), stored: [finished], now: now))
        #expect(Refresher.fixturesNeedRefresh(last: now.addingTimeInterval(-3600), stored: [overdue], now: now))
        #expect(!Refresher.fixturesNeedRefresh(last: now.addingTimeInterval(-300), stored: [overdue], now: now))
        #expect(Refresher.fixturesNeedRefresh(last: now.addingTimeInterval(-25 * 3600), stored: [finished], now: now))
    }
}

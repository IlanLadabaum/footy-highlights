import FootyKit
import XCTest
@testable import Footy_Highlights

@MainActor
final class QueueTests: XCTestCase {
    private func makeModel() throws -> AppModel {
        let store = try Store(inMemory: true)
        let names = ["Arsenal", "Chelsea", "Everton", "Fulham", "Brentford", "Burnley"]
        let teams = names.enumerated().map { Team(id: $0.offset + 1, name: "\($0.element) FC", shortName: $0.element, tla: "T\($0.offset)") }
        let kickoff = Date(timeIntervalSinceNow: -10 * 86_400)
        var fixtures: [Fixture] = []
        var videos: [Video] = []
        for index in 0..<3 {
            let date = kickoff.addingTimeInterval(Double(index) * 3600)
            let home = teams[index * 2], away = teams[index * 2 + 1]
            fixtures.append(Fixture(
                id: 100 + index, competitionId: "PL", season: Season.year(containing: date), utcDate: date,
                status: .finished, stage: "REGULAR_SEASON", matchday: 1, home: home, away: away,
                score: MatchScore(goals: ScorePair(home: 1, away: 0))))
            videos.append(Video(
                id: "vid\(index)", channelKey: "nbc",
                originalTitle: "\(home.shortName) v. \(away.shortName) | PREMIER LEAGUE HIGHLIGHTS | 1/1/2026 | NBC Sports",
                publishedAt: date.addingTimeInterval(7200), durationSeconds: 600))
        }
        store.replaceFixtures(fixtures, competitionId: "PL", season: fixtures[0].season)
        store.upsertVideos(videos, seenAt: Date())
        let model = AppModel(store: store, defaults: UserDefaults(suiteName: "queue-test-\(UUID())")!)
        return model
    }

    func testQueueDoesNotMarkWatchedUntilReached() throws {
        let model = try makeModel()
        let entries = model.library.competition("PL")!.rounds.flatMap(\.matches).filter(\.isPlayable)
        XCTAssertGreaterThanOrEqual(entries.count, 2)
        for entry in entries { model.enqueue(entry) }
        model.enqueue(entries[0])  // duplicates ignored
        XCTAssertEqual(model.queuedEntries.count, entries.count)
        XCTAssertTrue(model.queuedEntries.allSatisfy { !$0.flags.watched })

        let first = model.popQueue()
        XCTAssertEqual(first?.id, entries[0].id)
        XCTAssertTrue(first?.flags.watched == true)
        XCTAssertTrue(model.queuedEntries.allSatisfy { !$0.flags.watched })
        XCTAssertEqual(model.queuedEntries.count, entries.count - 1)
    }

    func testReorderAndClear() throws {
        let model = try makeModel()
        let entries = model.library.competition("PL")!.rounds.flatMap(\.matches).filter(\.isPlayable)
        for entry in entries { model.enqueue(entry) }
        model.moveQueue(from: IndexSet(integer: entries.count - 1), to: 0)
        XCTAssertEqual(model.queuedEntries.first?.id, entries.last?.id)
        model.dequeue(entries.last!.id)
        XCTAssertEqual(model.queuedEntries.count, entries.count - 1)
        model.clearQueue()
        XCTAssertTrue(model.queuedEntries.isEmpty)
        XCTAssertNil(model.popQueue())
    }

    func testRevealAllScoresInRoundAndHideAgain() throws {
        let model = try makeModel()
        let round = model.library.competition("PL")!.rounds[0]
        model.setAllRevealed(in: round, true)
        let revealed = model.library.round(round.id)!
        XCTAssertTrue(revealed.matches.allSatisfy(\.flags.revealed))
        XCTAssertEqual(model.table(for: revealed)?.rows.filter { $0.played == 1 }.count, 6)
        model.setAllRevealed(in: revealed, false)
        XCTAssertTrue(model.library.round(round.id)!.matches.allSatisfy { !$0.flags.revealed })
    }
}

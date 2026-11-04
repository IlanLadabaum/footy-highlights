import Foundation
import SwiftData

/// Local cache (SwiftData). The UI always renders from here; refreshes write into it.
@MainActor
public final class Store {
    public let container: ModelContainer
    let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public static let schema = Schema([
        VideoRecord.self, FixtureRecord.self, FlagRecord.self, SyncRecord.self, StandingsRecord.self,
        CutChoiceRecord.self,
    ])

    /// `inMemory` for tests and the CLI; otherwise the default on-disk store in Application Support.
    public init(inMemory: Bool = false, url: URL? = nil) throws {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: true)
        } else if let url {
            configuration = ModelConfiguration(schema: Self.schema, url: url)
        } else {
            configuration = ModelConfiguration(schema: Self.schema)
        }
        container = try ModelContainer(for: Self.schema, configurations: configuration)
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    public func save() {
        do {
            try context.save()
        } catch {
            assertionFailure("Store save failed: \(error)")
        }
    }

    // MARK: Fixtures

    public func fixtures() -> [Fixture] {
        let records = (try? context.fetch(FetchDescriptor<FixtureRecord>())) ?? []
        return records.compactMap { try? decoder.decode(Fixture.self, from: $0.payload) }
    }

    /// Replaces a competition-season's fixtures with a fresh download.
    public func replaceFixtures(_ fixtures: [Fixture], competitionId: String, season: Int) {
        let existing =
            (try? context.fetch(
                FetchDescriptor<FixtureRecord>(
                    predicate: #Predicate { $0.competitionId == competitionId && $0.season == season }))) ?? []
        var byId = Dictionary(existing.map { ($0.fixtureId, $0) }, uniquingKeysWith: { first, _ in first })
        for fixture in fixtures {
            guard let payload = try? encoder.encode(fixture) else { continue }
            if let record = byId.removeValue(forKey: fixture.id) {
                record.payload = payload
            } else {
                context.insert(FixtureRecord(fixture, payload: payload))
            }
        }
        for stale in byId.values { context.delete(stale) }
        save()
    }

    // MARK: Videos

    public func videos() -> [Video] {
        ((try? context.fetch(FetchDescriptor<VideoRecord>())) ?? []).map(\.video)
    }

    /// Inserts or updates videos. With `replacingChannel`, videos of that channel not in `videos` are deleted
    /// (used after a full rescan, so nothing older than the 30-day refresh rule lingers).
    public func upsertVideos(_ videos: [Video], seenAt: Date, replacingChannel channelKey: String? = nil) {
        let existing = (try? context.fetch(FetchDescriptor<VideoRecord>())) ?? []
        var byId = Dictionary(existing.map { ($0.videoId, $0) }, uniquingKeysWith: { first, _ in first })
        var seen: Set<String> = []
        for video in videos {
            seen.insert(video.id)
            if let record = byId[video.id] {
                record.originalTitle = video.originalTitle
                record.publishedAt = video.publishedAt
                if let duration = video.durationSeconds { record.durationSeconds = duration }
                record.lastSeenAt = seenAt
            } else {
                let record = VideoRecord(video, seenAt: seenAt)
                context.insert(record)
                byId[video.id] = record
            }
        }
        if let channelKey {
            for record in existing where record.channelKey == channelKey && !seen.contains(record.videoId) {
                context.delete(record)
            }
        }
        save()
    }

    public func setDurations(_ durations: [String: Int]) {
        guard !durations.isEmpty else { return }
        let records = (try? context.fetch(FetchDescriptor<VideoRecord>())) ?? []
        for record in records { if let seconds = durations[record.videoId] { record.durationSeconds = seconds } }
        save()
    }

    /// Deletes cached YouTube data not refreshed for 30 days (YouTube API policy DP III.E.4.c).
    public func purgeStaleVideos(now: Date) {
        let limit = now.addingTimeInterval(-30 * 86_400)
        let stale =
            (try? context.fetch(FetchDescriptor<VideoRecord>(predicate: #Predicate { $0.lastSeenAt < limit }))) ?? []
        for record in stale { context.delete(record) }
        if !stale.isEmpty { save() }
    }

    // MARK: Flags

    public func flags() -> [MatchKey: MatchFlags] {
        let records = (try? context.fetch(FetchDescriptor<FlagRecord>())) ?? []
        var result: [MatchKey: MatchFlags] = [:]
        for record in records {
            if let key = MatchKey(string: record.key) {
                result[key] = MatchFlags(watched: record.watched, revealed: record.revealed)
            }
        }
        return result
    }

    /// Sets watched and/or revealed for the given keys. Returns the previous values (for undo).
    @discardableResult
    public func setFlags(_ keys: [MatchKey], watched: Bool? = nil, revealed: Bool? = nil, at date: Date = Date())
        -> [MatchKey: MatchFlags]
    {
        let wanted = Set(keys.map(\.description))
        let records = (try? context.fetch(FetchDescriptor<FlagRecord>())) ?? []
        var byKey = Dictionary(
            records.filter { wanted.contains($0.key) }.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var previous: [MatchKey: MatchFlags] = [:]
        for key in keys {
            let record: FlagRecord
            if let existing = byKey[key.description] {
                record = existing
            } else {
                record = FlagRecord(key: key.description, flags: MatchFlags(), at: date)
                context.insert(record)
                byKey[key.description] = record
            }
            previous[key] = MatchFlags(watched: record.watched, revealed: record.revealed)
            if let watched { record.watched = watched }
            if let revealed { record.revealed = revealed }
            record.updatedAt = date
        }
        save()
        return previous
    }

    /// Restores exact flag values (undo).
    public func restoreFlags(_ values: [MatchKey: MatchFlags], at date: Date = Date()) {
        for (key, flags) in values {
            setFlags([key], watched: flags.watched, revealed: flags.revealed, at: date)
        }
    }

    // MARK: Cut choices

    public func cutChoices() -> [MatchKey: HighlightCut] {
        let records = (try? context.fetch(FetchDescriptor<CutChoiceRecord>())) ?? []
        var result: [MatchKey: HighlightCut] = [:]
        for record in records {
            if let key = MatchKey(string: record.key), let cut = HighlightCut(rawValue: record.cut) {
                result[key] = cut
            }
        }
        return result
    }

    public func setCut(_ cut: HighlightCut, for key: MatchKey) {
        let wanted = key.description
        let existing = try? context.fetch(FetchDescriptor<CutChoiceRecord>(predicate: #Predicate { $0.key == wanted }))
        if let record = existing?.first {
            record.cut = cut.rawValue
        } else {
            context.insert(CutChoiceRecord(key: wanted, cut: cut))
        }
        save()
    }

    // MARK: Sync markers

    public func syncDate(_ key: String) -> Date? {
        (try? context.fetch(FetchDescriptor<SyncRecord>(predicate: #Predicate { $0.key == key })))?.first?.date
    }

    public func syncNote(_ key: String) -> String? {
        (try? context.fetch(FetchDescriptor<SyncRecord>(predicate: #Predicate { $0.key == key })))?.first?.note
    }

    public func setSync(_ key: String, date: Date, note: String? = nil) {
        if let record = (try? context.fetch(FetchDescriptor<SyncRecord>(predicate: #Predicate { $0.key == key })))?
            .first
        {
            record.date = date
            record.note = note
        } else {
            context.insert(SyncRecord(key: key, date: date, note: note))
        }
        save()
    }

    // MARK: Standings (deduction detection)

    public func deductions(code: String, season: Int) -> [Int: Int] {
        let key = "\(code):\(season)"
        guard
            let record =
                (try? context.fetch(FetchDescriptor<StandingsRecord>(predicate: #Predicate { $0.key == key })))?.first,
            let rows = try? decoder.decode([StandingsRow].self, from: record.payload)
        else { return [:] }
        return Dictionary(rows.filter { $0.deduction > 0 }.map { ($0.teamId, $0.deduction) }, uniquingKeysWith: max)
    }

    public func standingsFetchedAt(code: String, season: Int) -> Date? {
        let key = "\(code):\(season)"
        return (try? context.fetch(FetchDescriptor<StandingsRecord>(predicate: #Predicate { $0.key == key })))?.first?
            .fetchedAt
    }

    public func setStandings(_ rows: [StandingsRow], code: String, season: Int, at date: Date) {
        let key = "\(code):\(season)"
        guard let payload = try? encoder.encode(rows) else { return }
        if let record = (try? context.fetch(FetchDescriptor<StandingsRecord>(predicate: #Predicate { $0.key == key })))?
            .first
        {
            record.payload = payload
            record.fetchedAt = date
        } else {
            context.insert(StandingsRecord(key: key, payload: payload, fetchedAt: date))
        }
        save()
    }
}

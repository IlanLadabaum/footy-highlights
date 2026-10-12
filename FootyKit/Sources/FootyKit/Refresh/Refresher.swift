import Foundation

public struct RefreshReport: Sendable, Equatable {
    public var skipped = false
    public var newVideos = 0
    public var fixtureCompetitionsUpdated = 0
    public var youTubeUnits = 0
    public var footballDataRequests = 0
    /// User-facing problems (bad key, quota, network). Shown non-blocking.
    public var errors: [String] = []

    public init() {}
}

/// Pulls fresh data into the local store following the plan's rules: launch + manual refresh,
/// at most every 15 minutes; one football-data request per competition (daily, or sooner around
/// match days); YouTube uploads scanned back to the season start, then incrementally.
@MainActor
public final class Refresher {
    public static let minimumInterval: TimeInterval = 15 * 60
    public static let fixtureMaxAge: TimeInterval = 24 * 3600
    /// Full YouTube rescans happen at least this often, keeping cached data within the 30-day rule.
    public static let fullScanInterval: TimeInterval = 25 * 86_400
    static let incrementalOverlap: TimeInterval = 2 * 86_400

    let config: AppConfig
    let store: Store
    let parser: TitleParser
    let throttle: RequestThrottle
    let http: HTTPClient

    public init(config: AppConfig, store: Store, throttle: RequestThrottle = RequestThrottle(),
                http: HTTPClient = URLSessionHTTPClient()) {
        self.config = config
        self.store = store
        self.parser = TitleParser(config: config)
        self.throttle = throttle
        self.http = http
    }

    public var lastRefresh: Date? { store.syncDate("refresh") }

    public func refresh(keys: APIKeys, force: Bool = false, now: Date = Date()) async -> RefreshReport {
        var report = RefreshReport()
        if !force, let last = lastRefresh, now.timeIntervalSince(last) < Self.minimumInterval {
            report.skipped = true
            return report
        }
        let season = Season.year(containing: now)
        if let key = keys.footballData, !key.isEmpty {
            await refreshFixtures(key: key, season: season, now: now, report: &report)
        }
        if let key = keys.youTube, !key.isEmpty {
            await refreshVideos(key: key, season: season, now: now, report: &report)
        } else {
            report.errors.append("Add a YouTube API key in Settings to find highlights.")
        }
        store.purgeStaleVideos(now: now)
        if report.errors.isEmpty || report.newVideos > 0 || report.fixtureCompetitionsUpdated > 0 {
            store.setSync("refresh", date: now)
        }
        return report
    }

    // MARK: football-data

    func refreshFixtures(key: String, season: Int, now: Date, report: inout RefreshReport) async {
        let client = FootballDataClient(apiKey: key, throttle: throttle, http: http)
        let existing = Dictionary(grouping: store.fixtures(), by: \.competitionId)
        for competition in config.competitionsByPriority {
            guard let code = competition.footballDataCode else { continue }
            let syncKey = "fd:\(code):\(season)"
            let last = store.syncDate(syncKey)
            let stored = (existing[competition.id] ?? []).filter { $0.season == season }
            guard Self.fixturesNeedRefresh(last: last, stored: stored, now: now) else { continue }
            do {
                let fixtures = try await client.matches(code: code, season: season, competitionId: competition.id)
                report.footballDataRequests += 1
                store.replaceFixtures(fixtures, competitionId: competition.id, season: season)
                store.setSync(syncKey, date: now)
                report.fixtureCompetitionsUpdated += 1
            } catch let error as FootballDataError {
                report.footballDataRequests += 1
                report.errors.append(error.localizedDescription)
                if error == .invalidKey { return }
            } catch {
                report.errors.append("Couldn't reach football-data.org (\(error.localizedDescription)).")
                return
            }

            // Current standings, only to detect point deductions; daily is plenty.
            guard competition.effectiveRoundStyle == .league, !competition.cup else { continue }
            let fetched = store.standingsFetchedAt(code: code, season: season)
            if fetched == nil || now.timeIntervalSince(fetched!) > Self.fixtureMaxAge {
                if let rows = try? await client.currentStandings(code: code, season: season) {
                    store.setStandings(rows, code: code, season: season, at: now)
                }
                report.footballDataRequests += 1
            }
        }
    }

    /// Daily, or sooner when a match that should be over by now isn't marked final yet (match days).
    static func fixturesNeedRefresh(last: Date?, stored: [Fixture], now: Date) -> Bool {
        guard let last else { return true }
        let age = now.timeIntervalSince(last)
        if age >= fixtureMaxAge { return true }
        guard age >= minimumInterval else { return false }
        let overdue = stored.contains { fixture in
            (fixture.status.isUpcoming || fixture.status.isLive) && fixture.utcDate.addingTimeInterval(2.5 * 3600) < now
        }
        return overdue
    }

    // MARK: YouTube

    func refreshVideos(key: String, season: Int, now: Date, report: inout RefreshReport) async {
        let client = YouTubeClient(apiKey: key, http: http)
        let channelKeys = Set(config.competitions.flatMap { $0.sources.map(\.channel) }).sorted()
        let cutoff = Season.scanCutoff(forSeason: season)
        let known = Set(store.videos().map(\.id))
        for channelKey in channelKeys {
            guard let channel = config.channels[channelKey] else { continue }
            let syncKey = "yt:\(channelKey)"
            let lastFull = store.syncDate(syncKey + ":full")
            let fullScan = lastFull == nil || lastFull! < cutoff || now.timeIntervalSince(lastFull!) > Self.fullScanInterval
            let since = fullScan ? cutoff : max(cutoff, (store.syncDate(syncKey) ?? cutoff).addingTimeInterval(-Self.incrementalOverlap))
            do {
                let uploads = try await client.uploads(playlistId: channel.uploadsPlaylistId, since: since)
                report.youTubeUnits += max(1, (uploads.count + 49) / 50)
                let highlights = uploads.compactMap { upload -> Video? in
                    guard parser.parse(title: upload.title, channelKey: channelKey) != nil else { return nil }
                    return Video(id: upload.videoId, channelKey: channelKey, originalTitle: upload.title,
                                 publishedAt: upload.publishedAt)
                }
                store.upsertVideos(highlights, seenAt: now, replacingChannel: fullScan ? channelKey : nil)
                report.newVideos += highlights.filter { !known.contains($0.id) }.count
                let newest = uploads.map(\.publishedAt).max() ?? store.syncDate(syncKey) ?? cutoff
                store.setSync(syncKey, date: newest)
                if fullScan { store.setSync(syncKey + ":full", date: now) }
            } catch let error as YouTubeError {
                report.errors.append(error.localizedDescription)
                if error == .invalidKey || error == .quotaExceeded { return }
            } catch {
                report.errors.append("Couldn't reach YouTube (\(error.localizedDescription)).")
                return
            }
        }

        // Durations for videos that don't have one yet (1 unit per 50).
        let missing = store.videos().filter { $0.durationSeconds == nil }.map(\.id)
        guard !missing.isEmpty else { return }
        do {
            let durations = try await client.durations(videoIds: missing)
            report.youTubeUnits += (missing.count + 49) / 50
            store.setDurations(durations)
        } catch {
            report.errors.append((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}

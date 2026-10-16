import FootyKit
import Foundation
import Observation

/// App-wide state: the local store, the data the screens show, keys and refresh status.
@MainActor
@Observable
final class AppModel {
    let config = AppConfig.bundled()
    let store: Store
    private let refresher: Refresher
    private let builder: LibraryBuilder
    private let keyManager = KeyManager()

    /// The app's single model (the App struct can be re-created; this can't).
    static let shared = AppModel()

    /// Off in the developer snapshot/test modes, so the main window doesn't refresh alongside them.
    static var automaticRefresh = true

    /// The main window's navigation stack.
    var path: [Route] = []
    /// Highlights waiting to play, in order. Persisted between launches.
    private(set) var queue: [MatchKey] = []
    private static let queueDefaultsKey = "queue"
    /// Competition IDs the user follows; nil until they've chosen (first launch asks).
    private(set) var enabledLeagues: Set<String>?
    private static let leaguesDefaultsKey = "enabledLeagues"

    private(set) var library = Library.empty
    private(set) var keys = APIKeys(youTube: nil, footballData: nil)
    private(set) var keySources: [APIKeyKind: KeySource] = [:]
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?
    private(set) var refreshErrors: [String] = []
    /// Set when a manual refresh was skipped because the data is fresh.
    private(set) var upToDateNotice = false
    private(set) var storeError: String?

    var hasYouTubeKey: Bool { !(keys.youTube ?? "").isEmpty }
    var hasFootballDataKey: Bool { !(keys.footballData ?? "").isEmpty }

    private let defaults: UserDefaults

    init(store injected: Store? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var openError: String?
        let store = injected ?? {
            do {
                return try Store()
            } catch {
                // Fall back to memory so the app still works; only watched status is lost.
                openError = "Couldn't open the local database (\(error.localizedDescription)). Watched status won't be saved."
                return try! Store(inMemory: true)  // swiftlint:disable:this force_try
            }
        }()
        storeError = openError
        self.store = store
        refresher = Refresher(config: config, store: store)
        builder = LibraryBuilder(config: config)
        reloadKeys()
        lastRefresh = refresher.lastRefresh
        enabledLeagues = defaults.stringArray(forKey: Self.leaguesDefaultsKey).map(Set.init)
        queue = (defaults.stringArray(forKey: Self.queueDefaultsKey) ?? []).compactMap(MatchKey.init(string:))
        rebuild()
    }

    // MARK: Data

    func rebuild() {
        library = builder.build(fixtures: store.fixtures(), videos: store.videos(), flags: store.flags())
    }

    /// Launch and the Refresh button: refreshes only if the data is older than 15 minutes (per the plan).
    func refresh(force: Bool = false) async {
        guard !isRefreshing, hasYouTubeKey else { return }
        isRefreshing = true
        upToDateNotice = false
        defer { isRefreshing = false }
        let report = await refresher.refresh(keys: keys, enabled: enabledLeagues, force: force)
        if report.skipped {
            upToDateNotice = true
        } else {
            refreshErrors = report.errors
        }
        lastRefresh = refresher.lastRefresh
        rebuild()
    }

    // MARK: Keys

    func reloadKeys() {
        let loaded = keyManager.load()
        keys = loaded.keys
        keySources = loaded.sources
    }

    func saveKey(_ kind: APIKeyKind, value: String) async {
        keyManager.save(kind, value: value)
        reloadKeys()
        // New key: fetch straight away rather than waiting out the 15-minute rule.
        await refresh(force: true)
    }

    // MARK: Flags

    /// Returns the previous values so the caller can register an undo.
    @discardableResult
    func setWatched(_ entries: [MatchEntry], _ watched: Bool) -> [MatchKey: MatchFlags] {
        let keys = entries.flatMap(\.flagKeys)
        guard !keys.isEmpty else { return [:] }
        let previous = store.setFlags(keys, watched: watched)
        rebuild()
        return previous
    }

    @discardableResult
    func setRevealed(_ entry: MatchEntry, _ revealed: Bool) -> [MatchKey: MatchFlags] {
        let previous = store.setFlags(entry.flagKeys, revealed: revealed)
        rebuild()
        return previous
    }

    /// Finished matches in the round whose score can be revealed.
    func revealableMatches(in round: Round) -> [MatchEntry] {
        round.matches.filter { $0.fixture?.score != nil && $0.fixture?.status.isFinal == true }
    }

    /// "Update table with all scores": reveals (or hides again) every finished match in the round.
    @discardableResult
    func setAllRevealed(in round: Round, _ revealed: Bool) -> [MatchKey: MatchFlags] {
        let keys = revealableMatches(in: round).flatMap(\.flagKeys)
        guard !keys.isEmpty else { return [:] }
        let previous = store.setFlags(keys, revealed: revealed)
        rebuild()
        return previous
    }

    func revealFirstLeg(_ info: FirstLegInfo) {
        store.setFlags([.fixture(info.fixture.id)], revealed: true)
        rebuild()
    }

    func restore(_ previous: [MatchKey: MatchFlags]) {
        store.restoreFlags(previous)
        rebuild()
    }

    // MARK: Leagues

    var needsLeagueChoice: Bool { enabledLeagues == nil }

    func isEnabled(_ competitionId: String) -> Bool { enabledLeagues?.contains(competitionId) ?? true }

    /// Home page competitions: only followed leagues.
    var visibleCompetitions: [CompetitionSummary] { library.competitions.filter { isEnabled($0.id) } }

    /// Turning a league off stops fetching it; turning one on fetches it straight away.
    func setLeagues(_ ids: Set<String>) {
        let added = !ids.subtracting(enabledLeagues ?? []).isEmpty || enabledLeagues == nil
        enabledLeagues = ids
        defaults.set(Array(ids).sorted(), forKey: Self.leaguesDefaultsKey)
        if added, hasYouTubeKey { Task { await refresh(force: true) } }
    }

    func setLeague(_ competitionId: String, enabled: Bool) {
        var ids = enabledLeagues ?? Set(config.competitions.map(\.id))
        if enabled { ids.insert(competitionId) } else { ids.remove(competitionId) }
        setLeagues(ids)
    }

    // MARK: Queue

    /// Queued entries that still exist and can play, in queue order.
    var queuedEntries: [MatchEntry] {
        queue.compactMap { entry($0) }.filter(\.isPlayable)
    }

    func isQueued(_ entry: MatchEntry) -> Bool { queue.contains(entry.id) }

    /// Adding to the queue doesn't mark anything watched; that happens when the player reaches it.
    func enqueue(_ entry: MatchEntry) {
        guard entry.isPlayable, !queue.contains(entry.id) else { return }
        queue.append(entry.id)
        saveQueue()
    }

    func dequeue(_ key: MatchKey) {
        queue.removeAll { $0 == key }
        saveQueue()
    }

    func toggleQueued(_ entry: MatchEntry) {
        if isQueued(entry) {
            dequeue(entry.id)
        } else {
            enqueue(entry)
        }
    }

    /// Reorders using offsets into `queuedEntries` (what the queue list shows).
    func moveQueue(from source: IndexSet, to destination: Int) {
        var keys = queuedEntries.map(\.id)
        keys.move(fromOffsets: source, toOffset: destination)
        queue = keys
        saveQueue()
    }

    func clearQueue() {
        queue = []
        saveQueue()
    }

    /// Takes the next playable highlight off the queue and marks it watched (the player has reached it).
    func popQueue() -> MatchEntry? {
        while let key = queue.first {
            queue.removeFirst()
            saveQueue()
            if let next = entry(key), next.isPlayable {
                setWatched([next], true)
                return entry(key)
            }
        }
        return nil
    }

    /// Queues the round's unwatched highlights in the order they're listed (chronological). Returns how many were added.
    @discardableResult
    func queueAllUnwatched(in round: Round) -> Int {
        let added = round.matches.filter { $0.isUnwatched && !queue.contains($0.id) }
        queue += added.map(\.id)
        saveQueue()
        return added.count
    }

    func startQueue() {
        guard !queuedEntries.isEmpty else { return }
        if path.last == .queue { return }
        path.append(.queue)
    }

    private func saveQueue() {
        defaults.set(queue.map(\.description), forKey: Self.queueDefaultsKey)
    }

    // MARK: Tables

    struct RoundTable {
        var rows: [StandingsEntry]
        var revealedCount: Int
        /// Teams with a point deduction this season (detected, not applied; see DEVIATIONS D12).
        var deductionNotes: [String]
    }

    /// The table as it stood before the round, plus the results the user revealed in this round.
    func table(for round: Round) -> RoundTable? {
        guard let cutoff = round.earliestKickoff,
            let competition = config.competition(id: round.id.competitionId),
            let season = round.matches.compactMap(\.fixture).first?.season
        else { return nil }
        let fixtures = (library.fixturesByCompetition[competition.id] ?? []).filter { $0.season == season }
        let revealed = Set(round.matches.filter { $0.flags.revealed }.compactMap(\.fixture?.id))
        let names = TeamNames(config: config)
        let calculator = StandingsCalculator(rule: competition.tiebreak ?? .premierLeague) { names.displayName(for: $0) }
        let rows = calculator.table(fixtures: fixtures, before: cutoff, applying: revealed)
        let deductions = competition.footballDataCode.map { store.deductions(code: $0, season: season) } ?? [:]
        let notes = rows.compactMap { row -> String? in
            guard let points = deductions[row.team.id] else { return nil }
            return "\(names.displayName(for: row.team)) had \(points) point\(points == 1 ? "" : "s") deducted this season (not included)."
        }
        let applied = revealed.filter { id in fixtures.contains { $0.id == id && $0.utcDate >= cutoff && $0.status.isFinal } }
        return RoundTable(rows: rows, revealedCount: applied.count, deductionNotes: notes)
    }

    /// A team's previous results in this round's competition: only what the round's table counts. Newest first.
    func teamResults(_ teamId: Int, round: Round) -> [Fixture] {
        guard let cutoff = round.earliestKickoff,
            let season = round.matches.compactMap(\.fixture).first?.season
        else { return [] }
        let fixtures = (library.fixturesByCompetition[round.id.competitionId] ?? []).filter { $0.season == season }
        let revealed = Set(round.matches.filter { $0.flags.revealed }.compactMap(\.fixture?.id))
        return TeamResults.results(for: teamId, in: fixtures, before: cutoff, applying: revealed)
    }

    func displayName(_ team: Team) -> String {
        TeamNames(config: config).displayName(for: team)
    }

    // MARK: Lookups

    func entry(_ key: MatchKey) -> MatchEntry? {
        for competition in library.competitions {
            for round in competition.rounds {
                if let entry = round.matches.first(where: { $0.id == key }) { return entry }
            }
        }
        return nil
    }

    func channelName(_ video: Video) -> String {
        config.channels[video.channelKey]?.name ?? "YouTube"
    }
}

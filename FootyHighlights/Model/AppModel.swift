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

    /// Off in the developer snapshot/test modes, so the main window doesn't refresh alongside them.
    static var automaticRefresh = true

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

    init(store injected: Store? = nil) {
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
        let report = await refresher.refresh(keys: keys, force: force)
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

    func revealFirstLeg(_ info: FirstLegInfo) {
        store.setFlags([.fixture(info.fixture.id)], revealed: true)
        rebuild()
    }

    func restore(_ previous: [MatchKey: MatchFlags]) {
        store.restoreFlags(previous)
        rebuild()
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

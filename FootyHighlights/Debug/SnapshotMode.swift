#if DEBUG && os(macOS)
    import AppKit
    import FootyKit
    import SwiftUI

    /// Developer tool: renders the main screens offscreen to PNGs and quits.
    ///   --snapshot <out-dir>      where to write PNGs
    ///   --seed <fixtures-dir>     fill an in-memory store from past-season test fixtures (no live data, no spoilers)
    /// Without --seed it renders whatever the normal on-disk store holds (scores stay hidden unless revealed).
    @MainActor
    enum SnapshotMode {
        static var outputDir: URL? {
            argument("--snapshot").map { URL(fileURLWithPath: $0) }
        }

        static func argument(_ name: String) -> String? {
            let args = CommandLine.arguments
            guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
            return args[index + 1]
        }

        static func run(outputDir: URL) {
            let model: AppModel
            if let seed = argument("--seed") {
                let store = try! Store(inMemory: true)  // swiftlint:disable:this force_try
                seedStore(store, from: URL(fileURLWithPath: seed))
                model = AppModel(store: store)
            } else {
                model = AppModel()
            }
            try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
            let library = model.library
            var screens: [(String, AnyView)] = [
                ("1-competitions", AnyView(NavigationStack { CompetitionsView() })),
                ("9-settings-keys", AnyView(KeysSettings().frame(width: 560, height: 520))),
                ("9-settings-advanced", AnyView(AdvancedSettings().frame(width: 560, height: 200))),
                ("9-setup", AnyView(SetupView())),
            ]
            let idle = PlayerController(videoId: "none")
            let chrome = { (panel: AnyView) in
                AnyView(VStack(spacing: 0) {
                    ZStack { Color.black; panel }
                    PlayerControls(controller: idle, hideDurations: false, isFullScreen: false, toggleFullScreen: {})
                })
            }
            screens.append(("4-player-finished", chrome(AnyView(FinishedPanel(replay: {}, back: {})))))
            screens.append(("4-player-error", chrome(AnyView(ErrorPanel(code: 150, video: nil, open: { _ in })))))
            for competition in library.competitions where !competition.rounds.isEmpty {
                screens.append(("2-rounds-\(competition.id)", AnyView(NavigationStack { RoundsView(competitionId: competition.id) })))
                screens.append(("3-round-\(competition.id)", AnyView(NavigationStack { RoundView(roundId: competition.rounds[0].id) })))
                if let secondLeg = competition.rounds.first(where: { $0.name.hasSuffix("2nd leg") }) {
                    screens.append(("3-round-\(competition.id)-2ndleg", AnyView(NavigationStack { RoundView(roundId: secondLeg.id) })))
                }
            }
            for (name, view) in screens {
                render(view.environment(model), size: CGSize(width: 1200, height: 800), to: outputDir.appendingPathComponent("\(name).png"))
            }
            print("Snapshots written to \(outputDir.path)")
            exit(0)
        }

        static func render(_ view: some View, size: CGSize, to url: URL) {
            let hosting = NSHostingView(
                rootView: view.frame(width: size.width, height: size.height)
                    .background(Color(nsColor: .windowBackgroundColor)))
            hosting.frame = CGRect(origin: .zero, size: size)
            hosting.appearance = NSAppearance(named: argument("--dark") != nil ? .darkAqua : .aqua)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            window.setFrameOrigin(CGPoint(x: -10_000, y: -10_000))
            window.orderFrontRegardless()
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            window.orderOut(nil)
        }

        /// Past-season (2025-26) fixtures and titles from FootyKit's test fixtures, plus a few flags.
        static func seedStore(_ store: Store, from dir: URL) {
            let codes = ["PL": "PL", "CL": "UCL", "PD": "LALIGA", "BL1": "BUNDESLIGA", "SA": "SERIEA", "FL1": "LIGUE1"]
            for (code, competitionId) in codes {
                guard let data = try? Data(contentsOf: dir.appendingPathComponent("matches_\(code)_2025.json")),
                    let fixtures = try? FootballDataClient.decodeMatches(data, competitionId: competitionId)
                else { continue }
                store.replaceFixtures(fixtures, competitionId: competitionId, season: 2025)
            }
            struct Raw: Decodable {
                var id: String
                var title: String
                var published: Date
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let data = try? Data(contentsOf: dir.appendingPathComponent("titles_2025.json")),
                let titles = try? decoder.decode([String: [Raw]].self, from: data)
            {
                let parser = TitleParser(config: AppConfig.bundled())
                for (channel, items) in titles {
                    let videos = items.filter { parser.parse(title: $0.title, channelKey: channel) != nil }.map {
                        Video(id: $0.id, channelKey: channel, originalTitle: $0.title, publishedAt: $0.published,
                              durationSeconds: 540 + abs($0.id.hashValue % 600))
                    }
                    store.upsertVideos(videos, seenAt: Date())
                }
            }
            // Some watched and revealed matches so those states show up.
            let lastPL = store.fixtures().filter { $0.competitionId == "PL" && $0.matchday == 38 }.sorted { $0.id < $1.id }
            store.setFlags(lastPL.prefix(3).map { .fixture($0.id) }, watched: true)
            store.setFlags(lastPL.dropFirst(1).prefix(2).map { .fixture($0.id) }, revealed: true)
        }
    }
#endif

import Foundation
import FootyKit

// Live-data check for the data layer. Prints counts only, never original titles or scores.
// Usage: swift run footy-cli [path/to/.env]

@MainActor
func run() async {
    let envPath = CommandLine.arguments.dropFirst().first { !$0.hasPrefix("--") } ?? findEnv()
    guard let envPath else {
        print("No .env found. Pass its path as the first argument.")
        exit(1)
    }
    let keys = EnvFile.keys(from: URL(fileURLWithPath: envPath))
    print("Keys: YouTube \(keys.youTube == nil ? "missing" : "present"), football-data \(keys.footballData == nil ? "missing" : "present")")

    let config = AppConfig.bundled()
    let store: Store
    do {
        store = try Store(inMemory: true)
    } catch {
        print("Store error: \(error)")
        exit(1)
    }
    let started = Date()
    let report = await Refresher(config: config, store: store).refresh(keys: keys, force: true)
    print(String(format: "Refresh: %.0fs, %d highlight videos, %d competitions' fixtures, ~%d YouTube units, %d football-data requests",
                 Date().timeIntervalSince(started), report.newVideos, report.fixtureCompetitionsUpdated,
                 report.youTubeUnits, report.footballDataRequests))
    for error in report.errors { print("  ! \(error)") }

    let library = LibraryBuilder(config: config).build(fixtures: store.fixtures(), videos: store.videos(), flags: store.flags())
    print("")
    print("Competition         data      rounds  matches  playable  matched  unmatched  no-hl  pending  durations")
    for competition in library.competitions {
        let entries = competition.rounds.flatMap(\.matches)
        let playable = entries.filter(\.isPlayable)
        let matched = playable.filter { $0.fixture != nil }.count
        let unmatched = playable.filter { $0.fixture == nil }.count
        let noHighlights = entries.filter { $0.availability == .noHighlights }.count
        let pending = entries.filter { $0.availability == .highlightsPending }.count
        let withDuration = playable.filter { $0.video?.durationSeconds != nil }.count
        print(
            competition.config.name.padding(toLength: 20, withPad: " ", startingAt: 0)
                + (competition.usesFixtureData ? "fixtures " : "titles   ")
                + pad(competition.rounds.count, 7) + pad(entries.count, 9) + pad(playable.count, 10)
                + pad(matched, 9) + pad(unmatched, 11) + pad(noHighlights, 7) + pad(pending, 9) + pad(withDuration, 11))
        if let latest = competition.rounds.first {
            print("    latest round: \(latest.name) (\(latest.matches.count) matches, layout \(latest.layout))")
        }
    }
    // Team names only (no titles, no scores): unmatched videos from clean channels and fixtures without highlights.
    if CommandLine.arguments.contains("--debug") {
        for competition in library.competitions {
            for entry in competition.rounds.flatMap(\.matches) {
                if entry.isPlayable, entry.fixture == nil, competition.usesFixtureData, !entry.spoilerProneTitle {
                    print("  unmatched [\(competition.id)] \(entry.homeName) | \(entry.awayName)")
                }
                if entry.availability == .noHighlights, competition.id != "LALIGA" {
                    print("  no highlight [\(competition.id)] \(entry.homeName) v \(entry.awayName)")
                }
            }
        }
    }
    // Spot-check neutral titles (team names + round, no results) for the latest round of each competition.
    if CommandLine.arguments.contains("--titles") {
        for competition in library.competitions {
            for entry in competition.rounds.first?.matches.prefix(3) ?? [] { print("  \(entry.neutralTitle)") }
        }
    }
}

func pad(_ value: Int, _ width: Int) -> String {
    let text = String(value)
    return String(repeating: " ", count: max(0, width - text.count)) + text
}

func findEnv() -> String? {
    var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    for _ in 0..<4 {
        let candidate = dir.appendingPathComponent(".env")
        if FileManager.default.fileExists(atPath: candidate.path) { return candidate.path }
        dir.deleteLastPathComponent()
    }
    return nil
}

await run()

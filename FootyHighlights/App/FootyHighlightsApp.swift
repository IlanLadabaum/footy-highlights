import SwiftUI

@main
struct FootyHighlightsApp: App {
    // One shared model: SwiftUI may build the App value more than once, and each model reads the Keychain.
    @State private var model = AppModel.shared

    init() {
        #if DEBUG && os(macOS)
            if SnapshotMode.outputDir != nil || PlayerTestMode.enabled { AppModel.automaticRefresh = false }
            if let dir = SnapshotMode.outputDir {
                DispatchQueue.main.async { SnapshotMode.run(outputDir: dir) }
            } else if PlayerTestMode.enabled {
                DispatchQueue.main.async { PlayerTestMode.run() }
            }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh") { Task { await model.refresh() } }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.isRefreshing || !model.hasYouTubeKey)
            }
        }

        #if os(macOS)
            Settings {
                SettingsView()
                    .environment(model)
            }
        #endif
    }
}

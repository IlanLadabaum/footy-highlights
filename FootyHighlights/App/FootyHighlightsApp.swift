import SwiftUI

@main
struct FootyHighlightsApp: App {
    @State private var model = AppModel()

    init() {
        #if DEBUG && os(macOS)
            if let dir = SnapshotMode.outputDir {
                DispatchQueue.main.async { SnapshotMode.run(outputDir: dir) }
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

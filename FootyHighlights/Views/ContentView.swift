import FootyKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [Route] = []

    var body: some View {
        Group {
            if model.hasYouTubeKey {
                NavigationStack(path: $path) {
                    CompetitionsView()
                        .navigationDestination(for: Route.self) { route in
                            switch route {
                            case .competition(let id): RoundsView(competitionId: id)
                            case .round(let id): RoundView(roundId: id)
                            case .player(let key): PlayerScreen(matchKey: key)
                            }
                        }
                }
            } else {
                SetupView()
            }
        }
        .task {
            await model.refresh()
        }
    }
}

/// Toolbar items shared by the browsing screens: refresh status and the Refresh button.
struct RefreshToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if model.isRefreshing {
                ProgressView().controlSize(.small)
            } else if !model.refreshErrors.isEmpty {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .help(model.refreshErrors.joined(separator: "\n"))
            }
            Button {
                Task { await model.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help(refreshHelp)
            .disabled(model.isRefreshing)
            #if os(macOS)
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
            #endif
        }
    }

    private var refreshHelp: String {
        guard let last = model.lastRefresh else { return "Refresh" }
        return "Refresh (last updated \(Formatting.relative(last)); refreshes at most every 15 minutes)"
    }
}

/// A short-lived banner with an Undo button, used after "Mark all as watched".
struct UndoBanner: View {
    let message: String
    let undo: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
            Button("Undo", action: undo)
                .keyboardShortcut("z", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 4)
        .padding(.bottom, 16)
        .task {
            try? await Task.sleep(for: .seconds(8))
            dismiss()
        }
    }
}

/// Holds the undo state for a screen's "Mark all as watched".
@MainActor
@Observable
final class UndoState {
    var message: String?
    private var previous: [MatchKey: MatchFlags] = [:]

    func offer(_ message: String, previous: [MatchKey: MatchFlags], undoManager: UndoManager?, model: AppModel) {
        self.message = message
        self.previous = previous
        undoManager?.registerUndo(withTarget: model) { model in
            MainActor.assumeIsolated { model.restore(previous) }
        }
        undoManager?.setActionName("Mark All as Watched")
    }

    func undo(model: AppModel) {
        model.restore(previous)
        message = nil
    }
}

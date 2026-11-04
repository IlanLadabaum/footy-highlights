import FootyKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.hasYouTubeKey {
                NavigationStack(path: $model.path) {
                    CompetitionsView()
                        .navigationDestination(for: Route.self) { route in
                            switch route {
                            case .competition(let id): RoundsView(competitionId: id)
                            case .round(let id): RoundView(roundId: id)
                            case .player(let key): PlayerScreen(mode: .single(key))
                            case .queue: PlayerScreen(mode: .queue)
                            }
                        }
                }
                .overlay(alignment: .bottomTrailing) { StartQueueButton() }
                .overlay(alignment: .top) { LoadingHighlightsBanner() }
                .animation(.easeInOut(duration: 0.25), value: model.isLoadingHighlights)
            } else {
                SetupView()
            }
        }
        .task {
            if AppModel.automaticRefresh { await model.refresh() }
        }
    }
}

/// Toolbar items shared by the browsing screens: refresh status and the Refresh button.
struct RefreshToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            QueueToolbarButton()
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

/// "Loading highlights…" while a refresh is fetching (launch and manual Refresh). It doesn't block the
/// cached list underneath, and it never appears on the player screen (nothing is drawn over the player).
struct LoadingHighlightsBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let onPlayer: Bool = {
            switch model.path.last {
            case .player, .queue: true
            default: false
            }
        }()
        if model.isLoadingHighlights, !onPlayer {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading highlights…")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .shadow(radius: 4)
            .padding(.top, 12)
            .allowsHitTesting(false)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

/// Floating "Start queue" button, bottom right, whenever the queue has videos (not on the player screen).
struct StartQueueButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let count = model.queuedEntries.count
        let onPlayer: Bool = {
            switch model.path.last {
            case .player, .queue: true
            default: false
            }
        }()
        if count > 0, !onPlayer {
            Button {
                model.startQueue()
            } label: {
                Label("Start queue (\(count))", systemImage: "play.fill")
                    .font(.headline)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .shadow(radius: 6)
            .padding(20)
            .help("Play the queued highlights in order")
        }
    }
}

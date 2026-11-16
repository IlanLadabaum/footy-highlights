import FootyKit
import Foundation
import Observation

/// One playback: a single match or the queue, and its YouTube player. It lives in the app model rather than
/// in the player screen, so it can move between the full player and the mini player without reloading.
@MainActor
@Observable
final class PlaybackSession {
    enum Mode: Hashable {
        case single(MatchKey)
        /// Plays the queue from the top, continuing automatically.
        case queue
    }

    let mode: Mode
    let controller: PlayerController
    /// The match currently loaded in the player.
    private(set) var currentKey: MatchKey
    /// Playing in the mini player window rather than on the player screen.
    var isMini = false

    /// Starts playing; nil when there's nothing playable.
    init?(mode: Mode, model: AppModel) {
        let first: MatchEntry?
        switch mode {
        case .single(let key):
            first = model.entry(key)
            // Watched works like email read status: opening the video marks it watched.
            if let first, !first.flags.watched { model.setWatched([first], true) }
            // Watching a queued match outside the queue takes it off the queue.
            if let first { model.dequeue(first.id) }
        case .queue:
            first = model.popQueue()
        }
        guard let first, let video = first.video else { return nil }
        self.mode = mode
        currentKey = first.id
        controller = PlayerController(videoId: video.id)
        if mode == .queue {
            // When a video ends, continue with the next one in the same player (keeps full screen).
            controller.nextVideo = { [weak self, weak model] in
                guard let self, let next = model?.popQueue(), let video = next.video else { return nil }
                currentKey = next.id
                return video.id
            }
        }
        controller.start()
    }

    #if DEBUG
        /// Test mode: wraps a controller that's already playing.
        init(testing controller: PlayerController, key: MatchKey) {
            mode = .single(key)
            currentKey = key
            self.controller = controller
        }
    #endif

    /// Skip: load the next queued video now. It's marked watched as it's reached.
    func advance(model: AppModel) {
        guard let next = model.popQueue(), let video = next.video else { return }
        currentKey = next.id
        controller.load(videoId: video.id)
    }

    func stop() { controller.stop() }

    /// The navigation route that shows this playback on the full player screen.
    var route: Route {
        switch mode {
        case .single(let key): .player(key)
        case .queue: .queue
        }
    }
}

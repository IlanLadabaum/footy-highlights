import Foundation

/// The viewer's last choices in YouTube's player, re-applied to every video. WebKit doesn't keep the embedded
/// player's own storage between launches, so the app remembers what the IFrame API can read and set.
/// Stored in UserDefaults, so it survives relaunches and app updates.
public struct PlayerPreferences: Equatable, Sendable {
    /// 0–100.
    public var volume: Int
    public var muted: Bool
    /// 1 is normal speed.
    public var playbackRate: Double

    public static let standard = PlayerPreferences(volume: 100, muted: false, playbackRate: 1)

    public init(volume: Int, muted: Bool, playbackRate: Double) {
        self.volume = min(100, max(0, volume))
        self.muted = muted
        self.playbackRate = playbackRate > 0 ? playbackRate : 1
    }

    private enum Key {
        static let volume = "player.volume"
        static let muted = "player.muted"
        static let rate = "player.playbackRate"
    }

    public static func load(from defaults: UserDefaults) -> PlayerPreferences {
        PlayerPreferences(
            volume: defaults.object(forKey: Key.volume) as? Int ?? standard.volume,
            muted: defaults.object(forKey: Key.muted) as? Bool ?? standard.muted,
            playbackRate: defaults.object(forKey: Key.rate) as? Double ?? standard.playbackRate)
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(volume, forKey: Key.volume)
        defaults.set(muted, forKey: Key.muted)
        defaults.set(playbackRate, forKey: Key.rate)
    }
}

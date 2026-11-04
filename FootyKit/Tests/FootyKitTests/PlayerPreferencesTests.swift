import Foundation
import Testing

@testable import FootyKit

struct PlayerPreferencesTests {
    @Test func defaultsWhenNothingSaved() {
        let defaults = UserDefaults(suiteName: "player-prefs-\(UUID())")!
        #expect(PlayerPreferences.load(from: defaults) == .standard)
    }

    @Test func savedChoicesComeBack() {
        let defaults = UserDefaults(suiteName: "player-prefs-\(UUID())")!
        PlayerPreferences(volume: 35, muted: true, playbackRate: 1.5).save(to: defaults)
        #expect(PlayerPreferences.load(from: defaults) == PlayerPreferences(volume: 35, muted: true, playbackRate: 1.5))
    }

    @Test func outOfRangeValuesAreClamped() {
        let prefs = PlayerPreferences(volume: 140, muted: false, playbackRate: 0)
        #expect(prefs.volume == 100)
        #expect(prefs.playbackRate == 1)
    }
}

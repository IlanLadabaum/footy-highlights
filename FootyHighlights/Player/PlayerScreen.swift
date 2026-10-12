import FootyKit
import SwiftUI

/// Placeholder until the player milestone (M3).
struct PlayerScreen: View {
    let matchKey: MatchKey
    @Environment(AppModel.self) private var model

    var body: some View {
        Text(model.entry(matchKey)?.neutralTitle ?? "")
    }
}

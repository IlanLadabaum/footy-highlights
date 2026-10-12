import FootyKit
import SwiftUI

/// First launch without a YouTube key: explains what's needed and takes the key.
struct SetupView: View {
    @Environment(AppModel.self) private var model
    @State private var youTubeKey = ""
    @State private var footballDataKey = ""
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Welcome to Footy Highlights").font(.largeTitle.weight(.semibold))
            Text("Spoiler-free football highlights from YouTube. To find videos, the app needs your own free YouTube API key.")
                .foregroundStyle(.secondary)
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text("YouTube API key (required)").font(.headline)
                    SecureField("Paste your YouTube Data API v3 key", text: $youTubeKey)
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: 16) {
                        Link("Get a key (Google Cloud Console)", destination: Formatting.youTubeKeyURL)
                        Link("Step-by-step guide", destination: Formatting.readmeURL)
                    }
                    .font(.callout)
                }
                .padding(8)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text("football-data.org key (optional)").font(.headline)
                    Text("Adds round numbers, matches without highlights and league tables.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    SecureField("Paste your football-data.org token", text: $footballDataKey)
                        .textFieldStyle(.roundedBorder)
                    Link("Register for a free key", destination: Formatting.footballDataKeyURL).font(.callout)
                }
                .padding(8)
            }
            HStack {
                Spacer()
                Button("Continue") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(youTubeKey.trimmingCharacters(in: .whitespaces).isEmpty || saving)
            }
        }
        .padding(40)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func save() {
        saving = true
        Task {
            if !footballDataKey.trimmingCharacters(in: .whitespaces).isEmpty {
                _ = KeyManager().save(.footballData, value: footballDataKey)
            }
            await model.saveKey(.youTube, value: youTubeKey)
            saving = false
        }
    }
}

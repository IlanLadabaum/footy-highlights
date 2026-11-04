import FootyKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            KeysSettings()
                .tabItem { Label("API Keys", systemImage: "key") }
            LeagueSettings()
                .tabItem { Label("Leagues", systemImage: "soccerball") }
            AdvancedSettings()
                .tabItem { Label("Advanced", systemImage: "gearshape.2") }
        }
        .frame(width: 560)
        .padding(20)
    }
}

struct KeysSettings: View {
    var body: some View {
        Form {
            KeyField(
                kind: .youTube, title: "YouTube API key", required: true,
                links: [
                    ("Get a key", Formatting.youTubeKeyURL), ("Enable YouTube Data API v3", Formatting.youTubeAPIURL),
                ])
            KeyField(
                kind: .footballData, title: "football-data.org key", required: false,
                links: [("Register for a free key", Formatting.footballDataKeyURL)])
            Link("Step-by-step setup guide", destination: Formatting.readmeURL)
        }
        .formStyle(.grouped)
    }
}

struct KeyField: View {
    let kind: APIKeyKind
    let title: String
    let required: Bool
    let links: [(String, URL)]
    @Environment(AppModel.self) private var model
    @State private var value = ""
    @State private var saved = false

    var body: some View {
        Section {
            SecureField(title, text: $value, prompt: Text(placeholder))
            HStack {
                Text(status).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if saved { Text("Saved").font(.caption).foregroundStyle(.green) }
                Button("Save") {
                    Task {
                        await model.saveKey(kind, value: value)
                        value = ""
                        saved = true
                    }
                }
                .disabled(value.trimmingCharacters(in: .whitespaces).isEmpty)
                if source == .file {
                    Button("Remove") {
                        Task { await model.saveKey(kind, value: "") }
                    }
                }
            }
            HStack(spacing: 16) {
                ForEach(links, id: \.1) { link in Link(link.0, destination: link.1) }
            }
            .font(.caption)
        } header: {
            Text(title + (required ? "" : " (optional)"))
        }
    }

    private var source: KeySource { model.keySources[kind] ?? .none }

    private var placeholder: String {
        source == .none ? "Paste key" : "Paste a new key to replace the saved one"
    }

    private var status: String {
        switch source {
        case .none: required ? "Not set. The app can't find highlights without it." : "Not set."
        case .file: "Saved on this Mac, in a file only your user account can read."
        case .envFile:
            "Using the key from the project's .env (developer build). A key saved here is only used if .env has none."
        }
    }
}

struct AdvancedSettings: View {
    @AppStorage(SettingsKeys.hideDurations) private var hideDurations = false
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Picker(
                "When a match has both cuts, show",
                selection: Binding(get: { model.defaultCut }, set: { model.setDefaultCut($0) })
            ) {
                Text("Extended highlights").tag(HighlightCut.extended)
                Text("Normal highlights").tag(HighlightCut.normal)
            }
            Text("Some channels post a normal and an extended highlight. You can still switch on each match.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Hide video durations", isOn: $hideDurations)
            Text(
                "Some matches have longer highlights than others, which can hint at the result. "
                    + "This hides lengths in the app's lists; YouTube's player still shows them."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}


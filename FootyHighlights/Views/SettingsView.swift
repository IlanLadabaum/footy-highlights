import FootyKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            KeysSettings()
                .tabItem { Label("API Keys", systemImage: "key") }
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
                links: [("Get a key", Formatting.youTubeKeyURL), ("Enable YouTube Data API v3", Formatting.youTubeAPIURL)])
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
                if source == .keychain {
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
        case .keychain: "Saved in your Keychain."
        case .envFile: "Using the key from the project's .env (developer build). A key saved here is only used if .env has none."
        }
    }
}

struct AdvancedSettings: View {
    @AppStorage(SettingsKeys.hideDurations) private var hideDurations = false

    var body: some View {
        Form {
            Toggle("Hide video durations", isOn: $hideDurations)
            Text(
                "Some matches have longer highlights than others, which can hint at the result. "
                    + "This also hides the total and remaining time in the player.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

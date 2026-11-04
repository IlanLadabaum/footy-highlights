import FootyKit
import SwiftUI

/// On/off toggle for every supported league, in priority order. Changes apply immediately.
struct LeagueToggleList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ForEach(model.config.competitionsByPriority) { competition in
            Toggle(
                isOn: Binding(
                    get: { model.isEnabled(competition.id) },
                    set: { model.setLeague(competition.id, enabled: $0) }
                )
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(competition.name)
                    Text(sourceNote(competition)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func sourceNote(_ competition: CompetitionConfig) -> String {
        let channels = model.sources(for: competition).compactMap { model.config.channels[$0]?.name }
        return "Highlights from " + channels.joined(separator: ", then ")
    }
}

/// "Add/remove leagues" sheet from the home page.
struct LeaguePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add or remove leagues").font(.title2.weight(.semibold)).padding(20)
            Form { LeagueToggleList() }
                .formStyle(.grouped)
            HStack {
                Text("Turned-off leagues are hidden and not downloaded.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 460, height: 520)
    }
}

/// First launch: choose leagues before seeing the home page.
struct FirstLeagueChoiceSheet: View {
    @Environment(AppModel.self) private var model
    @State private var chosen: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Which leagues do you follow?").font(.title2.weight(.semibold))
                Text("Only these appear on your home page and get downloaded. You can change this any time.")
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            Form {
                ForEach(model.config.competitionsByPriority) { competition in
                    Toggle(
                        competition.name,
                        isOn: Binding(
                            get: { chosen.contains(competition.id) },
                            set: { on in
                                if on { chosen.insert(competition.id) } else { chosen.remove(competition.id) }
                            }))
                }
            }
            .formStyle(.grouped)
            HStack {
                Button(chosen.count == model.config.competitions.count ? "Select none" : "Select all") {
                    chosen =
                        chosen.count == model.config.competitions.count ? [] : Set(model.config.competitions.map(\.id))
                }
                Spacer()
                Button("Continue") { model.setLeagues(chosen) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(chosen.isEmpty)
            }
            .padding(20)
        }
        .frame(width: 460, height: 520)
        .interactiveDismissDisabled()
    }
}

/// Settings → Leagues.
struct LeagueSettings: View {
    var body: some View {
        Form {
            Section {
                LeagueToggleList()
            } footer: {
                Text("Turned-off leagues are hidden from the home page and not downloaded, which saves API quota.")
            }
            SourceOrderSettings()
        }
        .formStyle(.grouped)
    }
}

/// Settings → Leagues: for leagues with more than one in-app source, which to use first and whether to fall back.
struct SourceOrderSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ForEach(model.config.competitionsByPriority.filter { !$0.sourceOrderOptions.isEmpty }) { competition in
            Section {
                Picker(
                    "Highlights from",
                    selection: Binding(
                        get: { model.sources(for: competition) },
                        set: { model.setSources($0, for: competition) })
                ) {
                    ForEach(competition.sourceOrderOptions, id: \.self) { order in
                        Text(label(order)).tag(order)
                    }
                }
                ForEach(competition.playableChannels, id: \.self) { key in
                    if let channel = model.config.channels[key] {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(channel.name).font(.callout.weight(.medium))
                            Text(channel.sourceNote ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                        .opacity(unavailable(channel) ? 0.5 : 1)
                    }
                }
                if competition.playableChannels.contains(where: { model.config.channels[$0].map(unavailable) ?? false })
                {
                    Text("Add a football-data.org key in the API Keys tab to use the sources that need it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("\(competition.name) highlight sources")
            } footer: {
                Text("The first source is used where it has the match; the second fills in the matches it misses.")
            }
        }
    }

    private func label(_ order: [String]) -> String {
        let names = order.compactMap { model.config.channels[$0]?.name }
        return names.count == 1 ? "\(names[0]) only" : names.joined(separator: ", then ")
    }

    /// Needs fixture data the viewer hasn't set up.
    private func unavailable(_ channel: ChannelConfig) -> Bool {
        channel.needsFixtureData && !model.hasFootballDataKey
    }
}

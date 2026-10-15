import FootyKit
import SwiftUI

/// Landing page: every competition, those with unwatched highlights first.
struct CompetitionsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @State private var confirmMarkAll: CompetitionSummary?
    @State private var undo = UndoState()
    @State private var showLeaguePicker = false

    private let columns = [GridItem(.adaptive(minimum: 240), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let error = model.storeError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                let visible = model.visibleCompetitions
                if visible.isEmpty, !model.needsLeagueChoice {
                    Text("No leagues selected. Use “Add/remove leagues” to choose some.").foregroundStyle(.secondary)
                } else {
                    section("New stuff to watch", visible.filter { $0.unwatchedCount > 0 }, emptyText: "You're all caught up.")
                    section("Nothing new", visible.filter { $0.unwatchedCount == 0 }, emptyText: nil)
                }
            }
            .padding(24)
            .padding(.bottom, 60)  // room for the floating Start queue button
        }
        .navigationTitle("Footy Highlights")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    showLeaguePicker = true
                } label: {
                    Label("Add/remove leagues", systemImage: "slider.horizontal.3")
                        .labelStyle(.titleAndIcon)
                }
                .help("Choose which leagues appear here")
            }
            RefreshToolbar()
        }
        .sheet(isPresented: $showLeaguePicker) { LeaguePickerSheet().environment(model) }
        .sheet(isPresented: .constant(model.needsLeagueChoice)) { FirstLeagueChoiceSheet().environment(model) }
        .overlay(alignment: .bottom) {
            if let message = undo.message {
                UndoBanner(message: message, undo: { undo.undo(model: model) }, dismiss: { undo.message = nil })
            }
        }
        .confirmationDialog(
            "Mark every \(confirmMarkAll?.config.name ?? "") highlight as watched?",
            isPresented: Binding(get: { confirmMarkAll != nil }, set: { if !$0 { confirmMarkAll = nil } }),
            presenting: confirmMarkAll
        ) { competition in
            Button("Mark \(competition.unwatchedCount) as Watched") { markAll(competition) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This affects the whole competition. You can undo it afterwards.")
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ competitions: [CompetitionSummary], emptyText: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.weight(.semibold))
            if competitions.isEmpty {
                if let emptyText {
                    Text(model.isRefreshing && model.library.competitions.allSatisfy(\.rounds.isEmpty)
                         ? "Looking for highlights…" : emptyText)
                        .foregroundStyle(.secondary)
                }
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(competitions) { competition in
                        CompetitionTile(competition: competition) { confirmMarkAll = competition }
                    }
                }
            }
        }
    }

    private func markAll(_ competition: CompetitionSummary) {
        let entries = competition.rounds.flatMap(\.matches).filter(\.isUnwatched)
        let previous = model.setWatched(entries, true)
        undo.offer("Marked \(entries.count) \(competition.config.name) highlights as watched",
                   previous: previous, undoManager: undoManager, model: model)
    }
}

struct CompetitionTile: View {
    let competition: CompetitionSummary
    let markAll: () -> Void

    var body: some View {
        NavigationLink(value: Route.competition(competition.id)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(competition.config.name).font(.headline)
                    Spacer()
                    UnwatchedBadge(count: competition.unwatchedCount)
                }
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomTrailing) {
            if competition.unwatchedCount > 0 {
                Button("Mark all as watched", action: markAll)
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .padding(12)
            }
        }
    }

    private var subtitle: String {
        guard let latest = competition.rounds.first else { return "No highlights yet" }
        return "Latest: \(latest.name)"
    }
}

struct UnwatchedBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text("\(count) new")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor, in: Capsule())
                .foregroundStyle(.white)
                .accessibilityLabel("\(count) unwatched")
        }
    }
}

import FootyKit
import SwiftUI

/// Toolbar button showing the queue's size; opens the queue.
struct QueueToolbarButton: View {
    @Environment(AppModel.self) private var model
    @State private var showing = false

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            Label(model.queuedEntries.isEmpty ? "Queue" : "Queue (\(model.queuedEntries.count))", systemImage: "list.bullet.rectangle")
                .labelStyle(.titleAndIcon)
        }
        .help("Open the queue")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            QueueView { showing = false }
                .environment(model)
        }
    }
}

/// The queue: drag to reorder, remove items, clear, start.
struct QueueView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKeys.hideDurations) private var hideDurations = false
    let close: () -> Void

    var body: some View {
        let entries = model.queuedEntries
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Queue").font(.headline)
                Spacer()
                Text(summary(entries)).font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            Divider()
            if entries.isEmpty {
                Text("Add highlights with the Queue button on any match, then start the queue here.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(24)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                List {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        HStack(spacing: 10) {
                            Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary).frame(width: 22, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(entry.homeName) v \(entry.awayName)")
                                Text(detail(entry)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                model.dequeue(entry.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help("Remove from the queue")
                        }
                        .padding(.vertical, 2)
                    }
                    .onMove { model.moveQueue(from: $0, to: $1) }
                }
                .listStyle(.plain)
                .frame(minHeight: 160, maxHeight: 420)
            }
            Divider()
            HStack {
                Button("Clear Queue", role: .destructive) { model.clearQueue() }
                    .disabled(entries.isEmpty)
                Spacer()
                Button {
                    close()
                    model.startQueue()
                } label: {
                    Label("Start Queue", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(entries.isEmpty)
            }
            .padding(12)
        }
        .frame(width: 420)
    }

    private func detail(_ entry: MatchEntry) -> String {
        let competition = model.config.competition(id: entry.competitionId)?.name ?? ""
        let round = model.library.round(entry.roundId)?.name
        var parts = [competition] + (round.map { [$0] } ?? [])
        if !hideDurations, let seconds = entry.video?.durationSeconds { parts.append(Formatting.duration(seconds)) }
        return parts.joined(separator: " · ")
    }

    private func summary(_ entries: [MatchEntry]) -> String {
        guard !entries.isEmpty else { return "Empty" }
        let count = "\(entries.count) video\(entries.count == 1 ? "" : "s")"
        guard !hideDurations else { return count }
        let total = entries.compactMap(\.video?.durationSeconds).reduce(0, +)
        return "\(count) · \(Formatting.duration(total))"
    }
}

import FootyKit
import SwiftUI

/// "Restore queue": lists the queue as it was when it was started; picking a match puts it and
/// everything after it back in the queue (marked unwatched) and plays from there.
struct RestoreQueueSheet: View {
    let entries: [MatchEntry]
    let pick: (MatchKey) -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Restore queue").font(.title2.weight(.semibold))
            Text(
                "Pick the match to start from. It and everything after it go back in the queue and are marked unwatched."
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            List(Array(entries.enumerated()), id: \.element.id) { index, entry in
                Button {
                    pick(entry.id)
                } label: {
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)
                        Text(entry.neutralTitle).lineLimit(1)
                        Spacer()
                        Image(systemName: "play.fill").foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(minHeight: 220)
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 460)
    }
}

import SwiftUI

struct QueueView: View {
    @EnvironmentObject private var player: FLACPlayer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Now Playing") {
                    if let song = player.currentSong {
                        Button { if let index = player.currentIndex { player.jump(toQueueIndex: index) } } label: { SongRow(song: song) }
                            .buttonStyle(.plain).songActions(song)
                    }
                }
                Section {
                    HStack {
                        Button { player.toggleShuffle() } label: {
                            Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(player.shuffleEnabled ? Color.accentColor : Color.secondary)
                        }
                        Button { player.cycleRepeatMode() } label: {
                            Label(player.repeatMode == .one ? "Repeat One" : "Repeat", systemImage: player.repeatMode == .one ? "repeat.1" : "repeat")
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(player.repeatMode == .off ? Color.secondary : Color.accentColor)
                        }
                    }.buttonStyle(.borderless)
                    ForEach(Array(player.upcomingSongs.enumerated()), id: \.offset) { offset, song in
                        Button { player.jump(toQueueIndex: (player.currentIndex ?? -1) + 1 + offset) } label: { SongRow(song: song) }
                            .buttonStyle(.plain).songActions(song)
                    }
                    .onMove { player.moveUpcoming(from: $0, to: $1) }
                    .onDelete { player.removeUpcoming(at: $0) }
                    if player.upcomingSongs.isEmpty { Text("Nothing up next").foregroundStyle(.secondary) }
                } header: { Text("Up Next") }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Queue")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) { Button("Clear") { player.clearUpNext() }.disabled(player.upcomingSongs.isEmpty) }
            }
        }
    }
}

import SwiftUI

struct QueueView: View {
    @ObservedObject var player: FLACPlayer
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                Section("Now Playing") {
                    if let current = player.currentSong {
                        SongRow(song: current, isPlaying: true)
                    }
                }
                Section("Up Next") {
                    ForEach(player.upcomingSongs) { song in
                        Button(action: {
                            if let idx = player.queue.firstIndex(of: song) {
                                player.playQueue(songs: player.queue, startIndex: idx)
                            }
                        }) {
                            SongRow(song: song)
                        }
                    }
                    .onMove { source, destination in player.moveInQueue(from: source, to: destination) }
                    .onDelete { offsets in player.removeFromQueue(at: offsets) }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Queue")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Shuffle") { player.shuffleUpcoming() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear") { player.clearQueue(); dismiss() }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - SongRow (used across the app)
struct SongRow: View {
    let song: Song
    var isPlaying: Bool = false

    var body: some View {
        HStack(spacing: 16) {
            if let art = song.artwork {
                Image(uiImage: art).resizable().scaledToFill()
                    .frame(width: 50, height: 50).cornerRadius(6).clipped()
            } else {
                Image(systemName: "music.note").resizable().scaledToFit()
                    .frame(width: 24, height: 24).padding(13).background(Color.gray.opacity(0.3)).cornerRadius(6)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.system(.body, design: .rounded).weight(isPlaying ? .bold : .semibold))
                    .foregroundColor(isPlaying ? .accentColor : .primary)
                    .lineLimit(1).truncationMode(.tail)
                Text(song.artist)
                    .font(.subheadline).foregroundColor(.secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            Text(song.durationFormatted).font(.caption).foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .listRowBackground(Color.clear)
        .listRowSeparator(.visible, edges: .bottom)
    }
}

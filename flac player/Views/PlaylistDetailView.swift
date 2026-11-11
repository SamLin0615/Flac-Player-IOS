import SwiftUI

struct PlaylistDetailView: View {
    let playlist: Playlist
    @ObservedObject var library: MusicLibrary
    @ObservedObject var player: FLACPlayer
    
    var body: some View {
        let songs = library.songsForPlaylist(playlist)
        
        List {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 20) {
                    Rectangle().fill(Color.accentColor.opacity(0.8)) // Playlist icon
                        .frame(width: 130, height: 130).cornerRadius(12).shadow(radius: 5)
                        .overlay(Image(systemName: "music.note.list").font(.largeTitle).foregroundColor(.white))
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(playlist.name).font(.title2.bold()).lineLimit(3)
                        Text("\(songs.count) Songs").font(.title3).foregroundColor(.secondary)
                        
                        HStack(spacing: 20) {
                            Button(action: { player.playQueue(songs: songs) }) {
                                Image(systemName: "play.circle.fill").resizable().frame(width: 44, height: 44).foregroundColor(.accentColor)
                            }.buttonStyle(.plain)
                            
                            Button(action: { player.play(songs: songs, shuffle: true) }) {
                                Image(systemName: "shuffle.circle").resizable().frame(width: 44, height: 44).foregroundColor(.secondary)
                            }.buttonStyle(.plain)
                        }
                        .padding(.top, 8)
                    }
                    Spacer()
                }
                .padding(.vertical, 24)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            // TRACKS
            ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                Button(action: { player.playQueue(songs: songs, startIndex: index) }) {
                    SongRow(song: song)
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                let current = library.playlists.first { $0.id == playlist.id } ?? playlist
                let available = Set(library.songs.map { $0.id })
                let visibleIndices = current.songIDs.indices.filter { available.contains(current.songIDs[$0]) }
                library.removeSongs(at: IndexSet(offsets.compactMap { visibleIndices.indices.contains($0) ? visibleIndices[$0] : nil }), from: current)
            }
        }
        .listStyle(.plain)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

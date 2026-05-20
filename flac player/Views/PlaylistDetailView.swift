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
                            
                            Button(action: { player.playQueue(songs: songs.shuffled()) }) {
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
            ForEach(songs) { song in
                Button(action: { player.playQueue(songs: songs, startIndex: songs.firstIndex(of: song) ?? 0) }) {
                    SongRow(song: song)
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                for idx in offsets { library.removeSong(songs[idx], from: playlist) }
            }
        }
        .listStyle(.plain)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

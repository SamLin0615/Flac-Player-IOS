import SwiftUI

struct AlbumDetailView: View {
    let album: String
    @ObservedObject var library: MusicLibrary
    @ObservedObject var player: FLACPlayer

    private var songs: [Song] {
        library.songs.filter { $0.album == album }
            .sorted { ($0.discNumber ?? 0, $0.trackNumber ?? 0) < ($1.discNumber ?? 0, $1.trackNumber ?? 0) }
    }

    var body: some View {
        List {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 20) {
                    if let firstSong = songs.first, let art = firstSong.artwork {
                        Image(uiImage: art).resizable().scaledToFill()
                            .frame(width: 130, height: 130).cornerRadius(12).shadow(radius: 5).clipped()
                    } else {
                        Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 130, height: 130).cornerRadius(12)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(album).font(.title2.bold()).lineLimit(3)
                        Text(songs.first?.artist ?? "Unknown").font(.title3).foregroundColor(.secondary).lineLimit(2)
                        
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

            ForEach(songs) { song in
                Button(action: { player.playQueue(songs: songs, startIndex: songs.firstIndex(of: song) ?? 0) }) {
                    SongRow(song: song)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

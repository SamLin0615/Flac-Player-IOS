import SwiftUI

struct ArtistDetailView: View {
    let artist: String
    @ObservedObject var library: MusicLibrary
    @ObservedObject var player: FLACPlayer

    private var songs: [Song] {
        library.songs.filter { $0.artist == artist }.sorted { $0.title < $1.title }
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
                        Text(artist).font(.largeTitle.bold()).lineLimit(3)
                        
                        HStack(spacing: 20) {
                            Button(action: { player.playQueue(songs: songs) }) {
                                Image(systemName: "play.circle.fill").resizable().frame(width: 44, height: 44).foregroundColor(.accentColor)
                            }.buttonStyle(.plain)
                            
                            Button(action: { player.playQueue(songs: songs.shuffled()) }) {
                                Image(systemName: "shuffle.circle").resizable().frame(width: 44, height: 44).foregroundColor(.secondary)
                            }.buttonStyle(.plain)
                        }
                        .padding(.top, 16)
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

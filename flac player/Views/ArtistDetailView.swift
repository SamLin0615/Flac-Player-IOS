import SwiftUI

struct ArtistDetailView: View {
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var player: FLACPlayer
    let artist: String

    private var albums: [Album] { library.albums.filter { $0.artist == artist } }
    private var songs: [Song] { albums.flatMap { $0.songs } }

    var body: some View {
        List {
            CollectionPlaybackHeader(songs: songs)
            Section("Albums") {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(albums) { album in
                            NavigationLink { AlbumDetailView(album: album) } label: { AlbumCard(album: album).frame(width: 150) }
                                .buttonStyle(.plain).collectionActions(album.songs)
                        }
                    }.padding(.vertical, 8)
                }.scrollIndicators(.hidden)
            }
            ForEach(albums) { album in
                Section(album.title) {
                    ForEach(album.songs) { song in
                        Button { player.play(songs: songs, startAt: songs.firstIndex(of: song) ?? 0) } label: { SongRow(song: song, showTrackNumber: true) }
                            .buttonStyle(.plain).songActions(song)
                    }
                }
            }
        }.listStyle(.plain).navigationTitle(artist)
    }
}

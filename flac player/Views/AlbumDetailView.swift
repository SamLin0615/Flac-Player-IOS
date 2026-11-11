import SwiftUI

struct AlbumDetailView: View {
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var player: FLACPlayer
    let album: Album

    private var currentAlbum: Album { library.albums.first { $0.id == album.id } ?? album }
    private var songs: [Song] { currentAlbum.songs }

    var body: some View {
        List {
            VStack(spacing: 12) {
                ArtworkView(artwork: currentAlbum.artwork, size: 220)
                Text(currentAlbum.title).font(.title2.bold()).multilineTextAlignment(.center)
                Text(currentAlbum.artist).foregroundStyle(.secondary)
                if let year = currentAlbum.year { Text(String(year)).font(.caption).foregroundStyle(.secondary) }
                CollectionPlaybackHeader(songs: songs)
            }.frame(maxWidth: .infinity).listRowSeparator(.hidden).collectionActions(songs)
            ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                Button { player.play(songs: songs, startAt: index) } label: { SongRow(song: song, showTrackNumber: true) }
                    .buttonStyle(.plain).songActions(song)
            }
        }.listStyle(.plain).navigationTitle(currentAlbum.title).navigationBarTitleDisplayMode(.inline)
    }
}

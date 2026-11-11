import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var player: FLACPlayer
    @State private var query = ""

    private var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var songs: [Song] {
        library.songs.filter { $0.title.localizedCaseInsensitiveContains(term) || $0.artist.localizedCaseInsensitiveContains(term) || $0.album.localizedCaseInsensitiveContains(term) }
    }
    private var albums: [Album] { library.albums.filter { $0.title.localizedCaseInsensitiveContains(term) || $0.artist.localizedCaseInsensitiveContains(term) } }
    private var artists: [String] { library.artists.filter { $0.localizedCaseInsensitiveContains(term) } }

    var body: some View {
        List {
            if !term.isEmpty {
                if !songs.isEmpty {
                    Section("Songs") {
                        ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                            Button { player.play(songs: songs, startAt: index) } label: { SongRow(song: song) }
                                .buttonStyle(.plain).songActions(song)
                        }
                    }
                }
                if !albums.isEmpty {
                    Section("Albums") {
                        ForEach(albums) { album in
                            NavigationLink { AlbumDetailView(album: album) } label: {
                                HStack { ArtworkView(artwork: album.artwork); VStack(alignment: .leading) { Text(album.title); Text(album.artist).font(.caption).foregroundStyle(.secondary) } }
                            }.collectionActions(album.songs)
                        }
                    }
                }
                if !artists.isEmpty {
                    Section("Artists") {
                        ForEach(artists, id: \.self) { artist in NavigationLink(artist) { ArtistDetailView(artist: artist) } }
                    }
                }
            }
        }
        .overlay {
            if term.isEmpty { ContentUnavailableView("Find Your Music", systemImage: "magnifyingglass", description: Text("Search songs, albums, and artists.")) }
            else if songs.isEmpty && albums.isEmpty && artists.isEmpty { ContentUnavailableView.search(text: term) }
        }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Songs, albums, artists")
    }
}

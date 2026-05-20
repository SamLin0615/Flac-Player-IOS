import SwiftUI

struct SearchView: View {
    @ObservedObject var library: MusicLibrary
    @ObservedObject var player: FLACPlayer
    @State private var query = ""
    @Environment(\.dismiss) var dismiss

    var filtered: [Song] {
        if query.isEmpty { return [] }
        return library.songs.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.artist.localizedCaseInsensitiveContains(query) ||
            $0.album.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationView {
            List(filtered) { song in
                Button(action: {
                    player.playQueue(songs: library.songs,
                                     startIndex: library.songs.firstIndex(of: song) ?? 0)
                    dismiss()
                }) {
                    SongRow(song: song)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
            .navigationTitle("Search")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

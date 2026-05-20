import SwiftUI

struct PlaylistsListView: View {
    @ObservedObject var library: MusicLibrary
    @ObservedObject var player: FLACPlayer
    @State private var newPlaylistName = ""

    var body: some View {
        NavigationView {
            List {
                ForEach(library.playlists) { playlist in
                    NavigationLink(destination: PlaylistDetailView(playlist: playlist, library: library, player: player)) {
                        Text(playlist.name)
                    }
                }
                .onDelete { offsets in
                    for idx in offsets {
                        library.deletePlaylist(library.playlists[idx])
                    }
                }
            }
            .navigationTitle("Playlists")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { newPlaylistName = "" }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .alert("New Playlist", isPresented: $newPlaylistName.presentOnce()) {
            TextField("Name", text: $newPlaylistName)
            Button("Create") { library.createPlaylist(name: newPlaylistName) }
            Button("Cancel", role: .cancel) {}
        }
    }
}
// Helper for alert
extension Binding where Value == String {
    func presentOnce() -> Binding<Bool> {
        Binding<Bool>(
            get: { !wrappedValue.isEmpty },
            set: { _ in }
        )
    }
}

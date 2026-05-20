import SwiftUI

struct AddToPlaylistView: View {
    @EnvironmentObject var library: MusicLibrary
    var player: FLACPlayer
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(library.playlists) { playlist in
                    Button(action: {
                        if let song = player.currentSong {
                            library.addSong(song, to: playlist)
                        }
                        dismiss()
                    }) {
                        Text(playlist.name)
                    }
                }
            }
            .navigationTitle("Add to Playlist")
        }
    }
}

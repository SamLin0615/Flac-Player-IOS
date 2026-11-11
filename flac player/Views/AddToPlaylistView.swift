import SwiftUI

struct AddToPlaylistView: View {
    @EnvironmentObject private var library: MusicLibrary
    @Environment(\.dismiss) private var dismiss
    let songs: [Song]
    @State private var creatingPlaylist = false
    @State private var name = ""

    var body: some View {
        NavigationStack {
            List {
                Button("New Playlist…", systemImage: "plus") { name = ""; creatingPlaylist = true }
                ForEach(library.playlists) { playlist in
                    Button {
                        library.addSongs(songs, to: playlist)
                        dismiss()
                    } label: { Label(playlist.name, systemImage: "music.note.list").frame(minHeight: 44) }
                }
            }
            .navigationTitle("Add to Playlist")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .alert("New Playlist", isPresented: $creatingPlaylist) {
                TextField("Playlist name", text: $name)
                Button("Create & Add") {
                    let playlist = library.createPlaylist(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
                    library.addSongs(songs, to: playlist)
                    dismiss()
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

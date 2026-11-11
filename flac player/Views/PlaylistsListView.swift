import SwiftUI

struct PlaylistsListView: View {
    @EnvironmentObject private var library: MusicLibrary
    @State private var creatingPlaylist = false
    @State private var renamingPlaylist: Playlist?
    @State private var showingRename = false
    @State private var name = ""

    var body: some View {
        List {
            Section("Smart Lists") {
                NavigationLink { SongListView(title: "Recently Added", songs: library.recentlyAdded) } label: { Label("Recently Added", systemImage: "plus.circle") }
                NavigationLink { SongListView(title: "Recently Played", songs: library.recentlyPlayed) } label: { Label("Recently Played", systemImage: "clock") }
                NavigationLink { SongListView(title: "Most Played", songs: library.mostPlayed) } label: { Label("Most Played", systemImage: "chart.bar") }
            }
            Section("My Playlists") {
                if library.playlists.isEmpty { Text("Create a playlist to collect your favorites.").foregroundStyle(.secondary) }
                ForEach(library.playlists) { playlist in
                    PlaylistLibraryRow(playlist: playlist) {
                        renamingPlaylist = playlist; name = playlist.name; showingRename = true
                    }
                }
            }
        }
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New Playlist", systemImage: "plus") { name = ""; creatingPlaylist = true }
            }
        }
        .alert("New Playlist", isPresented: $creatingPlaylist) {
            TextField("Playlist name", text: $name)
            Button("Create") { library.createPlaylist(name: name.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Playlist", isPresented: $showingRename) {
            TextField("Playlist name", text: $name)
            Button("Save") {
                if let playlist = renamingPlaylist { library.renamePlaylist(playlist, name: name.trimmingCharacters(in: .whitespacesAndNewlines)) }
            }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct PlaylistLibraryRow: View {
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var player: FLACPlayer
    let playlist: Playlist
    let rename: () -> Void
    @State private var addingToPlaylist = false
    private var songs: [Song] { library.songsForPlaylist(playlist) }

    var body: some View {
        NavigationLink { PlaylistDetailView(playlist: playlist) } label: {
            HStack {
                Image(systemName: "music.note.list").font(.title2).frame(width: 44, height: 44)
                VStack(alignment: .leading) { Text(playlist.name); Text("\(songs.count) songs").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .contextMenu {
            Button { player.play(songs: songs) } label: { Label("Play", systemImage: "play.fill") }
            Button { player.play(songs: songs, shuffle: true) } label: { Label("Shuffle", systemImage: "shuffle") }
            Button { player.playNext(songs) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
            Button { player.addToQueue(songs) } label: { Label("Add to Queue", systemImage: "text.badge.plus") }
            Button { addingToPlaylist = true } label: { Label("Add to Playlist…", systemImage: "music.note.list") }
            Button("Rename", systemImage: "pencil", action: rename)
            Button("Delete", systemImage: "trash", role: .destructive) { library.deletePlaylist(playlist) }
        }
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) { library.deletePlaylist(playlist) }
            Button("Rename", systemImage: "pencil", action: rename).tint(.blue)
        }
        .sheet(isPresented: $addingToPlaylist) { AddToPlaylistView(songs: songs) }
    }
}

import SwiftUI

struct PlaylistDetailView: View {
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var player: FLACPlayer
    let playlist: Playlist
    @State private var addingSongs = false

    private var current: Playlist { library.playlists.first { $0.id == playlist.id } ?? playlist }
    private var songs: [Song] { library.songsForPlaylist(current) }
    private var visibleIndices: [Int] {
        let available = Set(library.songs.map { $0.id })
        return current.songIDs.indices.filter { available.contains(current.songIDs[$0]) }
    }

    var body: some View {
        List {
            Section {
                CollectionPlaybackHeader(songs: songs).collectionActions(songs)
                Button("Add Songs", systemImage: "plus") { addingSongs = true }.frame(minHeight: 44)
            }
            Section("Songs") {
                ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                    Button { player.play(songs: songs, startAt: index) } label: { SongRow(song: song) }
                        .buttonStyle(.plain).songActions(song)
                }
                .onDelete { offsets in
                    library.removeSongs(at: IndexSet(offsets.compactMap { visibleIndices.indices.contains($0) ? visibleIndices[$0] : nil }), from: current)
                }
                .onMove { offsets, destination in
                    let indices = visibleIndices
                    let storedOffsets = IndexSet(offsets.compactMap { indices.indices.contains($0) ? indices[$0] : nil })
                    let storedDestination = destination < indices.count ? indices[max(0, destination)] : current.songIDs.count
                    library.moveSongs(from: storedOffsets, to: storedDestination, in: current)
                }
            }
        }
        .navigationTitle(current.name)
        .toolbar { EditButton() }
        .sheet(isPresented: $addingSongs) { LibrarySongPicker(playlist: current) }
    }
}

struct LibrarySongPicker: View {
    @EnvironmentObject private var library: MusicLibrary
    @Environment(\.dismiss) private var dismiss
    let playlist: Playlist
    @State private var search = ""
    @State private var selection: Set<String> = []

    private var songs: [Song] {
        library.songs.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.artist.localizedCaseInsensitiveContains(search) || $0.album.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List(songs) { song in
                Button {
                    if !selection.insert(song.id).inserted { selection.remove(song.id) }
                } label: {
                    HStack {
                        SongRow(song: song)
                        Image(systemName: selection.contains(song.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selection.contains(song.id) ? Color.accentColor : Color.secondary)
                    }
                }.buttonStyle(.plain)
                    .accessibilityLabel("\(song.title), \(selection.contains(song.id) ? "selected" : "not selected")")
                    .songActions(song)
            }
            .navigationTitle("Add Songs")
            .searchable(text: $search, prompt: "Search your library")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add (\(selection.count))") {
                        library.addSongs(library.songs.filter { selection.contains($0.id) }, to: playlist)
                        dismiss()
                    }.disabled(selection.isEmpty)
                }
            }
        }
    }
}

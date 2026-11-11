import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var player: FLACPlayer
    @State private var showingPlayer = false
    @State private var restoredPlayback = false

    var body: some View {
        TabView {
            Tab("Library", systemImage: "music.note.house") {
                NavigationStack { LibraryView() }
            }
            Tab("Playlists", systemImage: "music.note.list") {
                NavigationStack { PlaylistsListView() }
            }
            Tab(role: .search) {
                NavigationStack { SearchView() }
            }
        }
        .tabViewBottomAccessory {
            if player.currentSong != nil {
                MiniPlayerView { showingPlayer = true }
            }
        }
        .sheet(isPresented: $showingPlayer) {
            FullPlayerView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            player.onTrackPlayed = { [weak library] song in library?.recordPlay(song) }
            restorePlaybackIfNeeded()
        }
        .onChange(of: library.songs) { _, _ in restorePlaybackIfNeeded() }
    }

    private func restorePlaybackIfNeeded() {
        guard !restoredPlayback, !library.songs.isEmpty else { return }
        restoredPlayback = true
        player.restoreSession(using: library)
    }
}

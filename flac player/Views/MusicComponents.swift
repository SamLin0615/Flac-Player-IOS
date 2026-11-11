import SwiftUI
import UIKit

struct ArtworkView: View {
    let artwork: UIImage?
    var size: CGFloat = 56

    var body: some View {
        Group {
            if let artwork = artwork {
                Image(uiImage: artwork).resizable().scaledToFill()
            } else {
                Rectangle().fill(.quaternary)
                    .overlay { Image(systemName: "music.note").font(.title).foregroundStyle(.secondary) }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size > 100 ? 16 : 8))
        .accessibilityHidden(true)
    }
}

struct SongRow: View {
    @EnvironmentObject private var player: FLACPlayer
    let song: Song
    var showTrackNumber = false

    private var isCurrent: Bool { player.currentSong?.id == song.id }

    var body: some View {
        HStack(spacing: 12) {
            if showTrackNumber {
                Text(song.trackNumber.map(String.init) ?? "–")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 24)
            }
            ArtworkView(artwork: song.artwork, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title).font(.body.weight(.medium))
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.primary).lineLimit(1)
                Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if isCurrent {
                Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel(player.isPlaying ? "Now playing" : "Playback paused")
            }
            Text(song.durationFormatted).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4).frame(minHeight: 52).contentShape(Rectangle())
    }
}

struct CollectionPlaybackHeader: View {
    @EnvironmentObject private var player: FLACPlayer
    let songs: [Song]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button { player.play(songs: songs) } label: { Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 44) }
                Button { player.play(songs: songs, shuffle: true) } label: { Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity, minHeight: 44) }
            }
            .buttonStyle(.bordered).disabled(songs.isEmpty)
            Text("\(songs.count) songs · \(MusicFormatting.duration(songs.reduce(0) { $0 + $1.duration }))")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 8)
    }
}

struct AlbumCard: View {
    let album: Album
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geometry in
                ArtworkView(artwork: album.artwork, size: geometry.size.width)
            }.aspectRatio(1, contentMode: .fit)
            Text(album.title).font(.headline).lineLimit(1)
            Text(album.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if let year = album.year { Text(String(year)).font(.caption2).foregroundStyle(.secondary) }
        }
    }
}

enum MusicFormatting {
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct SongActions: ViewModifier {
    @EnvironmentObject private var player: FLACPlayer
    let song: Song
    @State private var addingToPlaylist = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button { player.playNext([song]) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
                Button { player.addToQueue([song]) } label: { Label("Add to Queue", systemImage: "text.badge.plus") }
                Button { addingToPlaylist = true } label: { Label("Add to Playlist…", systemImage: "music.note.list") }
            }
            .swipeActions(edge: .leading) {
                Button { player.playNext([song]) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }.tint(.indigo)
            }
            .swipeActions(edge: .trailing) {
                Button { player.addToQueue([song]) } label: { Label("Add to Queue", systemImage: "text.badge.plus") }.tint(.orange)
            }
            .sheet(isPresented: $addingToPlaylist) { AddToPlaylistView(songs: [song]) }
    }
}

private struct CollectionActions: ViewModifier {
    @EnvironmentObject private var player: FLACPlayer
    let songs: [Song]
    @State private var addingToPlaylist = false

    func body(content: Content) -> some View {
        content.contextMenu {
            Button { player.play(songs: songs) } label: { Label("Play", systemImage: "play.fill") }
            Button { player.play(songs: songs, shuffle: true) } label: { Label("Shuffle", systemImage: "shuffle") }
            Button { player.playNext(songs) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
            Button { player.addToQueue(songs) } label: { Label("Add to Queue", systemImage: "text.badge.plus") }
            Button { addingToPlaylist = true } label: { Label("Add to Playlist…", systemImage: "music.note.list") }
        }
        .sheet(isPresented: $addingToPlaylist) { AddToPlaylistView(songs: songs) }
    }
}

extension View {
    func songActions(_ song: Song) -> some View { modifier(SongActions(song: song)) }
    func collectionActions(_ songs: [Song]) -> some View { modifier(CollectionActions(songs: songs)) }
}

struct SongListView: View {
    @EnvironmentObject private var player: FLACPlayer
    let title: String
    let songs: [Song]

    var body: some View {
        List {
            CollectionPlaybackHeader(songs: songs)
            ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                Button { player.play(songs: songs, startAt: index) } label: { SongRow(song: song) }
                    .buttonStyle(.plain).songActions(song)
            }
        }
        .overlay { if songs.isEmpty { ContentUnavailableView("No Songs Yet", systemImage: "music.note", description: Text("Songs will appear here as you build and listen to your library.")) } }
        .navigationTitle(title)
    }
}

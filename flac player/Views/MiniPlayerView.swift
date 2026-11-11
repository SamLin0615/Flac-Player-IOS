import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject private var player: FLACPlayer
    let openPlayer: () -> Void

    var body: some View {
        if let song = player.currentSong {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button(action: openPlayer) {
                        HStack(spacing: 10) {
                            ArtworkView(artwork: song.artwork, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Open player: \(song.title), \(song.artist)")
                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3).frame(width: 44, height: 44)
                    }.accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                    Button { player.next() } label: {
                        Image(systemName: "forward.end.fill").font(.title3).frame(width: 44, height: 44)
                    }.accessibilityLabel("Next track")
                }.padding(.horizontal).padding(.vertical, 6)
                ProgressView(value: min(1, max(0, player.currentTime / max(song.duration, 1))))
                    .tint(.accentColor).frame(height: 2).accessibilityHidden(true)
            }
        }
    }
}

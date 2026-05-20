import SwiftUI

struct MiniPlayerView: View {
    @ObservedObject var player: FLACPlayer
    @Binding var playerOffsetY: CGFloat
    var isPlayerVisible: Bool

    var body: some View {
        if let song = player.currentSong, !isPlayerVisible {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.8))
                        .frame(width: geo.size.width * (player.currentTime / max(song.duration, 1)), height: 2)
                }
                .frame(height: 2)

                HStack(spacing: 16) {
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { playerOffsetY = 0 }
                    }) {
                        HStack(spacing: 12) {
                            if let art = song.artwork {
                                Image(uiImage: art).resizable().scaledToFill()
                                    .frame(width: 48, height: 48).cornerRadius(6).clipped()
                            } else {
                                Image(systemName: "music.note").resizable().scaledToFit()
                                    .frame(width: 24, height: 24).padding(12)
                                    .background(Color.gray.opacity(0.3)).cornerRadius(6)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(song.title).font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .lineLimit(1).truncationMode(.tail)
                                Text(song.artist).font(.caption).foregroundColor(.secondary)
                                    .lineLimit(1).truncationMode(.tail)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button(action: { player.isPlaying ? player.pause() : player.resume() }) {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2).foregroundColor(.primary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.2), radius: 15, y: 8)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }
}

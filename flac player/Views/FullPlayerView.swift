import SwiftUI

struct FullPlayerView: View {
    @EnvironmentObject private var player: FLACPlayer
    @Environment(\.dismiss) private var dismiss
    @State private var seekTime: TimeInterval = 0
    @State private var seeking = false
    @State private var showingQueue = false
    @State private var showingEQ = false
    @State private var showingLyrics = false
    @State private var addingToPlaylist = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let song = player.currentSong {
                    VStack(spacing: 20) {
                        GeometryReader { geometry in
                            ArtworkView(artwork: song.artwork, size: min(340, geometry.size.width))
                                .frame(maxWidth: .infinity)
                                .gesture(DragGesture(minimumDistance: 30).onEnded { value in
                                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                                    if value.translation.width < -50 { player.next() }
                                    else if value.translation.width > 50 { player.previous() }
                                })
                        }.frame(height: 340)
                        VStack(spacing: 6) {
                            Text(song.title).font(.title2.bold()).multilineTextAlignment(.center)
                            Text(song.artist).font(.title3).foregroundStyle(.secondary)
                            Text(song.album).font(.subheadline).foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                Text("FLAC · \(song.bitDepth)-bit / \(String(format: "%g", song.sampleRate / 1000)) kHz")
                                if player.replayGainMode != .off && (song.replayGainTrackDB != nil || song.replayGainAlbumDB != nil) { Text("RG").bold().accessibilityLabel("ReplayGain active") }
                                if !player.isEQBypassed { Text("EQ").bold().accessibilityLabel("Equalizer enabled") }
                            }.font(.caption).padding(.horizontal, 12).padding(.vertical, 6).background(.quaternary, in: Capsule())
                        }
                        VStack(spacing: 8) {
                            WaveformScrubber(duration: song.duration, amplitudes: player.currentAmplitude, currentTime: $seekTime, seeking: $seeking) { player.seek(to: $0) }
                            HStack {
                                Text(MusicFormatting.duration(seekTime))
                                Spacer()
                                Text("−" + MusicFormatting.duration(max(0, song.duration - seekTime)))
                            }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        transport
                        HStack {
                            Image(systemName: "speaker.fill").accessibilityHidden(true)
                            VolumeSlider().frame(minHeight: 44).accessibilityLabel("Playback volume")
                            AirPlayButton().frame(width: 44, height: 44).accessibilityLabel("Choose audio output")
                        }
                        HStack(spacing: 12) {
                            Button { showingLyrics = true } label: { Image(systemName: "quote.bubble").frame(maxWidth: .infinity, minHeight: 44) }
                                .accessibilityLabel("Lyrics").disabled(song.lyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
                            Button { showingQueue = true } label: { Image(systemName: "list.bullet").frame(maxWidth: .infinity, minHeight: 44) }.accessibilityLabel("Queue")
                            Button { showingEQ = true } label: { Image(systemName: "slider.horizontal.3").frame(maxWidth: .infinity, minHeight: 44) }.accessibilityLabel("Equalizer")
                            moreMenu.frame(maxWidth: .infinity)
                        }.font(.title3).buttonStyle(.bordered)
                        if let end = player.sleepTimerEndDate {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                let remaining = max(0, end.timeIntervalSince(context.date))
                                Text(remaining > 0 ? "Sleep in \(MusicFormatting.duration(remaining))" : "Fading out…")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } else if player.sleepAtEndOfTrack {
                            Text("Sleep at end of track").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.horizontal, 24).padding(.bottom, 24).frame(maxWidth: 600).frame(maxWidth: .infinity)
                } else {
                    ContentUnavailableView("Nothing Playing", systemImage: "music.note")
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Now Playing").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onAppear { seekTime = player.currentTime }
        .onChange(of: player.currentTime) { _, time in if !seeking { seekTime = time } }
        .onChange(of: player.currentSong?.id) { _, _ in seeking = false; seekTime = player.currentTime }
        .sheet(isPresented: $showingQueue) { QueueView().presentationDragIndicator(.visible) }
        .sheet(isPresented: $showingEQ) { EQView().presentationDragIndicator(.visible) }
        .sheet(isPresented: $showingLyrics) { if let song = player.currentSong { LyricsView(song: song).presentationDragIndicator(.visible) } }
        .sheet(isPresented: $addingToPlaylist) { if let song = player.currentSong { AddToPlaylistView(songs: [song]) } }
    }

    private var transport: some View {
        HStack(spacing: 12) {
            Button { player.toggleShuffle() } label: { Image(systemName: "shuffle").frame(width: 44, height: 44) }
                .foregroundStyle(player.shuffleEnabled ? Color.accentColor : Color.secondary)
                .accessibilityLabel(player.shuffleEnabled ? "Turn shuffle off" : "Turn shuffle on")
            Button { player.previous() } label: { Image(systemName: "backward.end.fill").font(.title).frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Previous track")
            Spacer(minLength: 0)
            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 64)).frame(width: 72, height: 72)
            }.accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            Spacer(minLength: 0)
            Button { player.next() } label: { Image(systemName: "forward.end.fill").font(.title).frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Next track")
            Button { player.cycleRepeatMode() } label: { Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat").frame(width: 44, height: 44) }
                .foregroundStyle(player.repeatMode == .off ? Color.secondary : Color.accentColor)
                .accessibilityLabel("Repeat: \(player.repeatMode.rawValue)")
        }.buttonStyle(.plain)
    }

    private var moreMenu: some View {
        Menu {
            Button("Add to Playlist…", systemImage: "music.note.list") { addingToPlaylist = true }
            Menu("Sleep Timer", systemImage: "moon") {
                Button("Off") { player.cancelSleepTimer() }
                ForEach([15, 30, 45, 60], id: \.self) { minutes in
                    Button("\(minutes) minutes") { player.setSleepTimer(minutes: Double(minutes)) }
                }
                Button("End of Track") { player.sleepAfterCurrentTrack() }
            }
            Menu("ReplayGain", systemImage: "waveform") {
                Picker("ReplayGain", selection: $player.replayGainMode) {
                    ForEach(ReplayGainMode.allCases, id: \.self) { mode in Text(mode.rawValue.capitalized).tag(mode) }
                }
            }
        } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }
            .accessibilityLabel("More playback options")
    }
}

struct WaveformScrubber: View {
    let duration: TimeInterval
    let amplitudes: [Float]
    @Binding var currentTime: TimeInterval
    @Binding var seeking: Bool
    let onSeek: (TimeInterval) -> Void

    private var bars: [Float] {
        guard !amplitudes.isEmpty else { return Array(repeating: 0.08, count: 50) }
        let count = min(50, amplitudes.count)
        return (0..<count).map { index in
            let lower = index * amplitudes.count / count
            let upper = (index + 1) * amplitudes.count / count
            let value = amplitudes[lower..<upper].max() ?? 0
            return value.isFinite ? min(1, max(0, value)) : 0
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let values = bars
            HStack(alignment: .center, spacing: 2) {
                ForEach(values.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Double(index) / Double(values.count) <= currentTime / max(duration, 1) ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(maxWidth: .infinity)
                        .frame(height: max(4, CGFloat(values[index]) * 60))
                }
            }
            .frame(height: 64).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in seeking = true; currentTime = position(value.location.x, width: geometry.size.width) }
                .onEnded { value in
                    currentTime = position(value.location.x, width: geometry.size.width)
                    onSeek(currentTime); seeking = false
                })
        }
        .frame(height: 64)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue(MusicFormatting.duration(currentTime))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: currentTime = min(duration, currentTime + 10)
            case .decrement: currentTime = max(0, currentTime - 10)
            @unknown default: return
            }
            onSeek(currentTime)
        }
    }

    private func position(_ x: CGFloat, width: CGFloat) -> TimeInterval {
        min(duration, max(0, Double(x / max(1, width)) * duration))
    }
}

import SwiftUI

struct FullPlayerView: View {
    @ObservedObject var player: FLACPlayer
    @EnvironmentObject var library: MusicLibrary
    @Binding var playerOffsetY: CGFloat
    var dismiss: () -> Void

    @State private var seekTime: TimeInterval = 0
    @State private var isSeeking = false
    @State private var showQueue = false
    @State private var showEQ = false
    @State private var showAddToPlaylist = false

    @State private var horizontalOffset: CGFloat = 0
    @State private var outerGestureActive = false
    @State private var artScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let art = player.currentSong?.artwork {
                Image(uiImage: art)
                    .resizable()
                    .scaledToFill()
                    .frame(width: ScreenBounds.current.width, height: ScreenBounds.current.height)
                    .clipped()
                    .blur(radius: 80)
                    .overlay(Color.black.opacity(0.5))
                    .ignoresSafeArea()
            }

            // Gesture layer (tap & swipe) – placed behind the UI
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    TapGesture()
                        .onEnded {
                            guard !outerGestureActive else { return }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.3)) {
                                if player.isPlaying { player.pause() } else { player.resume() }
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 30, coordinateSpace: .local)
                        .onChanged { value in
                            guard !outerGestureActive else { return }
                            let dx = value.translation.width
                            let dy = value.translation.height
                            if abs(dx) > abs(dy) {
                                horizontalOffset = dx
                            } else if dy > 80 {
                                dismiss()
                            }
                        }
                        .onEnded { value in
                            let dx = value.translation.width
                            let dy = value.translation.height
                            if dy < -60 {
                                showQueue = true
                            } else if abs(dx) > ScreenBounds.current.width * 0.4 {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                let direction: CGFloat = dx > 0 ? 1 : -1
                                withAnimation(.easeOut(duration: 0.2)) {
                                    horizontalOffset = direction * ScreenBounds.current.width
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    if dx > 0 { player.previous() }
                                    else { player.next() }
                                    withAnimation(.spring()) { horizontalOffset = 0 }
                                }
                            } else {
                                withAnimation(.spring(response: 0.3)) { horizontalOffset = 0 }
                            }
                        }
                )

            // Foreground UI
            VStack(spacing: 0) {
                Spacer().frame(height: 50)

                if let song = player.currentSong {
                    if let art = song.artwork {
                        Image(uiImage: art)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(player.isPlaying ? 4 : 16)
                            .shadow(color: .black.opacity(player.isPlaying ? 0.6 : 0.2),
                                    radius: player.isPlaying ? 25 : 10, y: 15)
                            .padding(.horizontal, player.isPlaying ? 16 : 40)
                            .scaleEffect(artScale)
                            .allowsHitTesting(false)
                    } else {
                        Image(systemName: "music.note")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 250)
                            .foregroundColor(.gray)
                            .padding(.horizontal, 32)
                            .scaleEffect(artScale)
                            .allowsHitTesting(false)
                    }

                    Spacer(minLength: 30)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(song.title)
                            .font(.title2.weight(.bold))
                            .foregroundColor(.white)
                            .lineLimit(1).truncationMode(.tail)
                            .minimumScaleFactor(0.8)
                        Text(song.artist)
                            .font(.title3)
                            .foregroundColor(.gray)
                            .lineLimit(1).truncationMode(.tail)
                        Text("FLAC \(Int(song.sampleRate/1000))kHz \(song.bitDepth)bit")
                            .font(.caption)
                            .foregroundColor(.gray.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 32)

                    Spacer(minLength: 20)

                    WaveformScrubber(
                        duration: song.duration,
                        amplitudes: player.currentAmplitude,
                        currentTime: $seekTime,
                        isSeeking: $isSeeking,
                        outerGestureActive: $outerGestureActive,
                        onSeek: { time in player.seek(to: time) }
                    )
                    .frame(height: 60)
                    .padding(.horizontal, 32)

                    Spacer(minLength: 20)

                    // Bottom toolbar – no overlay, buttons work natively
                    HStack {
                        Button(action: { showQueue = true }) {
                            Image(systemName: "list.bullet")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 60, height: 60)
                                .contentShape(Rectangle())
                        }
                        Spacer()
                        if let next = player.upcomingSongs.first {
                            VStack(spacing: 2) {
                                Text("Next")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(.gray.opacity(0.8))
                                    .textCase(.uppercase)
                                Text(next.title)
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 10)
                        } else { Spacer() }
                        Spacer()
                        Menu {
                            Button(action: { showAddToPlaylist = true }) {
                                Label("Add to Playlist", systemImage: "text.badge.plus")
                            }
                            Button(action: {
                                showEQ = true
                            }) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.title2)
                                    // 1. Expand the tappable area slightly so it's easier to hit
                                    .padding(10)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 60, height: 60)
                                .contentShape(Rectangle())
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
            .offset(x: horizontalOffset)
            .animation(.spring(response: 0.3), value: horizontalOffset)
        }
        .onAppear { horizontalOffset = 0 }
        .onChange(of: playerOffsetY) { _, offset in
            if offset < ScreenBounds.current.height * 0.5 {
                withAnimation(.spring()) { horizontalOffset = 0 }
            }
        }
        .preferredColorScheme(.dark)
        .onReceive(player.$currentTime) { time in
            if !isSeeking { seekTime = time }
        }
        .onReceive(player.$isPlaying) { playing in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                artScale = playing ? 1.0 : 0.9
            }
        }
        .sheet(isPresented: $showQueue) {
            QueueView(player: player)
                .presentationDetents([.fraction(0.85), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(white: 0.05))
        }
        .sheet(isPresented: $showEQ) { EQView(player: player) }
        .sheet(isPresented: $showAddToPlaylist) { AddToPlaylistView(player: player) }
    }
}

// MARK: - Waveform Scrubber (isolated gesture, bottom‑aligned bars)
struct WaveformScrubber: View {
    let duration: TimeInterval
    let amplitudes: [Float]
    @Binding var currentTime: TimeInterval
    @Binding var isSeeking: Bool
    @Binding var outerGestureActive: Bool
    var onSeek: (TimeInterval) -> Void

    @State private var dragInitialTime: TimeInterval = 0

    private var displayAmplitudes: [Float] {
        guard !amplitudes.isEmpty else { return [] }
        let maxBars = 50
        if amplitudes.count <= maxBars { return amplitudes }
        let step = amplitudes.count / maxBars
        return stride(from: 0, to: amplitudes.count, by: step).compactMap { i in
            i < amplitudes.count ? amplitudes[i] : nil
        }
    }

    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let bars = displayAmplitudes
            let barCount = bars.count
            if barCount > 0 {
                let spacing: CGFloat = 2
                let totalSpacing = CGFloat(barCount - 1) * spacing
                let barWidth = max(1, (totalWidth - totalSpacing) / CGFloat(barCount))
                let progress = duration > 0 ? currentTime / duration : 0

                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(0..<barCount, id: \.self) { i in
                        let barProgress = Double(i) / Double(barCount)
                        let filled = barProgress <= progress
                        RoundedRectangle(cornerRadius: 1)
                            .fill(filled ? Color.white : Color.white.opacity(0.3))
                            .frame(width: barWidth, height: max(4, 60 * CGFloat(bars[i])))
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { value in
                            outerGestureActive = true
                            if !isSeeking {
                                isSeeking = true
                                dragInitialTime = currentTime
                            }
                            let deltaProgress = value.translation.width / totalWidth
                            let deltaTime = deltaProgress * duration
                            currentTime = max(0, min(duration, dragInitialTime + deltaTime))
                        }
                        .onEnded { _ in
                            onSeek(currentTime)
                            isSeeking = false
                            outerGestureActive = false
                        }
                )
            } else {
                Rectangle().fill(Color.gray.opacity(0.3))
            }
        }
        .frame(height: 60)
    }
}

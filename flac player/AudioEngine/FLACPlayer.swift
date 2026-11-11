import Foundation
import Combine
import AudioToolbox
import AVFAudio
import MediaPlayer
import UIKit
import os

enum RepeatMode: String, Codable {
    case off, all, one
    var next: RepeatMode {
        switch self { case .off: return .all; case .all: return .one; case .one: return .off }
    }
}

enum ReplayGainMode: String, CaseIterable { case off, track, album }

private final class PlaybackContext {
    let file: ExtAudioFileRef
    let sampleRate: Double
    let channels: Int
    let totalFrames: Int64
    let buffers: [RingBuffer]
    let lock: UnsafeMutablePointer<os_unfair_lock> = {
        let pointer = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        pointer.initialize(to: os_unfair_lock())
        return pointer
    }()
    let wake = DispatchSemaphore(value: 0)
    let readers = DispatchGroup()
    var exiting = false
    var pendingSeek: Int64?
    var seekGeneration = 0
    var eof = false
    var endSignaled = false
    var elapsedFrames: Int64 = 0
    var playedFrames: Int64 = 0
    var gain: Float = 1
    var fadeRemaining: Int64 = 0
    var fadeTotal: Int64 = 0
    var fadeFinished = false

    init(file: ExtAudioFileRef, sampleRate: Double, channels: Int, totalFrames: Int64, position: Int64) {
        self.file = file
        self.sampleRate = sampleRate
        self.channels = channels
        self.totalFrames = totalFrames
        buffers = (0..<channels).map { _ in RingBuffer(capacityInFrames: max(4096, Int(sampleRate) * 4)) }
        pendingSeek = position
        elapsedFrames = position
    }
    deinit { lock.deinitialize(count: 1); lock.deallocate() }
}

final class FLACPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentSong: Song?
    @Published private(set) var currentIndex: Int?
    @Published private(set) var queue: [Song] = []
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var currentAmplitude: [Float] = []
    @Published var shuffleEnabled = false {
        didSet {
            requireMain()
            if oldValue != shuffleEnabled && !changingQueue { reorderForShuffle(); persistSession() }
        }
    }
    @Published var repeatMode: RepeatMode = .off { didSet { requireMain(); persistSession() } }
    @Published var replayGainMode: ReplayGainMode {
        didSet { requireMain(); UserDefaults.standard.set(replayGainMode.rawValue, forKey: "ReplayGainMode"); publishReplayGain() }
    }
    @Published var replayGainPreampDB: Double {
        didSet { requireMain(); UserDefaults.standard.set(replayGainPreampDB, forKey: "ReplayGainPreampDB"); publishReplayGain() }
    }
    @Published private(set) var currentEQPresetID: UUID?
    @Published private(set) var sleepTimerEndDate: Date?
    @Published private(set) var sleepAtEndOfTrack = false
    private(set) var originalQueue: [Song] = []
    var onTrackPlayed: ((Song) -> Void)? { didSet { requireMain() } }

    private var queueTokens: [UUID] = []
    private var originalTokens: [UUID] = []
    private var changingQueue = false
    private var restored = false
    private var audioUnit: AudioComponentInstance?
    private var context: PlaybackContext?
    private let readerQueue = DispatchQueue(label: "flac.reader", qos: .userInitiated)
    private let eqEngine = EQEngine()
    private var timer: AnyCancellable?
    private var observers = Set<AnyCancellable>()
    private var sleepWork: DispatchWorkItem?
    private var interruptionWasPlaying = false
    private var countedPlay = false
    private var endHandled = false
    private var lastPersist = Date.distantPast

    var eqFrequencies: [Double] { eqEngine.bandFreqs }
    var eqGains: [Double] { eqEngine.bandGains }
    var eqQs: [Double] { eqEngine.bandQs }
    var eqBandsCount: Int { eqEngine.bandCount }
    var isEQBypassed: Bool { eqEngine.bypassed }
    var preampGainDB: Double { eqEngine.preampGainDB }
    var effectivePreampDB: Double { eqEngine.effectivePreampDB }
    var autoPreamp: Bool { eqEngine.autoPreamp }
    var eqSampleRate: Double { eqEngine.sampleRate }
    var eqBandTypes: [EQFilterType] { eqEngine.bandTypes }
    var upcomingSongs: [Song] {
        guard let index = currentIndex else { return [] }
        return Array(queue.dropFirst(index + 1))
    }

    init() {
        precondition(Thread.isMainThread)
        replayGainMode = ReplayGainMode(rawValue: UserDefaults.standard.string(forKey: "ReplayGainMode") ?? "") ?? .off
        replayGainPreampDB = UserDefaults.standard.double(forKey: "ReplayGainPreampDB")
        currentEQPresetID = eqEngine.selectedPresetID
        observe(.remotePlay) { $0.resume() }
        observe(.remotePause) { $0.pause() }
        observe(.remoteTogglePlayPause) { $0.togglePlayPause() }
        observe(.remoteNext) { $0.next() }
        observe(.remotePrevious) { $0.previous() }
        observeNotification(.remoteSeek) { player, notification in
            if let time = notification.object as? TimeInterval { player.seek(to: time) }
        }
        observeNotification(.remoteRepeat) { player, notification in
            guard let raw = notification.object as? Int, let type = MPRepeatType(rawValue: raw) else { return }
            switch type { case .one: player.repeatMode = .one; case .all: player.repeatMode = .all; default: player.repeatMode = .off }
        }
        observeNotification(.remoteShuffle) { player, notification in
            guard let raw = notification.object as? Int, let type = MPShuffleType(rawValue: raw) else { return }
            player.shuffleEnabled = type != .off
        }
        observeNotification(AVAudioSession.interruptionNotification) { player, notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .began {
                player.interruptionWasPlaying = player.isPlaying
                player.pause()
            } else {
                let options = AVAudioSession.InterruptionOptions(rawValue: notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
                if player.interruptionWasPlaying && options.contains(.shouldResume) { player.resume() }
                player.interruptionWasPlaying = false
            }
        }
        observeNotification(AVAudioSession.routeChangeNotification) { player, notification in
            if let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
               AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable {
                player.interruptionWasPlaying = false
                player.pause()
            }
        }
        observe(AVAudioSession.mediaServicesWereResetNotification) { player in
            AudioSessionManager.shared.mediaServicesReset()
            guard let index = player.currentIndex else { return }
            let position = player.currentTime
            let playing = player.isPlaying
            player.prepare(index: index, position: position, autoplay: playing, continuingPlay: true)
        }
        observe(UIApplication.willResignActiveNotification) { $0.persistSession() }
    }

    deinit {
        timer?.cancel()
        sleepWork?.cancel()
        tearDown()
    }

    private func requireMain() { precondition(Thread.isMainThread, "Playback API must run on the main thread") }
    private func observe(_ name: Notification.Name, action: @escaping (FLACPlayer) -> Void) {
        observeNotification(name) { player, _ in action(player) }
    }
    private func observeNotification(_ name: Notification.Name, action: @escaping (FLACPlayer, Notification) -> Void) {
        NotificationCenter.default.publisher(for: name).receive(on: DispatchQueue.main)
            .sink { [weak self] notification in if let self = self { action(self, notification) } }.store(in: &observers)
    }

    func play(songs: [Song], startAt: Int? = nil, shuffle: Bool = false) {
        requireMain()
        guard !songs.isEmpty else {
            stop()
            queue = []; queueTokens = []; originalQueue = []; originalTokens = []
            UserDefaults.standard.removeObject(forKey: "PlaybackSession.v1")
            return
        }
        changingQueue = true
        originalQueue = songs
        originalTokens = songs.map { _ in UUID() }
        queue = songs
        queueTokens = originalTokens
        let start = startAt ?? (shuffle ? Int.random(in: songs.indices) : 0)
        currentIndex = min(max(0, start), songs.count - 1)
        shuffleEnabled = shuffle
        changingQueue = false
        if shuffle { reorderForShuffle() }
        prepare(index: currentIndex ?? 0, autoplay: true)
    }

    func playQueue(songs: [Song], startIndex: Int = 0) { play(songs: songs, startAt: startIndex) }
    func play(song: Song) { play(songs: [song]) }
    func togglePlayPause() { requireMain(); isPlaying ? pause() : resume() }

    func pause() {
        requireMain()
        if let unit = audioUnit { AudioOutputUnitStop(unit) }
        isPlaying = false
        updateTimeAndStats()
        resetFade()
        timer?.cancel(); timer = nil
        NowPlayingManager.shared.update(elapsed: currentTime, isPlaying: false)
        persistSession()
    }

    func resume() {
        requireMain()
        guard let song = currentSong, let unit = audioUnit else { return }
        if let context = context {
            os_unfair_lock_lock(context.lock)
            let ended = context.endSignaled && context.pendingSeek == nil
            os_unfair_lock_unlock(context.lock)
            if ended { seek(to: 0) }
        }
        do { try AudioSessionManager.shared.configure(for: song.sampleRate) }
        catch { return }
        guard AudioOutputUnitStart(unit) == noErr else { return }
        isPlaying = true
        NowPlayingManager.shared.update(elapsed: currentTime, isPlaying: true)
        startTimer()
        if let end = sleepTimerEndDate, end <= Date() { beginFade() }
    }

    func stop(clearSong: Bool = true) {
        requireMain()
        pause()
        tearDown()
        AudioSessionManager.shared.deactivate()
        cancelSleepTimer()
        if clearSong {
            currentSong = nil; currentIndex = nil; currentTime = 0; currentAmplitude = []
            NowPlayingManager.shared.clear()
        }
    }

    func seek(to time: TimeInterval) {
        requireMain()
        guard time.isFinite, let context = context else { return }
        let position = min(max(0, time), Double(context.totalFrames) / context.sampleRate)
        os_unfair_lock_lock(context.lock)
        context.pendingSeek = Int64(position * context.sampleRate)
        context.seekGeneration += 1
        context.endSignaled = false
        os_unfair_lock_unlock(context.lock)
        endHandled = false
        currentTime = position
        context.wake.signal()
        eqEngine.reset()
        NowPlayingManager.shared.update(elapsed: position, isPlaying: isPlaying)
        persistSession()
    }

    func skip(by seconds: TimeInterval) { requireMain(); seek(to: currentTime + seconds) }
    func next() { requireMain(); advance(natural: false) }
    func previous() {
        requireMain()
        if currentTime > 3 { seek(to: 0); return }
        guard let index = currentIndex else { return }
        prepare(index: index > 0 ? index - 1 : (repeatMode == .all ? queue.count - 1 : 0), autoplay: true)
    }
    func jump(toQueueIndex index: Int) { requireMain(); guard queue.indices.contains(index) else { return }; prepare(index: index, autoplay: true) }

    private func advance(natural: Bool) {
        guard let index = currentIndex else { return }
        if natural && sleepAtEndOfTrack { pause(); cancelSleepTimer(); return }
        if natural && repeatMode == .one { prepare(index: index, autoplay: true); return }
        if queue.indices.contains(index + 1) { prepare(index: index + 1, autoplay: true) }
        else if repeatMode == .all { prepare(index: 0, autoplay: true) }
        else { prepare(index: 0, autoplay: false) }
    }

    func playNext(_ songs: [Song]) { requireMain(); insert(songs, at: (currentIndex ?? -1) + 1) }
    func addToQueue(_ songs: [Song]) { requireMain(); insert(songs, at: queue.count) }
    private func insert(_ songs: [Song], at index: Int) {
        guard !songs.isEmpty else { return }
        let tokens = songs.map { _ in UUID() }
        queue.insert(contentsOf: songs, at: index)
        queueTokens.insert(contentsOf: tokens, at: index)
        originalQueue.append(contentsOf: songs)
        originalTokens.append(contentsOf: tokens)
        if !shuffleEnabled { originalQueue = queue; originalTokens = queueTokens }
        if currentIndex == nil { prepare(index: 0, autoplay: false) }
        queueChanged()
    }

    func removeUpcoming(at offsets: IndexSet) {
        requireMain()
        guard let current = currentIndex else { return }
        for offset in offsets.sorted(by: >) {
            guard offset < queue.count - current - 1 else { continue }
            let index = current + 1 + offset
            let token = queueTokens.remove(at: index)
            queue.remove(at: index)
            if let original = originalTokens.firstIndex(of: token) { originalTokens.remove(at: original); originalQueue.remove(at: original) }
        }
        if !shuffleEnabled { originalQueue = queue; originalTokens = queueTokens }
        queueChanged()
    }

    func moveUpcoming(from offsets: IndexSet, to destination: Int) {
        requireMain()
        guard let current = currentIndex else { return }
        let start = current + 1
        let valid = offsets.filter { $0 < queue.count - start }.map { start + $0 }
        let songs = valid.map { queue[$0] }
        let tokens = valid.map { queueTokens[$0] }
        let target = start + min(max(0, destination), queue.count - start)
        for index in valid.reversed() { queue.remove(at: index); queueTokens.remove(at: index) }
        let insertion = target - valid.filter { $0 < target }.count
        queue.insert(contentsOf: songs, at: insertion); queueTokens.insert(contentsOf: tokens, at: insertion)
        if !shuffleEnabled { originalQueue = queue; originalTokens = queueTokens }
        queueChanged()
    }

    func clearUpNext() { requireMain(); removeUpcoming(at: IndexSet(integersIn: 0..<upcomingSongs.count)) }
    func toggleShuffle() { requireMain(); shuffleEnabled.toggle() }
    func cycleRepeatMode() { requireMain(); repeatMode = repeatMode.next }
    private func reorderForShuffle() {
        guard let index = currentIndex, queueTokens.indices.contains(index) else { return }
        let token = queueTokens[index]
        if shuffleEnabled {
            var indices = Array(queue.indices).filter { $0 != index }.shuffled()
            indices.insert(index, at: 0)
            let oldQueue = queue, oldTokens = queueTokens
            queue = indices.map { oldQueue[$0] }; queueTokens = indices.map { oldTokens[$0] }
            currentIndex = 0
        } else {
            queue = originalQueue; queueTokens = originalTokens
            currentIndex = queueTokens.firstIndex(of: token)
        }
        queueChanged()
    }
    private func queueChanged() {
        NowPlayingManager.shared.updateQueue(index: currentIndex ?? 0, count: queue.count)
        persistSession()
    }

    private func prepare(index: Int, position: TimeInterval = 0, autoplay: Bool, continuingPlay: Bool = false) {
        requireMain()
        guard queue.indices.contains(index) else { return }
        if let unit = audioUnit { AudioOutputUnitStop(unit) }
        updateTimeAndStats()
        let previouslyCounted = countedPlay
        var playedSeconds = 0.0
        if continuingPlay, let context = context {
            os_unfair_lock_lock(context.lock)
            playedSeconds = Double(context.playedFrames) / context.sampleRate
            os_unfair_lock_unlock(context.lock)
        }
        tearDown()
        isPlaying = false
        timer?.cancel(); timer = nil
        currentIndex = index
        let song = queue[index]
        currentSong = song
        currentTime = max(0, min(position, song.duration))
        countedPlay = continuingPlay && previouslyCounted; endHandled = false
        NowPlayingManager.shared.setNowPlaying(song: song, elapsed: currentTime, isPlaying: false, queueIndex: index, queueCount: queue.count)
        persistSession()
        loadAmplitude(for: song)
        var file: ExtAudioFileRef?
        guard ExtAudioFileOpenURL(song.url as CFURL, &file) == noErr, let opened = file else { return }
        var format = Self.format(sampleRate: song.sampleRate, channels: UInt32(song.channels))
        guard song.sampleRate > 0, song.channels > 0,
              ExtAudioFileSetProperty(opened, kExtAudioFileProperty_ClientDataFormat, UInt32(MemoryLayout.size(ofValue: format)), &format) == noErr else {
            ExtAudioFileDispose(opened); return
        }
        var length: Int64 = 0
        var size = UInt32(MemoryLayout.size(ofValue: length))
        if ExtAudioFileGetProperty(opened, kExtAudioFileProperty_FileLengthFrames, &size, &length) != noErr { length = Int64(song.duration * song.sampleRate) }
        let context = PlaybackContext(file: opened, sampleRate: song.sampleRate, channels: song.channels,
                                      totalFrames: length, position: min(length, Int64(currentTime * song.sampleRate)))
        context.playedFrames = Int64(playedSeconds * song.sampleRate)
        self.context = context
        eqEngine.setSampleRate(song.sampleRate)
        eqEngine.reset()
        publishReplayGain()
        // Configure the route before constructing RemoteIO, without deactivating between tracks.
        do { try AudioSessionManager.shared.configure(for: song.sampleRate, activate: autoplay) }
        catch { tearDown(); return }
        guard setupAudioUnit(sampleRate: song.sampleRate, channels: UInt32(song.channels)) else { tearDown(); return }
        context.readers.enter()
        readerQueue.async { Self.readFileLoop(context); context.readers.leave() }
        if autoplay { resume() }
        persistSession()
    }

    private func tearDown() {
        if let unit = audioUnit { AudioOutputUnitStop(unit) }
        if let context = context {
            os_unfair_lock_lock(context.lock); context.exiting = true; os_unfair_lock_unlock(context.lock)
            context.wake.signal()
            context.readers.wait()
        }
        if let unit = audioUnit {
            AudioUnitUninitialize(unit); AudioComponentInstanceDispose(unit); audioUnit = nil
        }
        if let context = context { ExtAudioFileDispose(context.file) }
        context = nil
    }

    private static func format(sampleRate: Double, channels: UInt32) -> AudioStreamBasicDescription {
        AudioStreamBasicDescription(mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: channels, mBitsPerChannel: 32, mReserved: 0)
    }

    private func setupAudioUnit(sampleRate: Double, channels: UInt32) -> Bool {
        var description = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_RemoteIO,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &description),
              AudioComponentInstanceNew(component, &audioUnit) == noErr, let unit = audioUnit else { return false }
        var enabled: UInt32 = 1
        guard AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &enabled, UInt32(MemoryLayout.size(ofValue: enabled))) == noErr else { return false }
        var format = Self.format(sampleRate: sampleRate, channels: channels)
        guard AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, UInt32(MemoryLayout.size(ofValue: format))) == noErr else { return false }
        var callback = AURenderCallbackStruct(inputProc: { ref, _, _, _, frames, data in
            Unmanaged<FLACPlayer>.fromOpaque(ref).takeUnretainedValue().render(data: data, frames: Int(frames))
        }, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        guard AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback,
                                   UInt32(MemoryLayout.size(ofValue: callback))) == noErr else { return false }
        return AudioUnitInitialize(unit) == noErr
    }

    private func render(data: UnsafeMutablePointer<AudioBufferList>?, frames: Int) -> OSStatus {
        guard let data = data else { return noErr }
        let output = UnsafeMutableAudioBufferListPointer(data)
        for buffer in output { if let pointer = buffer.mData { memset(pointer, 0, Int(buffer.mDataByteSize)) } }
        guard let context = context, os_unfair_lock_trylock(context.lock) else { return noErr }
        defer { os_unfair_lock_unlock(context.lock) }
        guard !context.exiting, context.pendingSeek == nil, output.count >= context.channels else { return noErr }
        var available = Int.max
        for buffer in context.buffers { available = min(available, buffer.availableToRead) }
        let count = min(frames, available)
        eqEngine.beginRender()
        let fadeStart = context.fadeRemaining
        for channel in 0..<context.channels {
            guard let pointer = output[channel].mData?.assumingMemoryBound(to: Float.self) else { continue }
            _ = context.buffers[channel].read(pointer, count: count)
            for frame in 0..<count {
                let fade: Float = context.fadeTotal > 0 ? Float(max(0, fadeStart - Int64(frame))) / Float(context.fadeTotal) : 1
                pointer[frame] *= context.gain * fade
            }
            eqEngine.process(channel: channel, buffer: pointer, frames: count)
        }
        context.elapsedFrames += Int64(count)
        context.playedFrames += Int64(count)
        if context.fadeTotal > 0 {
            context.fadeRemaining = max(0, fadeStart - Int64(frames))
            if context.fadeRemaining == 0 { context.fadeFinished = true }
        }
        if context.eof && available <= frames && !context.endSignaled { context.endSignaled = true }
        return noErr
    }

    private static func readFileLoop(_ context: PlaybackContext) {
        let capacity = 4096
        let pointers = (0..<context.channels).map { _ in UnsafeMutablePointer<Float>.allocate(capacity: capacity) }
        let list = AudioBufferList.allocate(maximumBuffers: context.channels)
        defer { pointers.forEach { $0.deallocate() }; free(list.unsafeMutablePointer) }
        for channel in 0..<context.channels {
            list[channel].mNumberChannels = 1
            list[channel].mData = UnsafeMutableRawPointer(pointers[channel])
        }
        while true {
            os_unfair_lock_lock(context.lock)
            if context.exiting { os_unfair_lock_unlock(context.lock); return }
            if let target = context.pendingSeek {
                // The reader alone seeks; the render trylock emits silence throughout this flush.
                let status = ExtAudioFileSeek(context.file, target)
                context.buffers.forEach { $0.reset() }
                context.elapsedFrames = target
                context.eof = status != noErr
                context.endSignaled = false
                context.pendingSeek = nil
            }
            let generation = context.seekGeneration
            let eof = context.eof
            let space = context.buffers.map { $0.availableSpace }.min() ?? 0
            os_unfair_lock_unlock(context.lock)
            if eof || space == 0 { _ = context.wake.wait(timeout: .now() + .milliseconds(10)); continue }
            var frames = UInt32(min(capacity, space))
            for channel in 0..<context.channels { list[channel].mDataByteSize = UInt32(capacity * MemoryLayout<Float>.size) }
            let status = ExtAudioFileRead(context.file, &frames, list.unsafeMutablePointer)
            os_unfair_lock_lock(context.lock)
            if !context.exiting && context.pendingSeek == nil && context.seekGeneration == generation {
                if status != noErr || frames == 0 { context.eof = true }
                else {
                    for channel in 0..<context.channels { _ = context.buffers[channel].write(pointers[channel], count: Int(frames)) }
                }
            }
            os_unfair_lock_unlock(context.lock)
        }
    }

    private func startTimer() {
        timer?.cancel()
        timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.tick() }
    }
    private func updateTimeAndStats() {
        guard let context = context else { return }
        os_unfair_lock_lock(context.lock)
        let elapsed = context.pendingSeek ?? context.elapsedFrames
        let played = context.playedFrames
        os_unfair_lock_unlock(context.lock)
        currentTime = Double(elapsed) / context.sampleRate
        if !countedPlay, let song = currentSong, song.duration > 0,
           Double(played) / context.sampleRate >= min(30, song.duration * 0.5) {
            countedPlay = true
            onTrackPlayed?(song)
        }
    }
    private func tick() {
        updateTimeAndStats()
        guard let context = context else { return }
        os_unfair_lock_lock(context.lock)
        let ended = context.endSignaled
        let faded = context.fadeFinished
        let fading = context.fadeTotal > 0
        os_unfair_lock_unlock(context.lock)
        if faded { pause(); cancelSleepTimer(); return }
        if sleepAtEndOfTrack, let song = currentSong, song.duration - currentTime <= 5, !fading { beginFade() }
        if ended && !endHandled { endHandled = true; advance(natural: true); return }
        if Date().timeIntervalSince(lastPersist) >= 10 { persistSession() }
    }

    func loadAmplitude(for song: Song) {
        requireMain()
        currentAmplitude = song.amplitudeData
        guard song.amplitudeData.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let data = AmplitudeEngine.compute(for: song.url)
            DispatchQueue.main.async { guard let self = self, self.currentSong?.id == song.id else { return }; self.currentAmplitude = data }
        }
    }

    private func publishReplayGain() {
        guard let context = context, let song = currentSong else { return }
        let db: Double?, peak: Double?
        switch replayGainMode {
        case .off: db = nil; peak = nil
        case .track:
            db = song.replayGainTrackDB ?? song.replayGainAlbumDB
            peak = song.replayGainTrackDB != nil ? (song.replayGainTrackPeak ?? song.replayGainAlbumPeak) : (song.replayGainAlbumPeak ?? song.replayGainTrackPeak)
        case .album:
            db = song.replayGainAlbumDB ?? song.replayGainTrackDB
            peak = song.replayGainAlbumDB != nil ? (song.replayGainAlbumPeak ?? song.replayGainTrackPeak) : (song.replayGainTrackPeak ?? song.replayGainAlbumPeak)
        }
        var gain = 1.0
        if let db = db, db.isFinite, replayGainPreampDB.isFinite {
            gain = pow(10, min(120, max(-120, db + replayGainPreampDB)) / 20)
            if let peak = peak, peak.isFinite, peak > 0 { gain = min(gain, 1 / peak) }
        }
        os_unfair_lock_lock(context.lock); context.gain = Float(gain); os_unfair_lock_unlock(context.lock)
    }

    func setEQBand(index: Int, frequency: Double? = nil, gainDB: Double? = nil, q: Double? = nil) {
        requireMain(); eqEngine.updateBand(index: index, frequency: frequency, gainDB: gainDB, q: q); currentEQPresetID = nil
    }
    func updateEQBand(index: Int, frequency: Double, gainDB: Double, q: Double) { setEQBand(index: index, frequency: frequency, gainDB: gainDB, q: q) }
    func setEQBypass(_ bypass: Bool) { requireMain(); objectWillChange.send(); eqEngine.setBypass(bypass) }
    func setPreampGain(_ gain: Double) { requireMain(); objectWillChange.send(); eqEngine.preampGainDB = gain }
    func setAutoPreamp(_ enabled: Bool) { requireMain(); objectWillChange.send(); eqEngine.autoPreamp = enabled }
    func loadEQPreset(preamp: Double, frequencies: [Double], gains: [Double], qs: [Double]) {
        requireMain(); eqEngine.loadPreset(preamp: preamp, frequencies: frequencies, gains: gains, qs: qs); currentEQPresetID = nil
    }
    func apply(preset: EQPreset) {
        requireMain(); eqEngine.loadPreset(preamp: preset.preampGainDB, frequencies: preset.frequencies, gains: preset.gains, qs: preset.qs)
        eqEngine.selectedPresetID = preset.id; currentEQPresetID = preset.id
    }

    func setSleepTimer(minutes: Double) {
        requireMain(); cancelSleepTimer()
        guard minutes.isFinite, minutes > 0 else { return }
        sleepTimerEndDate = Date().addingTimeInterval(minutes * 60)
        let work = DispatchWorkItem { [weak self] in self?.beginFade() }
        sleepWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + minutes * 60, execute: work)
    }
    func sleepAfterCurrentTrack() { requireMain(); cancelSleepTimer(); sleepAtEndOfTrack = true }
    func cancelSleepTimer() {
        requireMain(); sleepWork?.cancel(); sleepWork = nil; sleepTimerEndDate = nil; sleepAtEndOfTrack = false; resetFade()
    }
    private func beginFade() {
        guard isPlaying, let context = context else { cancelSleepTimer(); return }
        os_unfair_lock_lock(context.lock)
        context.fadeTotal = Int64(context.sampleRate * 5); context.fadeRemaining = context.fadeTotal; context.fadeFinished = false
        os_unfair_lock_unlock(context.lock)
    }
    private func resetFade() {
        guard let context = context else { return }
        os_unfair_lock_lock(context.lock); context.fadeTotal = 0; context.fadeRemaining = 0; context.fadeFinished = false; os_unfair_lock_unlock(context.lock)
    }

    private struct SavedEntry: Codable { let songID: String; let token: UUID }
    private struct SavedSession: Codable {
        let queue: [SavedEntry]
        let originalQueue: [SavedEntry]
        let currentIndex: Int
        let position: TimeInterval
        let shuffle: Bool
        let repeatMode: RepeatMode
    }
    private func persistSession() {
        guard !changingQueue, let index = currentIndex, queue.indices.contains(index) else { return }
        var position = currentTime
        if let context = context {
            os_unfair_lock_lock(context.lock)
            position = Double(context.pendingSeek ?? context.elapsedFrames) / context.sampleRate
            os_unfair_lock_unlock(context.lock)
        }
        let session = SavedSession(queue: zip(queue, queueTokens).map { SavedEntry(songID: $0.0.id, token: $0.1) },
            originalQueue: zip(originalQueue, originalTokens).map { SavedEntry(songID: $0.0.id, token: $0.1) },
            currentIndex: index, position: position, shuffle: shuffleEnabled, repeatMode: repeatMode)
        if let data = try? JSONEncoder().encode(session) { UserDefaults.standard.set(data, forKey: "PlaybackSession.v1") }
        lastPersist = Date()
    }
    func restoreSession(using library: MusicLibrary) {
        requireMain()
        guard !restored else { return }; restored = true
        guard queue.isEmpty, let data = UserDefaults.standard.data(forKey: "PlaybackSession.v1"),
              let session = try? JSONDecoder().decode(SavedSession.self, from: data) else { return }
        let lookup = Dictionary(library.songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let entries = session.queue.filter { lookup[$0.songID] != nil }
        guard !entries.isEmpty else { return }
        let original = session.originalQueue.filter { lookup[$0.songID] != nil }
        let selected = session.queue.indices.contains(session.currentIndex) ? session.queue[session.currentIndex].token : nil
        changingQueue = true
        queue = entries.compactMap { lookup[$0.songID] }; queueTokens = entries.map { $0.token }
        originalQueue = original.compactMap { lookup[$0.songID] }; originalTokens = original.map { $0.token }
        if originalQueue.isEmpty { originalQueue = queue; originalTokens = queueTokens }
        shuffleEnabled = session.shuffle; repeatMode = session.repeatMode
        changingQueue = false
        let index = selected.flatMap { queueTokens.firstIndex(of: $0) } ?? 0
        prepare(index: index, position: selected == queueTokens[index] && session.position.isFinite ? session.position : 0, autoplay: false)
    }
}

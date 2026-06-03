import Foundation
import Combine
import AudioToolbox
import AVFAudio
import os
import MediaPlayer
import SwiftUI

enum RepeatMode {
    case off, one, all
}

class FLACPlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var currentSong: Song?
    @Published var queue: [Song] = []
    @Published var currentTime: TimeInterval = 0
    @Published var currentAmplitude: [Float] = []
    var repeatMode: RepeatMode = .off
    var sourceQueue: [Song] = []

    var eqFrequencies: [Double] { eqEngine.bandFreqs }
    var eqGains: [Double] { eqEngine.bandGains }
    var eqQs: [Double] { eqEngine.bandQs }
    var isEQBypassed: Bool { eqEngine.bypassed }

    private var audioUnit: AudioComponentInstance?
    private var extAudioFile: ExtAudioFileRef?
    private var ringBuffers: [RingBuffer] = []
    private let bufferFrameSize = 4096
    private var fileReadQueue: DispatchQueue!
    private var fileSampleRate: Double = 44100
    private var fileChannels: UInt32 = 2

    private var readLoopActive = false
    private var fileReadComplete = false
    private let stateLock = NSLock()

    private var elapsedFrames: Int64 = 0
    private var totalFrames: Int64 = 0
    private var timer: AnyCancellable?

    private var remoteCancellables = Set<AnyCancellable>()

    // EQ engine instance
    private var eqEngine = EQEngine()

    // MARK: - Init
    init() {
        // Remote command observers
        NotificationCenter.default.publisher(for: .remotePlay)
            .sink { [weak self] _ in self?.resume() }
            .store(in: &remoteCancellables)
        NotificationCenter.default.publisher(for: .remotePause)
            .sink { [weak self] _ in self?.pause() }
            .store(in: &remoteCancellables)
        NotificationCenter.default.publisher(for: .remoteTogglePlayPause)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.isPlaying ? self.pause() : self.resume()
            }
            .store(in: &remoteCancellables)
        NotificationCenter.default.publisher(for: .remoteNext)
            .sink { [weak self] _ in self?.next() }
            .store(in: &remoteCancellables)
        NotificationCenter.default.publisher(for: .remotePrevious)
            .sink { [weak self] _ in self?.previous() }
            .store(in: &remoteCancellables)
        NotificationCenter.default.publisher(for: .remoteSeek)
            .sink { [weak self] notif in
                if let time = notif.object as? TimeInterval {
                    self?.seek(to: time)
                }
            }
            .store(in: &remoteCancellables)
    }

    // MARK: - Public API

    func play(song: Song) {
        stop(clearSong: false)
        
        self.currentSong = song
        self.currentTime = 0

        loadAmplitude(for: song)
        
        fileSampleRate = song.sampleRate
        fileChannels = UInt32(song.channels)
        totalFrames = Int64(song.duration * fileSampleRate)
        eqEngine.setSampleRate(fileSampleRate)

        try? AudioSessionManager.shared.configure(for: fileSampleRate)

        guard ExtAudioFileOpenURL(song.url as CFURL, &extAudioFile) == noErr,
              let extFile = extAudioFile else { return }

        var clientFormat = AudioStreamBasicDescription(
            mSampleRate: fileSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: fileChannels,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        
        ExtAudioFileSetProperty(extFile, kExtAudioFileProperty_ClientDataFormat,
                                UInt32(MemoryLayout.size(ofValue: clientFormat)), &clientFormat)

        let capacity = Int(fileSampleRate) * 4
        ringBuffers = (0..<fileChannels).map { _ in RingBuffer(capacityInFrames: capacity) }

        stateLock.lock()
        readLoopActive = true
        fileReadComplete = false
        elapsedFrames = 0
        stateLock.unlock()

        setupAudioUnit(sampleRate: fileSampleRate, channels: fileChannels)

        fileReadQueue = DispatchQueue(label: "flac.read", qos: .userInitiated)
        fileReadQueue.async { [weak self] in self?.readFileLoop() }

        AudioOutputUnitStart(audioUnit!)
        
        DispatchQueue.main.async {
            self.isPlaying = true
        }
        
        NowPlayingManager.shared.setNowPlaying(song: song, elapsed: 0, isPlaying: true)
        startTimer()
    }

    func pause() {
        DispatchQueue.main.async {
            self.isPlaying = false
        }
        
        timer?.cancel()
        timer = nil
        
        if let song = currentSong {
            NowPlayingManager.shared.setNowPlaying(
                song: song,
                elapsed: currentTime,
                isPlaying: false
            )
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let au = self?.audioUnit else { return }
            AudioOutputUnitStop(au)
        }
    }

    func resume() {
        DispatchQueue.main.async {
            self.isPlaying = true
        }
        
        if let song = currentSong {
            NowPlayingManager.shared.setNowPlaying(
                song: song,
                elapsed: currentTime,
                isPlaying: true
            )
        }
        
        startTimer()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let au = self?.audioUnit else { return }
            AudioOutputUnitStart(au)
        }
    }
    
    private func startTimer() {
        timer?.cancel()
        timer = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.currentTime = Double(self.elapsedFrames) / self.fileSampleRate
                if let song = self.currentSong {
                    NowPlayingManager.shared.setNowPlaying(song: song, elapsed: self.currentTime, isPlaying: self.isPlaying)
                }
            }
    }

    func stop(clearSong: Bool = true) {
        pause()
        timer?.cancel()
        timer = nil
        
        stateLock.lock()
        readLoopActive = false
        stateLock.unlock()
        
        if let extFile = extAudioFile {
            ExtAudioFileDispose(extFile)
            extAudioFile = nil
        }
        
        if let au = audioUnit {
            AudioUnitUninitialize(au)
            AudioComponentInstanceDispose(au)
            audioUnit = nil
        }
        
        AudioSessionManager.shared.deactivate()
        
        if clearSong {
            DispatchQueue.main.async {
                self.currentSong = nil
                self.currentTime = 0
                self.currentAmplitude = []
            }
            NowPlayingManager.shared.clear()
        }
    }

    func seek(to time: TimeInterval) {
        DispatchQueue.main.async {
            self.currentTime = time
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.stateLock.lock()
            let targetFrame = Int64(time * self.fileSampleRate)
            self.elapsedFrames = targetFrame
            
            for ch in 0..<Int(self.fileChannels) {
                if ch < self.ringBuffers.count { self.ringBuffers[ch].reset() }
            }
            if let extFile = self.extAudioFile {
                ExtAudioFileSeek(extFile, targetFrame)
            }
            self.stateLock.unlock()
        }
    }
    
    func playQueue(songs: [Song], startIndex: Int = 0) {
        sourceQueue = songs
        queue = songs
        if startIndex < songs.count {
            play(song: songs[startIndex])
        }
    }

    func next() {
        guard !queue.isEmpty, let current = currentSong else { return }
            
        let currentIndex = queue.firstIndex(of: current) ?? 0
        let nextIndex = currentIndex + 1
        
        if nextIndex >= queue.count {
            playQueue(songs: queue, startIndex: 0)
        } else {
            playQueue(songs: queue, startIndex: nextIndex)
        }
    }

    func previous() {
        guard !queue.isEmpty, let current = currentSong else { return }
        
        if currentTime > 3.0 {
            seek(to: 0)
            return
        }
        
        let currentIndex = queue.firstIndex(of: current) ?? 0
        let prevIndex = currentIndex - 1
        
        if prevIndex < 0 {
            playQueue(songs: queue, startIndex: queue.count - 1)
        } else {
            playQueue(songs: queue, startIndex: prevIndex)
        }
    }
    
    func shuffleUpcoming() {
        guard !queue.isEmpty, let current = currentSong else { return }
        let currentIndex = queue.firstIndex(of: current) ?? 0
        
        if currentIndex + 1 < queue.count {
            let upcoming = queue[(currentIndex + 1)...].shuffled()
            queue.replaceSubrange((currentIndex + 1)..., with: upcoming)
        }
    }

    func shuffleQueue() {
        guard !queue.isEmpty else { return }
        let current = currentSong
        var shuffled = queue.shuffled()
        if let current = current, let idx = shuffled.firstIndex(of: current) {
            shuffled.swapAt(0, idx)
        }
        queue = shuffled
    }
    
    func shuffleAll() {
        guard !sourceQueue.isEmpty else { return }
        let shuffled = sourceQueue.shuffled()
        queue = shuffled
        if let first = shuffled.first {
            play(song: first)
        }
    }

    func advanceToNextSong() {
        guard repeatMode != .one else {
            if let song = currentSong { play(song: song) }
            return
        }
        guard !queue.isEmpty, let current = currentSong else { return }
        let currentIndex = queue.firstIndex(of: current) ?? 0
        let nextIndex = currentIndex + 1
        if nextIndex >= queue.count {
            // Loop back to start
            play(song: queue[0])
        } else {
            play(song: queue[nextIndex])
        }
    }

    // MARK: - Queue helpers
    
    var currentSongIndex: Int? {
        queue.firstIndex(where: { $0.id == currentSong?.id })
    }

    var upcomingSongs: [Song] {
        guard let idx = currentSongIndex else { return [] }
        return Array(queue.suffix(from: idx + 1))
    }

    func removeFromQueue(at offsets: IndexSet) {
        let indices = offsets.compactMap { offset -> Int? in
            let realIndex = (currentSongIndex ?? -1) + 1 + offset
            return realIndex < queue.count ? realIndex : nil
        }
        queue.remove(atOffsets: IndexSet(indices))
    }

    func moveInQueue(from source: IndexSet, to destination: Int) {
        guard let currentIdx = currentSongIndex else { return }
        var items = upcomingSongs
        items.move(fromOffsets: source, toOffset: destination)
        queue = Array(queue[0...currentIdx]) + items
    }

    func clearQueue() {
        guard let idx = currentSongIndex else { return }
        queue = Array(queue[0...idx])
    }

    // MARK: - EQ control

    func setEQBand(index: Int, frequency: Double? = nil,
                   gainDB: Double? = nil, q: Double? = nil) {
        eqEngine.updateBand(index: index, frequency: frequency,
                            gainDB: gainDB, q: q)
    }

    func setEQBypass(_ bypass: Bool) {
        eqEngine.setBypass(bypass)
    }

    var eqBandsCount: Int { eqEngine.bandCount }

    var preampGainDB: Double {
        return eqEngine.preampGainDB
    }

    func setPreampGain(_ gain: Double) {
        // Note: Due to threading, changes are safe as EQEngine handles ramping
        eqEngine.preampGainDB = gain
    }

    func updateEQBand(index: Int, frequency: Double, gainDB: Double, q: Double) {
        eqEngine.updateBand(index: index, frequency: frequency, gainDB: gainDB, q: q)
    }

    func loadEQPreset(preamp: Double, frequencies: [Double], gains: [Double], qs: [Double]) {
        eqEngine.loadPreset(preamp: preamp, frequencies: frequencies, gains: gains, qs: qs)
    }

    // MARK: - Audio Unit setup

    private func setupAudioUnit(sampleRate: Double, channels: UInt32) {
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_RemoteIO,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0
        )
        guard let comp = AudioComponentFindNext(nil, &desc) else { return }
        AudioComponentInstanceNew(comp, &audioUnit)
        guard let au = audioUnit else { return }

        var flag: UInt32 = 1
        AudioUnitSetProperty(au, kAudioOutputUnitProperty_EnableIO,
                             kAudioUnitScope_Output, 0, &flag, UInt32(MemoryLayout.size(ofValue: flag)))

        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: channels, mBitsPerChannel: 32, mReserved: 0
        )
        AudioUnitSetProperty(au, kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Input, 0, &asbd, UInt32(MemoryLayout.size(ofValue: asbd)))

        var callbackStruct = AURenderCallbackStruct(
            inputProc: { (inRefCon, _, _, _, inNumberFrames, ioData) -> OSStatus in
                let player = Unmanaged<FLACPlayer>.fromOpaque(inRefCon).takeUnretainedValue()
                return player.renderCallback(ioData: ioData, frames: inNumberFrames)
            },
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        AudioUnitSetProperty(au, kAudioUnitProperty_SetRenderCallback,
                             kAudioUnitScope_Input, 0, &callbackStruct,
                             UInt32(MemoryLayout.size(ofValue: callbackStruct)))

        AudioUnitInitialize(au)
    }

    private func renderCallback(ioData: UnsafeMutablePointer<AudioBufferList>?, frames: UInt32) -> OSStatus {
        guard ioData != nil else { return noErr }
        let bufferList = UnsafeMutableAudioBufferListPointer(ioData)
        let frameCount = Int(frames)

        var allBuffersReady = true
        for buffer in ringBuffers {
            if buffer.availableToRead < frameCount {
                allBuffersReady = false
                break
            }
        }

        if allBuffersReady {
            for ch in 0..<Int(fileChannels) {
                if let dest = bufferList?[ch].mData?.assumingMemoryBound(to: Float.self) {
                    _ = ringBuffers[ch].read(dest, count: frameCount)
                    eqEngine.process(channel: ch, buffer: dest, frames: frameCount)
                }
            }
            OSAtomicAdd64(Int64(frameCount), &elapsedFrames)
            return noErr
        }

        for ch in 0..<Int(fileChannels) {
            if let buf = bufferList?[ch].mData {
                memset(buf, 0, frameCount * MemoryLayout<Float>.size)
            }
        }

        stateLock.lock()
        let shouldAdvance = fileReadComplete && ringBuffers[0].availableToRead < frameCount
        stateLock.unlock()

        if shouldAdvance {
            DispatchQueue.main.async { [weak self] in
                self?.advanceToNextSong()
            }
        }

        return noErr
    }

    private func readFileLoop() {
        guard let extFile = extAudioFile else { return }

        let chCount = Int(fileChannels)
        let bufferPointers: [UnsafeMutablePointer<Float>] = (0..<chCount).map { _ in
            UnsafeMutablePointer<Float>.allocate(capacity: bufferFrameSize)
        }
        defer {
            for ptr in bufferPointers { ptr.deallocate() }
        }

        let ablPointer = AudioBufferList.allocate(maximumBuffers: chCount)
        defer { free(ablPointer.unsafeMutablePointer) }

        for i in 0..<chCount {
            ablPointer[i].mNumberChannels = 1
            ablPointer[i].mDataByteSize = UInt32(bufferFrameSize * MemoryLayout<Float>.size)
            ablPointer[i].mData = UnsafeMutableRawPointer(bufferPointers[i])
        }

        var localReadActive = true
        while localReadActive {
            stateLock.lock()
            localReadActive = readLoopActive
            stateLock.unlock()
            if !localReadActive { break }

            let minSpace = ringBuffers.map { $0.availableSpace }.min() ?? 0
            if minSpace == 0 {
                usleep(1000)
                continue
            }

            var ioFrames: UInt32 = UInt32(min(bufferFrameSize, minSpace))
            let status = ExtAudioFileRead(extFile, &ioFrames, ablPointer.unsafeMutablePointer)
            if status != noErr || ioFrames == 0 {
                stateLock.lock()
                fileReadComplete = true
                readLoopActive = false
                stateLock.unlock()
                break
            }

            let framesRead = Int(ioFrames)
            for ch in 0..<chCount {
                _ = ringBuffers[ch].write(bufferPointers[ch], count: framesRead)
            }
        }
    }
    
    // MARK: - Waveform Generation
    
    private func computeAmplitude(for song: Song) -> [Float] {
        if !song.amplitudeData.isEmpty { return song.amplitudeData }
        guard let file = try? AVAudioFile(forReading: song.url) else { return [] }
        let format = file.processingFormat
        let frameCount = UInt32(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return [] }
        try? file.read(into: buffer)
        guard let channelData = buffer.floatChannelData else { return [] }

        let sampleRate = format.sampleRate
        let samplesPerChunk = Int(sampleRate) // 1 second per bar
        var amplitudes: [Float] = []
        var offset = 0
        while offset < Int(frameCount) {
            let remaining = min(samplesPerChunk, Int(frameCount) - offset)
            var sum: Float = 0
            for i in 0..<remaining {
                let sample = channelData[0][offset + i]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(remaining))
            amplitudes.append(rms)
            offset += samplesPerChunk
        }
        if let maxAmp = amplitudes.max(), maxAmp > 0 {
            amplitudes = amplitudes.map { $0 / maxAmp }
        }
        return amplitudes
    }
    
    func loadAmplitude(for song: Song) {
        DispatchQueue.main.async { self.currentAmplitude = [] }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let generated = self.computeAmplitude(for: song)
            DispatchQueue.main.async {
                self.currentAmplitude = generated
            }
        }
    }
}

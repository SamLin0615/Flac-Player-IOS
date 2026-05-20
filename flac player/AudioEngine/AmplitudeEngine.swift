import AVFAudio

struct AmplitudeEngine {
    static func compute(for url: URL) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url) else { return [] }
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
}

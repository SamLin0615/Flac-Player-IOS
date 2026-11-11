import Foundation
import AVFAudio

struct AmplitudeEngine {
    static func compute(for url: URL, bins: Int = 120) -> [Float] {
        guard bins > 0,
              let file = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false),
              file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 65_536) else { return [] }
        var peaks = [Float](repeating: 0, count: bins)
        let total = file.length
        var position: AVAudioFramePosition = 0
        do {
            while position < total {
                try file.read(into: buffer, frameCount: AVAudioFrameCount(min(65_536, total - position)))
                let count = Int(buffer.frameLength)
                guard count > 0, let channels = buffer.floatChannelData else { return [] }
                for frame in 0..<count {
                    let bin = min(bins - 1, Int(Double(position + Int64(frame)) / Double(total) * Double(bins)))
                    for channel in 0..<Int(buffer.format.channelCount) {
                        let value = abs(channels[channel][frame])
                        if value.isFinite { peaks[bin] = max(peaks[bin], value) }
                    }
                }
                position += Int64(count)
            }
        } catch { return [] }
        if let maximum = peaks.max(), maximum > 0 { return peaks.map { min(1, $0 / maximum) } }
        return peaks
    }
}

import AVFAudio

class AudioSessionManager {
    static let shared = AudioSessionManager()
    private let session = AVAudioSession.sharedInstance()

    func configure(for sampleRate: Double) throws {
        try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothA2DP])
        try session.setPreferredSampleRate(sampleRate)
        try session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)
    }

    func deactivate() {
        try? session.setActive(false)
    }
}

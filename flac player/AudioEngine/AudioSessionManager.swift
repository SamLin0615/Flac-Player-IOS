import AVFAudio

class AudioSessionManager {
    static let shared = AudioSessionManager()
    private let session = AVAudioSession.sharedInstance()
    private var categoryConfigured = false

    func configure(for sampleRate: Double, activate: Bool = true) throws {
        if !categoryConfigured {
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothA2DP])
            categoryConfigured = true
        }
        try session.setPreferredSampleRate(sampleRate)
        if activate { try session.setActive(true) }
    }

    func deactivate() {
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    func mediaServicesReset() { categoryConfigured = false }
}

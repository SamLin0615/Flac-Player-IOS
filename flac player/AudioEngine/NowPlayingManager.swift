import MediaPlayer
import UIKit

final class NowPlayingManager {
    static let shared = NowPlayingManager()
    private let infoCenter = MPNowPlayingInfoCenter.default()
    private let remote = MPRemoteCommandCenter.shared()

    private init() {
        configureRemoteCommands()
    }

    func setNowPlaying(song: Song, elapsed: TimeInterval, isPlaying: Bool, queueIndex: Int, queueCount: Int) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist,
            MPMediaItemPropertyAlbumTitle: song.album,
            MPMediaItemPropertyPlaybackDuration: song.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: queueIndex,
            MPNowPlayingInfoPropertyPlaybackQueueCount: queueCount
        ]
        if let art = song.artwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: art.size) { _ in art }
        }
        infoCenter.nowPlayingInfo = info
    }

    func update(elapsed: TimeInterval, isPlaying: Bool) {
        guard var info = infoCenter.nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        infoCenter.nowPlayingInfo = info
    }

    func updateQueue(index: Int, count: Int) {
        guard var info = infoCenter.nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = index
        info[MPNowPlayingInfoPropertyPlaybackQueueCount] = count
        infoCenter.nowPlayingInfo = info
    }
    
    func clear() {
        infoCenter.nowPlayingInfo = nil
    }

    private func configureRemoteCommands() {
        remote.skipForwardCommand.isEnabled = false
        remote.skipBackwardCommand.isEnabled = false
        remote.changeRepeatModeCommand.isEnabled = true
        remote.changeShuffleModeCommand.isEnabled = true
        remote.changeRepeatModeCommand.addTarget { event in
            guard let event = event as? MPChangeRepeatModeCommandEvent else { return .commandFailed }
            NotificationCenter.default.post(name: .remoteRepeat, object: event.repeatType.rawValue)
            return .success
        }
        remote.changeShuffleModeCommand.addTarget { event in
            guard let event = event as? MPChangeShuffleModeCommandEvent else { return .commandFailed }
            NotificationCenter.default.post(name: .remoteShuffle, object: event.shuffleType.rawValue)
            return .success
        }
        remote.playCommand.addTarget { _ in
            NotificationCenter.default.post(name: .remotePlay, object: nil)
            return .success
        }
        remote.pauseCommand.addTarget { _ in
            NotificationCenter.default.post(name: .remotePause, object: nil)
            return .success
        }
        remote.togglePlayPauseCommand.addTarget { _ in
            NotificationCenter.default.post(name: .remoteTogglePlayPause, object: nil)
            return .success
        }
        remote.nextTrackCommand.addTarget { _ in
            NotificationCenter.default.post(name: .remoteNext, object: nil)
            return .success
        }
        remote.previousTrackCommand.addTarget { _ in
            NotificationCenter.default.post(name: .remotePrevious, object: nil)
            return .success
        }
        remote.changePlaybackPositionCommand.addTarget { event in
            guard let seekEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            NotificationCenter.default.post(name: .remoteSeek, object: seekEvent.positionTime)
            return .success
        }
    }
}

extension Notification.Name {
    static let remotePlay = Notification.Name("remotePlay")
    static let remotePause = Notification.Name("remotePause")
    static let remoteTogglePlayPause = Notification.Name("remoteTogglePlayPause")
    static let remoteNext = Notification.Name("remoteNext")
    static let remotePrevious = Notification.Name("remotePrevious")
    static let remoteSeek = Notification.Name("remoteSeek")
    static let remoteRepeat = Notification.Name("remoteRepeat")
    static let remoteShuffle = Notification.Name("remoteShuffle")
}

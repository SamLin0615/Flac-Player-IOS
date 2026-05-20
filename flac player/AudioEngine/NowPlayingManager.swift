import MediaPlayer
import UIKit

final class NowPlayingManager {
    static let shared = NowPlayingManager()
    private let infoCenter = MPNowPlayingInfoCenter.default()
    private let remote = MPRemoteCommandCenter.shared()

    private init() {
        configureRemoteCommands()
    }

    func setNowPlaying(song: Song, elapsed: TimeInterval, isPlaying: Bool) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist,
            MPMediaItemPropertyAlbumTitle: song.album,
            MPMediaItemPropertyPlaybackDuration: song.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let art = song.artwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: art.size) { _ in art }
        }
        infoCenter.nowPlayingInfo = info
    }
    
    func clear() {
        infoCenter.nowPlayingInfo = nil
    }

    private func configureRemoteCommands() {
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
}

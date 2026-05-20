import Foundation
import UIKit
import AudioToolbox

private final class DateCache {
    var date: Date?
}

struct Song: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let title: String
    let artist: String
    let album: String
    let albumArtist: String
    let genre: String
    let trackNumber: Int?
    let discNumber: Int?
    let year: Int?
    let duration: TimeInterval
    let sampleRate: Double
    let bitDepth: Int
    let channels: Int
    let artwork: UIImage?
    let lyrics: String?
    var amplitudeData: [Float] = []

    private let _dateCache = DateCache()
    var dateAdded: Date {
        if let d = _dateCache.date { return d }
        let d = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
        _dateCache.date = d
        return d
    }

    var durationFormatted: String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    init?(url: URL) {
        guard let (meta, props) = Self.parse(url: url) else { return nil }
        self.url = url
        self.title = meta["title"] as? String ?? url.deletingPathExtension().lastPathComponent
        self.artist = meta["artist"] as? String ?? "Unknown Artist"
        self.album = meta["album"] as? String ?? "Unknown Album"
        self.albumArtist = meta["albumartist"] as? String ?? self.artist
        self.genre = meta["genre"] as? String ?? ""
        self.trackNumber = meta["track"] as? Int
        self.discNumber = meta["discnumber"] as? Int
        self.year = meta["year"] as? Int
        self.duration = props.duration
        self.sampleRate = props.sampleRate
        self.bitDepth = props.bitDepth
        self.channels = props.channels
        self.artwork = meta["artwork"] as? UIImage
        self.lyrics = meta["lyrics"] as? String
    }

    static func == (lhs: Song, rhs: Song) -> Bool {
        lhs.id == rhs.id
    }

    private static func parse(url: URL) -> (metadata: [String: Any], properties: (duration: TimeInterval, sampleRate: Double, bitDepth: Int, channels: Int))? {
        var audioFile: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &audioFile) == noErr,
              let fileID = audioFile else { return nil }
        defer { AudioFileClose(fileID) }

        var meta: [String: Any] = [:]

        var dict: CFDictionary?
        var dictSize = UInt32(MemoryLayout<CFDictionary?>.size)
        let dictErr = withUnsafeMutablePointer(to: &dict) { ptr in
            AudioFileGetProperty(fileID, kAudioFilePropertyInfoDictionary, &dictSize, UnsafeMutableRawPointer(ptr))
        }
        if dictErr == noErr, let validDict = dict as? [String: Any] {
            meta = validDict
        }
        
        var imageData: CFData?
        var imageSize = UInt32(MemoryLayout<CFData?>.size)
        let imgErr = withUnsafeMutablePointer(to: &imageData) { ptr in
            AudioFileGetProperty(fileID, kAudioFilePropertyAlbumArtwork, &imageSize, UnsafeMutableRawPointer(ptr))
        }
        if imgErr == noErr, let validData = imageData as Data?, let image = UIImage(data: validData) {
            meta["artwork"] = image
        }

        var asbd = AudioStreamBasicDescription()
        var asbdSize = UInt32(MemoryLayout.size(ofValue: asbd))
        guard AudioFileGetProperty(fileID, kAudioFilePropertyDataFormat, &asbdSize, &asbd) == noErr else { return nil }

        var bits: UInt32 = 0
        var bitsSize = UInt32(MemoryLayout.size(ofValue: bits))
        AudioFileGetProperty(fileID, kAudioFilePropertySourceBitDepth, &bitsSize, &bits)
        let bitDepth = (bits > 0) ? Int(bits) : Int(asbd.mBitsPerChannel)

        var duration: Float64 = 0
        var durSize = UInt32(MemoryLayout.size(ofValue: duration))
        AudioFileGetProperty(fileID, kAudioFilePropertyEstimatedDuration, &durSize, &duration)

        let sampleRate = asbd.mSampleRate
        let channels = Int(asbd.mChannelsPerFrame)

        return (meta, (duration: TimeInterval(duration), sampleRate: sampleRate, bitDepth: bitDepth, channels: channels))
    }
}

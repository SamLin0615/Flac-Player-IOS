import Foundation
import UIKit
import AudioToolbox

struct Song: Identifiable, Hashable {
    let id: String
    let url: URL
    let title: String
    let artist: String
    let album: String
    let albumArtist: String
    let genre: String
    let trackNumber: Int?
    let discNumber: Int?
    let year: Int?
    let trackTotal: Int?
    let discTotal: Int?
    let replayGainTrackDB: Double?
    let replayGainAlbumDB: Double?
    let replayGainTrackPeak: Double?
    let replayGainAlbumPeak: Double?
    let duration: TimeInterval
    let sampleRate: Double
    let bitDepth: Int
    let channels: Int
    let artwork: UIImage?
    let lyrics: String?
    var amplitudeData: [Float] = []

    let dateAdded: Date

    var durationFormatted: String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    init?(url: URL) {
        let native = FLACMetadataReader.read(url: url)
        let parsed: (metadata: [String: Any], properties: (duration: TimeInterval, sampleRate: Double, bitDepth: Int, channels: Int))
        if let native = native {
            parsed = (native.comments as [String: Any], (native.duration, native.sampleRate, native.bitDepth, native.channels))
        } else if let fallback = Self.parse(url: url) {
            parsed = fallback
        } else { return nil }
        let meta = Dictionary(parsed.metadata.map { ($0.key.uppercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        let props = parsed.properties
        func text(_ keys: String...) -> String? {
            for key in keys {
                if let value = meta[key] as? String { return value }
                if let value = meta[key] as? NSNumber { return value.stringValue }
            }
            return nil
        }
        func number(_ value: String?) -> Int? {
            value.flatMap { Int($0.split(separator: "/").first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") }
        }
        func total(_ value: String?) -> Int? {
            guard let parts = value?.split(separator: "/"), parts.count > 1 else { return nil }
            return Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
        }
        func gain(_ key: String) -> Double? {
            text(key)?.split(whereSeparator: { $0.isWhitespace }).first.flatMap { Double($0) }
        }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.resolvingSymlinksInPath().standardizedFileURL.path
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard path.hasPrefix(documents + "/") else { return nil }
        self.id = String(path.dropFirst(documents.count + 1))
        self.url = url
        self.title = text("TITLE") ?? url.deletingPathExtension().lastPathComponent
        self.artist = text("ARTIST") ?? "Unknown Artist"
        self.album = text("ALBUM") ?? "Unknown Album"
        self.albumArtist = text("ALBUMARTIST", "ALBUM ARTIST") ?? self.artist
        self.genre = text("GENRE") ?? ""
        self.trackNumber = number(text("TRACKNUMBER", "TRACK NUMBER", "TRACK"))
        self.discNumber = number(text("DISCNUMBER", "DISC NUMBER"))
        self.trackTotal = number(text("TOTALTRACKS", "TRACKTOTAL")) ?? total(text("TRACKNUMBER", "TRACK NUMBER"))
        self.discTotal = number(text("TOTALDISCS", "DISCTOTAL")) ?? total(text("DISCNUMBER", "DISC NUMBER"))
        let yearPrefix = text("DATE", "YEAR")?.prefix(4)
        self.year = yearPrefix.flatMap { $0.count == 4 && $0.allSatisfy({ $0.isNumber }) ? Int($0) : nil }
        self.replayGainTrackDB = gain("REPLAYGAIN_TRACK_GAIN")
        self.replayGainAlbumDB = gain("REPLAYGAIN_ALBUM_GAIN")
        self.replayGainTrackPeak = gain("REPLAYGAIN_TRACK_PEAK")
        self.replayGainAlbumPeak = gain("REPLAYGAIN_ALBUM_PEAK")
        self.duration = props.duration
        self.sampleRate = props.sampleRate
        self.bitDepth = props.bitDepth
        self.channels = props.channels
        self.artwork = native?.artwork ?? meta["ARTWORK"] as? UIImage
        self.lyrics = text("LYRICS", "UNSYNCEDLYRICS")
        self.dateAdded = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }

    static func == (lhs: Song, rhs: Song) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }

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
        if imgErr == noErr, let validData = imageData as Data?, let image = FLACMetadataReader.thumbnail(from: validData) {
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

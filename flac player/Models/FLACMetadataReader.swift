import Foundation
import UIKit
import ImageIO

struct FLACMetadataReader {
    struct Metadata {
        var comments: [String: String] = [:]
        var sampleRate: Double = 0
        var channels: Int = 0
        var bitDepth: Int = 0
        var duration: TimeInterval = 0
        var artwork: UIImage?
    }

    static func thumbnail(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 600,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    static func read(url: URL) -> Metadata? {
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        func read(_ count: Int) throws -> Data {
            var data = Data()
            while data.count < count {
                guard let part = try file.read(upToCount: count - data.count), !part.isEmpty else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                data.append(part)
            }
            return data
        }
        do {
            let fileSize = try file.seekToEnd()
            try file.seek(toOffset: 0)
            var magic = try read(4)
            if magic.prefix(3) == Data("ID3".utf8) {
                let rest = try read(6)
                let sizeBytes = rest.suffix(4)
                guard sizeBytes.allSatisfy({ $0 < 128 }) else { return nil }
                let size = sizeBytes.reduce(UInt64(0)) { ($0 << 7) | UInt64($1) }
                let footer: UInt64 = magic[3] == 4 && (rest[1] & 0x10) != 0 ? 10 : 0
                try file.seek(toOffset: 10 + size + footer)
                magic = try read(4)
            }
            guard magic == Data("fLaC".utf8) else { return nil }
            var result = Metadata()
            var hasStreamInfo = false
            var hasFrontCover = false
            while true {
                let header = try read(4)
                let type = header[0] & 0x7f
                let length = Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
                let payloadOffset = try file.offset()
                guard payloadOffset <= fileSize, UInt64(length) <= fileSize - payloadOffset else { return nil }
                if type == 0 || type == 4 || type == 6 {
                    var cursor = Cursor(data: try read(length))
                    switch type {
                    case 0:
                        guard length == 34 else { return nil }
                        try cursor.skip(10)
                        let packed = try cursor.integer(8)
                        result.sampleRate = Double((packed >> 44) & 0xfffff)
                        result.channels = Int((packed >> 41) & 7) + 1
                        result.bitDepth = Int((packed >> 36) & 31) + 1
                        guard result.sampleRate > 0 else { return nil }
                        result.duration = Double(packed & 0xfffffffff) / result.sampleRate
                        hasStreamInfo = true
                    case 4:
                        let vendorLength = Int(try cursor.integer(4, littleEndian: true))
                        try cursor.skip(vendorLength)
                        let count = Int(try cursor.integer(4, littleEndian: true))
                        guard count <= cursor.remaining / 4 else { return nil }
                        for _ in 0..<count {
                            let size = Int(try cursor.integer(4, littleEndian: true))
                            let bytes = try cursor.bytes(size)
                            guard let text = String(data: bytes, encoding: .utf8),
                                  let separator = text.firstIndex(of: "=") else { continue }
                            let key = text[..<separator].uppercased()
                            if result.comments[key] == nil {
                                result.comments[key] = String(text[text.index(after: separator)...])
                            }
                        }
                    case 6:
                        let pictureType = try cursor.integer(4)
                        let mimeLength = Int(try cursor.integer(4))
                        try cursor.skip(mimeLength)
                        let descriptionLength = Int(try cursor.integer(4))
                        try cursor.skip(descriptionLength)
                        try cursor.skip(16)
                        let size = Int(try cursor.integer(4))
                        let bytes = try cursor.bytes(size)
                        if !hasFrontCover && (result.artwork == nil || pictureType == 3),
                           let artwork = thumbnail(from: bytes) {
                            result.artwork = artwork
                            hasFrontCover = pictureType == 3
                        }
                    default: break
                    }
                } else {
                    // Seek over padding and metadata we do not use.
                    try file.seek(toOffset: payloadOffset + UInt64(length))
                }
                if header[0] & 0x80 != 0 { break }
            }
            return hasStreamInfo ? result : nil
        } catch { return nil }
    }

    private struct Cursor {
        let data: Data
        var offset = 0
        var remaining: Int { data.count - offset }

        mutating func bytes(_ count: Int) throws -> Data {
            guard count >= 0, count <= remaining else { throw CocoaError(.fileReadCorruptFile) }
            defer { offset += count }
            return data.subdata(in: offset..<(offset + count))
        }

        mutating func skip(_ count: Int) throws { _ = try bytes(count) }

        mutating func integer(_ count: Int, littleEndian: Bool = false) throws -> UInt64 {
            let value = try bytes(count)
            return (littleEndian ? Array(value.reversed()) : Array(value)).reduce(UInt64(0)) {
                ($0 << 8) | UInt64($1)
            }
        }
    }
}

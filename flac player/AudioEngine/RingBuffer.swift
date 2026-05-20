import Foundation

class RingBuffer {
    private var buffer: [Float]
    private let capacity: Int
    private var readIndex: Int = 0
    private var writeIndex: Int = 0
    private let lock = NSLock()
    private(set) var availableToRead: Int = 0
    var availableSpace: Int {
        lock.lock()
        defer { lock.unlock() }
        return capacity - availableToRead
    }

    init(capacityInFrames: Int) {
        self.capacity = capacityInFrames
        self.buffer = [Float](repeating: 0, count: capacityInFrames)
    }

    /// Write up to `count` samples; returns number actually written.
    func write(_ frames: UnsafePointer<Float>, count: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let space = capacity - availableToRead
        let toWrite = min(space, count)
        if toWrite <= 0 { return 0 }

        let firstPart = min(capacity - writeIndex, toWrite)
        buffer.withUnsafeMutableBufferPointer { buf in
            buf.baseAddress!.advanced(by: writeIndex).initialize(from: frames, count: firstPart)
        }
        if toWrite > firstPart {
            let secondPart = toWrite - firstPart
            buffer.withUnsafeMutableBufferPointer { buf in
                buf.baseAddress!.initialize(from: frames.advanced(by: firstPart), count: secondPart)
            }
            writeIndex = secondPart
        } else {
            writeIndex = (writeIndex + toWrite) % capacity
        }
        availableToRead += toWrite
        return toWrite
    }

    /// Read up to `count` samples into `frames`; returns number actually read.
    func read(_ frames: UnsafeMutablePointer<Float>, count: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let toRead = min(availableToRead, count)
        if toRead <= 0 { return 0 }

        let firstPart = min(capacity - readIndex, toRead)
        buffer.withUnsafeBufferPointer { buf in
            frames.initialize(from: buf.baseAddress!.advanced(by: readIndex), count: firstPart)
        }
        if toRead > firstPart {
            let secondPart = toRead - firstPart
            buffer.withUnsafeBufferPointer { buf in
                (frames + firstPart).initialize(from: buf.baseAddress!, count: secondPart)
            }
            readIndex = secondPart
        } else {
            readIndex = (readIndex + toRead) % capacity
        }
        availableToRead -= toRead
        return toRead
    }

    func reset() {
        lock.lock()
        readIndex = 0
        writeIndex = 0
        availableToRead = 0
        lock.unlock()
    }
}

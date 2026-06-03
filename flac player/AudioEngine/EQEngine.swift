import Foundation
import Accelerate

enum EQFilterType {
    case lowShelf, peaking, highShelf, lowPass, highPass
}

struct BiquadCoefficients {
    var b0: Double = 0, b1: Double = 0, b2: Double = 0
    var a1: Double = 0, a2: Double = 0
}

class ParametricEQBand {
    var type: EQFilterType
    var frequency: Double
    var gainDB: Double
    var q: Double
    
    private var coeffs: BiquadCoefficients
    private var targetCoeffs: BiquadCoefficients
    private var x1: Double = 0, x2: Double = 0
    private var y1: Double = 0, y2: Double = 0
    private let smoothing: Double = 0.05 // Prevents zipper noise

    init(type: EQFilterType, frequency: Double, sampleRate: Double, gainDB: Double, q: Double) {
        self.type = type
        self.frequency = frequency
        self.gainDB = gainDB
        self.q = q
        let c = Self.design(type: type, freq: frequency, fs: sampleRate, gainDB: gainDB, q: q)
        self.coeffs = c
        self.targetCoeffs = c
    }

    func updateParameters(frequency: Double, sampleRate: Double, gainDB: Double, q: Double) {
        self.frequency = frequency
        self.gainDB = gainDB
        self.q = q
        targetCoeffs = Self.design(type: type, freq: frequency, fs: sampleRate, gainDB: gainDB, q: q)
    }

    func process(buffer: UnsafeMutablePointer<Float>, frames: Int) {
        // Smooth coefficient transitions to prevent clicks
        coeffs.b0 += (targetCoeffs.b0 - coeffs.b0) * smoothing
        coeffs.b1 += (targetCoeffs.b1 - coeffs.b1) * smoothing
        coeffs.b2 += (targetCoeffs.b2 - coeffs.b2) * smoothing
        coeffs.a1 += (targetCoeffs.a1 - coeffs.a1) * smoothing
        coeffs.a2 += (targetCoeffs.a2 - coeffs.a2) * smoothing

        let b0 = Float(coeffs.b0), b1 = Float(coeffs.b1), b2 = Float(coeffs.b2)
        let a1 = Float(coeffs.a1), a2 = Float(coeffs.a2)
        var lx1 = Float(x1), lx2 = Float(x2)
        var ly1 = Float(y1), ly2 = Float(y2)

        for i in 0..<frames {
            let x = buffer[i]
            let y = b0 * x + b1 * lx1 + b2 * lx2 - a1 * ly1 - a2 * ly2
            buffer[i] = y
            lx2 = lx1; lx1 = x
            ly2 = ly1; ly1 = y
        }

        x1 = Double(lx1); x2 = Double(lx2)
        y1 = Double(ly1); y2 = Double(ly2)
    }

    // Audio Cookbook Biquad Math
    static func design(type: EQFilterType, freq: Double, fs: Double, gainDB: Double, q: Double) -> BiquadCoefficients {
        let w0 = 2.0 * .pi * freq / fs
        let alpha = sin(w0) / (2.0 * q)
        let A = pow(10.0, gainDB / 40.0)
        
        var b0, b1, b2, a0, a1, a2: Double
        
        switch type {
        case .peaking:
            b0 = 1.0 + alpha * A
            b1 = -2.0 * cos(w0)
            b2 = 1.0 - alpha * A
            a0 = 1.0 + alpha / A
            a1 = -2.0 * cos(w0)
            a2 = 1.0 - alpha / A
        case .lowShelf:
            b0 = A * ((A + 1.0) - (A - 1.0) * cos(w0) + 2.0 * sqrt(A) * alpha)
            b1 = 2.0 * A * ((A - 1.0) - (A + 1.0) * cos(w0))
            b2 = A * ((A + 1.0) - (A - 1.0) * cos(w0) - 2.0 * sqrt(A) * alpha)
            a0 = (A + 1.0) + (A - 1.0) * cos(w0) + 2.0 * sqrt(A) * alpha
            a1 = -2.0 * ((A - 1.0) + (A + 1.0) * cos(w0))
            a2 = (A + 1.0) + (A - 1.0) * cos(w0) - 2.0 * sqrt(A) * alpha
        case .highShelf:
            b0 = A * ((A + 1.0) + (A - 1.0) * cos(w0) + 2.0 * sqrt(A) * alpha)
            b1 = -2.0 * A * ((A - 1.0) + (A + 1.0) * cos(w0))
            b2 = A * ((A + 1.0) + (A - 1.0) * cos(w0) - 2.0 * sqrt(A) * alpha)
            a0 = (A + 1.0) - (A - 1.0) * cos(w0) + 2.0 * sqrt(A) * alpha
            a1 = 2.0 * ((A - 1.0) - (A + 1.0) * cos(w0))
            a2 = (A + 1.0) - (A - 1.0) * cos(w0) - 2.0 * sqrt(A) * alpha
        default: // Fallback to peaking
            return design(type: .peaking, freq: freq, fs: fs, gainDB: gainDB, q: q)
        }
        
        return BiquadCoefficients(b0: b0/a0, b1: b1/a0, b2: b2/a0, a1: a1/a0, a2: a2/a0)
    }
}

class EQEngine {
    private(set) var bypassed = false
    private var sampleRate: Double = 44100
    private let maxChannels = 2
    
    // PREAMP STATE
    public var preampGainDB: Double = 0.0
    private var currentLinearGain: Float = 1.0

    // PRESET STATE
    var bandFreqs: [Double] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    var bandGains: [Double] = Array(repeating: 0.0, count: 10)
    var bandQs: [Double] = Array(repeating: 0.707, count: 10)
    var bandTypes: [EQFilterType] = [.lowShelf, .peaking, .peaking, .peaking, .peaking, .peaking, .peaking, .peaking, .peaking, .highShelf]
    
    var bandCount: Int { return bandFreqs.count }
    private var bandsPerChannel: [[ParametricEQBand]] = []

    init() { allocateBands() }
    
    private func allocateBands() {
        bandsPerChannel = (0..<maxChannels).map { _ in
            (0..<bandFreqs.count).map { i in
                ParametricEQBand(type: bandTypes[i], frequency: bandFreqs[i], sampleRate: sampleRate, gainDB: bandGains[i], q: bandQs[i])
            }
        }
    }

    func setSampleRate(_ sr: Double) {
        guard sr != sampleRate else { return }
        sampleRate = sr
        allocateBands()
    }
    
    func setBypass(_ bypass: Bool) { bypassed = bypass }

    func updateBand(index: Int, frequency: Double? = nil, gainDB: Double? = nil, q: Double? = nil) {
        guard index < bandFreqs.count else { return }
        if let f = frequency { bandFreqs[index] = f }
        if let g = gainDB { bandGains[index] = g }
        if let qq = q { bandQs[index] = qq }

        for ch in 0..<maxChannels {
            bandsPerChannel[ch][index].updateParameters(
                frequency: bandFreqs[index], sampleRate: sampleRate, gainDB: bandGains[index], q: bandQs[index]
            )
        }
    }
    
    func loadPreset(preamp: Double, frequencies: [Double], gains: [Double], qs: [Double]) {
        self.preampGainDB = preamp
        for i in 0..<bandCount {
            if i < frequencies.count {
                updateBand(index: i, frequency: frequencies[i], gainDB: gains[i], q: qs[i])
            }
        }
    }

    // Argument label matching what line 450 in FLACPlayer.swift expects (frames:)
    func process(channel: Int, buffer: UnsafeMutablePointer<Float>, frames: Int) {
        guard !bypassed else { return }

        // 1. GLOBAL PREAMP DSP (With Accelerate Ramping)
        let targetGain = Float(pow(10.0, preampGainDB / 20.0))
        let diff = targetGain - currentLinearGain
        
        if abs(diff) > 0.0001 {
            var step: Float = diff / Float(frames)
            var startGain = currentLinearGain
            vDSP_vrampmul(buffer, 1, &startGain, &step, buffer, 1, vDSP_Length(frames))
            currentLinearGain = targetGain
        } else if targetGain != 1.0 {
            var staticGain = targetGain
            vDSP_vsmul(buffer, 1, &staticGain, buffer, 1, vDSP_Length(frames))
        }

        // 2. BIQUAD PROCESSING
        let bands = bandsPerChannel[channel]
        for band in bands {
            band.process(buffer: buffer, frames: frames)
        }
    }
}

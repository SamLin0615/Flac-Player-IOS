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
    private let smoothing: Double = 0.05

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

    static func design(type: EQFilterType, freq: Double, fs: Double, gainDB: Double, q: Double) -> BiquadCoefficients {
        let A = pow(10, gainDB / 40)
        let w0 = 2 * .pi * freq / fs
        let alpha = sin(w0) / (2 * q)
        let cosw0 = cos(w0)
        
        var b0, b1, b2, a0, a1, a2: Double
        
        switch type {
        case .peaking:
            b0 = 1 + alpha * A
            b1 = -2 * cosw0
            b2 = 1 - alpha * A
            a0 = 1 + alpha / A
            a1 = -2 * cosw0
            a2 = 1 - alpha / A
        case .lowShelf:
            let sqA = 2 * sqrt(A) * alpha
            b0 = A * ((A + 1) - (A - 1) * cosw0 + sqA)
            b1 = 2 * A * ((A - 1) - (A + 1) * cosw0)
            b2 = A * ((A + 1) - (A - 1) * cosw0 - sqA)
            a0 = (A + 1) + (A - 1) * cosw0 + sqA
            a1 = -2 * ((A - 1) + (A + 1) * cosw0)
            a2 = (A + 1) + (A - 1) * cosw0 - sqA
        case .highShelf:
            let sqA = 2 * sqrt(A) * alpha
            b0 = A * ((A + 1) + (A - 1) * cosw0 + sqA)
            b1 = -2 * A * ((A - 1) + (A + 1) * cosw0)
            b2 = A * ((A + 1) + (A - 1) * cosw0 - sqA)
            a0 = (A + 1) - (A - 1) * cosw0 + sqA
            a1 = 2 * ((A - 1) - (A + 1) * cosw0)
            a2 = (A + 1) - (A - 1) * cosw0 - sqA
        default:
            return BiquadCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)
        }
        
        return BiquadCoefficients(b0: b0/a0, b1: b1/a0, b2: b2/a0, a1: a1/a0, a2: a2/a0)
    }

    func process(_ input: UnsafeMutablePointer<Float>, frames: Int) {
        for i in 0..<frames {
            // Apply smoothing
            coeffs.b0 += smoothing * (targetCoeffs.b0 - coeffs.b0)
            coeffs.b1 += smoothing * (targetCoeffs.b1 - coeffs.b1)
            coeffs.b2 += smoothing * (targetCoeffs.b2 - coeffs.b2)
            coeffs.a1 += smoothing * (targetCoeffs.a1 - coeffs.a1)
            coeffs.a2 += smoothing * (targetCoeffs.a2 - coeffs.a2)
            
            let x0 = Double(input[i])
            let y0 = coeffs.b0 * x0 + coeffs.b1 * x1 + coeffs.b2 * x2 - coeffs.a1 * y1 - coeffs.a2 * y2
            
            x2 = x1; x1 = x0
            y2 = y1; y1 = y0
            
            input[i] = Float(y0)
        }
    }
}

class EQEngine {
    var bypassed = false
    private var sampleRate: Double = 44100
    private let maxChannels = 2
    
    var bandFreqs: [Double] = [60, 250, 1000, 4000, 12000]
    var bandGains: [Double] = [0, 0, 0, 0, 0]
    var bandQs: [Double] = [0.7, 1.0, 1.0, 1.0, 0.7]
    var bandTypes: [EQFilterType] = [.lowShelf, .peaking, .peaking, .peaking, .highShelf]
    
    var bandCount: Int {
        return bandFreqs.count
    }
    
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

    func process(channel: Int, buffer: UnsafeMutablePointer<Float>, frames: Int) {
        guard !bypassed, channel < maxChannels else { return }
        for band in bandsPerChannel[channel] {
            band.process(buffer, frames: frames)
        }
    }
}

import Foundation
import os

enum EQFilterType { case lowShelf, peaking, highShelf, lowPass, highPass }

struct BiquadCoefficients {
    var b0: Double = 1, b1: Double = 0, b2: Double = 0
    var a1: Double = 0, a2: Double = 0
}

final class EQEngine {
    static let defaultFrequencies: [Double] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    private(set) var bandFreqs = EQEngine.defaultFrequencies
    private(set) var bandGains = [Double](repeating: 0, count: 10)
    private(set) var bandQs = [Double](repeating: 0.707, count: 10)
    let bandTypes: [EQFilterType] = [.lowShelf, .peaking, .peaking, .peaking, .peaking, .peaking, .peaking, .peaking, .peaking, .highShelf]
    private(set) var bypassed = false
    private(set) var sampleRate: Double = 44100
    private(set) var effectivePreampDB: Double = 0
    var bandCount: Int { 10 }
    var preampGainDB: Double = 0 { didSet { requireMain(); publish(); persist() } }
    var autoPreamp = true { didSet { requireMain(); publish(); persist() } }
    var selectedPresetID: UUID? { didSet { requireMain(); persist() } }

    private let maxChannels = 2
    private let lock: UnsafeMutablePointer<os_unfair_lock> = {
        let pointer = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        pointer.initialize(to: os_unfair_lock())
        return pointer
    }()
    private var target = [BiquadCoefficients](repeating: BiquadCoefficients(), count: 10)
    private var targetGain: Float = 1
    private var targetBypass = false
    private var resetVersion = 0
    // Only the render thread touches the following state.
    private var renderCoefficients = [BiquadCoefficients](repeating: BiquadCoefficients(), count: 10)
    private var renderGain: Float = 1
    private var renderBypass = false
    private var renderResetVersion = -1
    private struct History {
        var x1: Double = 0, x2: Double = 0, y1: Double = 0, y2: Double = 0
    }
    private var histories = [History](repeating: History(), count: 20)

    private struct SavedState: Codable {
        let frequencies: [Double]
        let gains: [Double]
        let qs: [Double]
        let preamp: Double
        let autoPreamp: Bool
        let bypass: Bool
        let presetID: UUID?
    }

    init() {
        precondition(Thread.isMainThread)
        if let data = UserDefaults.standard.data(forKey: "EQState.v1"),
           let saved = try? JSONDecoder().decode(SavedState.self, from: data),
           Self.valid(frequencies: saved.frequencies, gains: saved.gains, qs: saved.qs), saved.preamp.isFinite {
            bandFreqs = saved.frequencies; bandGains = saved.gains; bandQs = saved.qs
            preampGainDB = saved.preamp; autoPreamp = saved.autoPreamp; bypassed = saved.bypass; selectedPresetID = saved.presetID
        }
        publish()
    }

    deinit { lock.deinitialize(count: 1); lock.deallocate() }

    private func requireMain() { precondition(Thread.isMainThread, "EQ controls must run on main") }
    private static func valid(frequencies: [Double], gains: [Double], qs: [Double]) -> Bool {
        frequencies.count == 10 && gains.count == 10 && qs.count == 10 &&
        frequencies.allSatisfy { $0.isFinite && $0 >= 20 && $0 <= 20000 } &&
        gains.allSatisfy { $0.isFinite && abs($0) <= 24 } && qs.allSatisfy { $0.isFinite && $0 >= 0.1 && $0 <= 10 }
    }
    private func persist() {
        let state = SavedState(frequencies: bandFreqs, gains: bandGains, qs: bandQs, preamp: preampGainDB,
                               autoPreamp: autoPreamp, bypass: bypassed, presetID: selectedPresetID)
        if let data = try? JSONEncoder().encode(state) { UserDefaults.standard.set(data, forKey: "EQState.v1") }
    }
    private func publish() {
        let coefficients = (0..<bandCount).map {
            Self.coefficients(type: bandTypes[$0], frequency: bandFreqs[$0], sampleRate: sampleRate, gainDB: bandGains[$0], q: bandQs[$0])
        }
        var boost = 0.0
        if autoPreamp {
            let upper = min(20000, sampleRate * 0.499)
            for point in 0..<200 {
                let frequency = exp(log(20) + Double(point) / 199 * (log(upper) - log(20)))
                boost = max(boost, Self.magnitudeResponseDB(at: frequency, sampleRate: sampleRate, coefficients: coefficients))
            }
        }
        effectivePreampDB = (preampGainDB.isFinite ? preampGainDB : 0) - boost
        os_unfair_lock_lock(lock)
        target = coefficients
        targetGain = Float(pow(10, effectivePreampDB / 20))
        targetBypass = bypassed
        os_unfair_lock_unlock(lock)
    }

    func setSampleRate(_ rate: Double) {
        requireMain(); guard rate.isFinite, rate > 40 else { return }
        sampleRate = rate; publish(); reset()
    }
    func setBypass(_ bypass: Bool) { requireMain(); bypassed = bypass; publish(); persist() }
    func reset() { requireMain(); os_unfair_lock_lock(lock); resetVersion += 1; os_unfair_lock_unlock(lock) }
    func updateBand(index: Int, frequency: Double? = nil, gainDB: Double? = nil, q: Double? = nil) {
        requireMain(); guard (0..<bandCount).contains(index) else { return }
        if let frequency = frequency, frequency.isFinite { bandFreqs[index] = min(20000, max(20, frequency)) }
        if let gain = gainDB, gain.isFinite { bandGains[index] = min(24, max(-24, gain)) }
        if let q = q, q.isFinite { bandQs[index] = min(10, max(0.1, q)) }
        selectedPresetID = nil
        publish(); persist()
    }
    func loadPreset(preamp: Double, frequencies: [Double], gains: [Double], qs: [Double]) {
        requireMain(); guard preamp.isFinite, Self.valid(frequencies: frequencies, gains: gains, qs: qs) else { return }
        bandFreqs = frequencies; bandGains = gains; bandQs = qs
        selectedPresetID = nil
        preampGainDB = preamp
        publish(); persist()
    }

    // Called once per render quantum, before any channels are processed.
    func beginRender() {
        guard os_unfair_lock_trylock(lock) else { return }
        for index in 0..<10 { renderCoefficients[index] = target[index] }
        renderGain = targetGain; renderBypass = targetBypass
        if renderResetVersion != resetVersion {
            for index in histories.indices { histories[index] = History() }
            renderResetVersion = resetVersion
        }
        os_unfair_lock_unlock(lock)
    }
    func process(channel: Int, buffer: UnsafeMutablePointer<Float>, frames: Int) {
        guard channel >= 0, channel < maxChannels, frames > 0, !renderBypass else { return }
        for frame in 0..<frames { buffer[frame] *= renderGain }
        for band in 0..<10 {
            let coefficient = renderCoefficients[band]
            if coefficient.b0 == 1 && coefficient.b1 == 0 && coefficient.b2 == 0 && coefficient.a1 == 0 && coefficient.a2 == 0 { continue }
            let index = channel * 10 + band
            var state = histories[index]
            for frame in 0..<frames {
                let input = Double(buffer[frame])
                let output = coefficient.b0 * input + coefficient.b1 * state.x1 + coefficient.b2 * state.x2 - coefficient.a1 * state.y1 - coefficient.a2 * state.y2
                buffer[frame] = Float(output)
                state.x2 = state.x1; state.x1 = input; state.y2 = state.y1; state.y1 = output
            }
            histories[index] = state
        }
    }

    static func magnitudeResponseDB(at frequency: Double, sampleRate: Double, coefficients: [BiquadCoefficients]) -> Double {
        guard frequency.isFinite, sampleRate > 0 else { return 0 }
        let omega = 2 * Double.pi * frequency / sampleRate
        let c1 = cos(omega), s1 = sin(omega), c2 = cos(2 * omega), s2 = sin(2 * omega)
        return coefficients.reduce(0) { result, c in
            let nr = c.b0 + c.b1 * c1 + c.b2 * c2
            let ni = -c.b1 * s1 - c.b2 * s2
            let dr = 1 + c.a1 * c1 + c.a2 * c2
            let di = -c.a1 * s1 - c.a2 * s2
            return result + 10 * log10(max(1e-30, nr * nr + ni * ni) / max(1e-30, dr * dr + di * di))
        }
    }

    static func coefficients(type: EQFilterType, frequency: Double, sampleRate: Double, gainDB: Double, q: Double) -> BiquadCoefficients {
        guard sampleRate > 0, frequency.isFinite, gainDB.isFinite, q.isFinite else { return BiquadCoefficients() }
        if gainDB == 0 && type != .lowPass && type != .highPass { return BiquadCoefficients() }
        let frequency = min(max(1, frequency), sampleRate * 0.499)
        let omega = 2 * Double.pi * frequency / sampleRate
        let cosine = cos(omega), alpha = sin(omega) / (2 * max(0.1, q))
        let a = pow(10, gainDB / 40), root = 2 * sqrt(a) * alpha
        let b0, b1, b2, a0, a1, a2: Double
        switch type {
        case .peaking:
            b0 = 1 + alpha * a; b1 = -2 * cosine; b2 = 1 - alpha * a
            a0 = 1 + alpha / a; a1 = -2 * cosine; a2 = 1 - alpha / a
        case .lowShelf:
            b0 = a * ((a + 1) - (a - 1) * cosine + root)
            b1 = 2 * a * ((a - 1) - (a + 1) * cosine)
            b2 = a * ((a + 1) - (a - 1) * cosine - root)
            a0 = (a + 1) + (a - 1) * cosine + root
            a1 = -2 * ((a - 1) + (a + 1) * cosine)
            a2 = (a + 1) + (a - 1) * cosine - root
        case .highShelf:
            b0 = a * ((a + 1) + (a - 1) * cosine + root)
            b1 = -2 * a * ((a - 1) + (a + 1) * cosine)
            b2 = a * ((a + 1) + (a - 1) * cosine - root)
            a0 = (a + 1) - (a - 1) * cosine + root
            a1 = 2 * ((a - 1) - (a + 1) * cosine)
            a2 = (a + 1) - (a - 1) * cosine - root
        case .lowPass:
            b0 = (1 - cosine) / 2; b1 = 1 - cosine; b2 = b0
            a0 = 1 + alpha; a1 = -2 * cosine; a2 = 1 - alpha
        case .highPass:
            b0 = (1 + cosine) / 2; b1 = -(1 + cosine); b2 = b0
            a0 = 1 + alpha; a1 = -2 * cosine; a2 = 1 - alpha
        }
        return BiquadCoefficients(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }
}

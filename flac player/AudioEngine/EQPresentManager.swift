import Foundation
import Combine

public struct EQPreset: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var preampGainDB: Double
    public var frequencies: [Double]
    public var gains: [Double]
    public var qs: [Double]
    
    // Explicit initializer to prevent compiler memberwise initialization bugs
    public init(id: UUID = UUID(), name: String, preampGainDB: Double, frequencies: [Double], gains: [Double], qs: [Double]) {
        self.id = id
        self.name = name
        self.preampGainDB = preampGainDB
        self.frequencies = frequencies
        self.gains = gains
        self.qs = qs
    }
    
    // A standard neutral / flat profile
    public static let neutral = EQPreset(
        name: "Flat / Neutral",
        preampGainDB: 0.0,
        frequencies: [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000],
        gains: Array(repeating: 0.0, count: 10),
        qs: Array(repeating: 0.707, count: 10)
    )
}

public class EQPresetManager: ObservableObject {
    @Published public var presets: [EQPreset] = []
    private let storageKey = "AudiophileEQPresets"
    
    public init() {
        loadPresets()
    }
    
    public func loadPresets() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([EQPreset].self, from: data) {
            presets = saved
        }
        
        if presets.isEmpty {
            presets = [.neutral]
        }
    }
    
    public func savePreset(name: String, preamp: Double, freqs: [Double], gains: [Double], qs: [Double]) {
        let newPreset = EQPreset(name: name, preampGainDB: preamp, frequencies: freqs, gains: gains, qs: qs)
        presets.append(newPreset)
        persist()
    }
    
    public func deletePreset(at offsets: IndexSet) {
        // Native Swift array removal without requiring a SwiftUI import
        for index in offsets.sorted(by: >) {
            presets.remove(at: index)
        }
        if presets.isEmpty { presets = [.neutral] }
        persist()
    }
    
    private func persist() {
        if let encoded = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
}

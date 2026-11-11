import Foundation
import Combine

struct EQPreset: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var preampGainDB: Double
    var frequencies: [Double]
    var gains: [Double]
    var qs: [Double]
    var isBuiltIn: Bool
    
    init(id: UUID = UUID(), name: String, preampGainDB: Double, frequencies: [Double], gains: [Double], qs: [Double], isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.preampGainDB = preampGainDB
        self.frequencies = frequencies
        self.gains = gains
        self.qs = qs
        self.isBuiltIn = isBuiltIn
    }
    
    static let neutral = EQPreset(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Flat",
        preampGainDB: 0.0,
        frequencies: [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000],
        gains: Array(repeating: 0.0, count: 10),
        qs: Array(repeating: 0.707, count: 10), isBuiltIn: true
    )

    private enum CodingKeys: String, CodingKey { case id, name, preampGainDB, frequencies, gains, qs, isBuiltIn }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        preampGainDB = try values.decode(Double.self, forKey: .preampGainDB)
        frequencies = try values.decode([Double].self, forKey: .frequencies)
        gains = try values.decode([Double].self, forKey: .gains)
        qs = try values.decode([Double].self, forKey: .qs)
        isBuiltIn = try values.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
    }
}

final class EQPresetManager: ObservableObject {
    @Published private(set) var userPresets: [EQPreset] = []
    let builtInPresets: [EQPreset] = {
        let definitions: [(String, [Double])] = [
            ("Flat", [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
            ("Bass Boost", [5, 4, 3, 1, 0, 0, 0, 0, 0, 0]),
            ("Bass Reducer", [-5, -4, -3, -1, 0, 0, 0, 0, 0, 0]),
            ("Treble Boost", [0, 0, 0, 0, 0, 0, 1, 2, 3, 4]),
            ("Treble Reducer", [0, 0, 0, 0, 0, 0, -1, -2, -3, -4]),
            ("Vocal / Presence", [-2, -1, 0, 0, 1, 2, 3, 2, 0, -1]),
            ("Loudness", [5, 4, 2, 0, -1, -1, 0, 1, 3, 4]),
            ("Warm", [3, 2, 2, 1, 0, 0, -1, -1, -2, -2]),
            ("Bright", [-2, -1, 0, 0, 0, 1, 2, 3, 3, 2]),
            ("Rock", [4, 3, 1, -1, -2, 0, 2, 3, 3, 2]),
            ("Jazz", [3, 2, 1, 0, -1, 0, 1, 2, 2, 3]),
            ("Classical", [2, 1, 0, 0, -1, -1, 0, 1, 2, 2]),
            ("Electronic", [5, 4, 2, 0, -2, -1, 1, 2, 3, 4]),
            ("Acoustic", [1, 1, 2, 1, 0, 1, 2, 2, 1, 1]),
            ("Spoken Word", [-4, -3, -1, 0, 1, 3, 4, 2, -1, -2])
        ]
        return definitions.enumerated().map { index, item in
            EQPreset(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
                     name: item.0, preampGainDB: 0, frequencies: EQEngine.defaultFrequencies,
                     gains: item.1, qs: Array(repeating: 0.707, count: 10), isBuiltIn: true)
        }
    }()
    var presets: [EQPreset] { builtInPresets + userPresets }
    private let storageKey = "AudiophileEQPresets"
    
    init() {
        loadPresets()
    }
    
    func loadPresets() {
        precondition(Thread.isMainThread)
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([EQPreset].self, from: data) {
            userPresets = saved.filter { !$0.isBuiltIn && $0.name != "Flat / Neutral" }
            persist()
        }
    }

    @discardableResult
    func savePreset(name: String, from player: FLACPlayer) -> EQPreset {
        precondition(Thread.isMainThread)
        let preset = EQPreset(name: name, preampGainDB: player.preampGainDB,
                              frequencies: player.eqFrequencies, gains: player.eqGains, qs: player.eqQs)
        userPresets.append(preset)
        persist()
        return preset
    }

    func updatePreset(_ preset: EQPreset, from player: FLACPlayer) {
        precondition(Thread.isMainThread)
        guard !preset.isBuiltIn, let index = userPresets.firstIndex(where: { $0.id == preset.id }) else { return }
        userPresets[index] = EQPreset(id: preset.id, name: userPresets[index].name, preampGainDB: player.preampGainDB,
                                      frequencies: player.eqFrequencies, gains: player.eqGains, qs: player.eqQs)
        persist()
    }
    func renamePreset(_ preset: EQPreset, name: String) {
        precondition(Thread.isMainThread)
        guard !preset.isBuiltIn, let index = userPresets.firstIndex(where: { $0.id == preset.id }) else { return }
        userPresets[index].name = name
        persist()
    }
    func deletePreset(_ preset: EQPreset) {
        precondition(Thread.isMainThread)
        guard !preset.isBuiltIn else { return }
        userPresets.removeAll { $0.id == preset.id }
        persist()
    }
    
    private func persist() {
        if let encoded = try? JSONEncoder().encode(userPresets) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
}

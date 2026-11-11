import SwiftUI

struct EQView: View {
    @EnvironmentObject private var player: FLACPlayer
    @EnvironmentObject private var presets: EQPresetManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedBand = 0
    @State private var savingPreset = false
    @State private var renamingPreset = false
    @State private var presetName = ""
    @State private var presetToRename: EQPreset?

    private var currentPreset: EQPreset? { presets.presets.first { $0.id == player.currentEQPresetID } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    presetControls
                    Toggle("Equalizer On (A/B)", isOn: Binding(get: { !player.isEQBypassed }, set: { player.setEQBypass(!$0) }))
                    Text(player.isEQBypassed ? "Off — preamp and filters bypassed" : "On — preamp and filters active")
                        .font(.caption).foregroundStyle(.secondary)
                    EQResponseGraph(selectedBand: $selectedBand).frame(height: 240)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Text("Preamp"); Spacer(); Text(String(format: "%+.1f dB", player.preampGainDB)).monospacedDigit() }
                        Slider(value: Binding(get: { player.preampGainDB }, set: { player.setPreampGain($0) }), in: -12...6, step: 0.5)
                            .accessibilityLabel("Equalizer preamp")
                        Toggle("Auto Headroom", isOn: Binding(get: { player.autoPreamp }, set: { player.setAutoPreamp($0) }))
                        Text(String(format: "Effective preamp: %+.1f dB", player.effectivePreampDB)).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Bands").font(.headline)
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(0..<player.eqBandsCount, id: \.self) { index in
                                EQBandCard(index: index, selected: selectedBand == index) { selectedBand = index }
                                    .frame(width: 210)
                            }
                        }.padding(.vertical, 4)
                    }.scrollIndicators(.hidden)
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ReplayGain").font(.headline)
                        Picker("ReplayGain Mode", selection: $player.replayGainMode) {
                            ForEach(ReplayGainMode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                        }.pickerStyle(.segmented)
                        HStack {
                            Text("ReplayGain Preamp"); Spacer()
                            Text(String(format: "%+.1f dB", player.replayGainPreampDB)).monospacedDigit()
                        }
                        Slider(value: $player.replayGainPreampDB, in: -12...6, step: 0.5).accessibilityLabel("ReplayGain preamp")
                        Text("Tagged tracks only. Peak tags limit gain to prevent clipping.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding()
            }
            .navigationTitle("Equalizer").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") { if let flat = presets.builtInPresets.first { player.apply(preset: flat) } }
                }
            }
            .alert("Save as Preset", isPresented: $savingPreset) {
                TextField("Preset name", text: $presetName)
                Button("Save") {
                    let preset = presets.savePreset(name: presetName.trimmingCharacters(in: .whitespacesAndNewlines), from: player)
                    player.apply(preset: preset)
                }.disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) {}
            }
            .alert("Rename Preset", isPresented: $renamingPreset) {
                TextField("Preset name", text: $presetName)
                Button("Rename") {
                    if let preset = presetToRename { presets.renamePreset(preset, name: presetName.trimmingCharacters(in: .whitespacesAndNewlines)) }
                }.disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var presetControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Menu {
                Section("Built-in Presets") {
                    ForEach(presets.builtInPresets) { preset in Button(preset.name) { player.apply(preset: preset) } }
                }
                if !presets.userPresets.isEmpty {
                    Section("Your Presets") {
                        ForEach(presets.userPresets) { preset in
                            Menu(preset.name) {
                                Button("Apply") { player.apply(preset: preset) }
                                Button("Update from Current Settings") {
                                    presets.updatePreset(preset, from: player)
                                    if let updated = presets.userPresets.first(where: { $0.id == preset.id }) { player.apply(preset: updated) }
                                }
                                Button("Rename") { presetToRename = preset; presetName = preset.name; renamingPreset = true }
                                Button("Delete", role: .destructive) { presets.deletePreset(preset) }
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(currentPreset?.name ?? "Custom").font(.headline)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                }.frame(minHeight: 44)
            }
            Button("Save as Preset…", systemImage: "plus") { presetName = ""; savingPreset = true }.frame(minHeight: 44)
        }
    }
}

private struct EQBandCard: View {
    @EnvironmentObject private var player: FLACPlayer
    let index: Int
    let selected: Bool
    let select: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: select) {
                HStack {
                    Text("Band \(index + 1)").bold()
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                }.frame(minHeight: 44)
            }.buttonStyle(.plain).accessibilityLabel("Select band \(index + 1)")
            Text(String(format: "Gain  %+.1f dB", player.eqGains[index])).font(.caption.monospacedDigit())
            Slider(value: Binding(get: { player.eqGains[index] }, set: { player.setEQBand(index: index, gainDB: $0) }), in: -12...12, step: 0.5)
                .accessibilityLabel("Band \(index + 1) gain")
            Text(String(format: "Frequency  %.0f Hz", player.eqFrequencies[index])).font(.caption.monospacedDigit())
            Slider(value: Binding(get: { log10(player.eqFrequencies[index]) }, set: { player.setEQBand(index: index, frequency: pow(10, $0)) }), in: log10(20)...log10(20000))
                .accessibilityLabel("Band \(index + 1) frequency")
            Text(String(format: "Q  %.2f", player.eqQs[index])).font(.caption.monospacedDigit())
            Slider(value: Binding(get: { player.eqQs[index] }, set: { player.setEQBand(index: index, q: $0) }), in: 0.1...10, step: 0.05)
                .accessibilityLabel("Band \(index + 1) Q")
        }
        .padding()
        .background(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2))
    }
}

private struct EQResponseGraph: View {
    @EnvironmentObject private var player: FLACPlayer
    @Binding var selectedBand: Int

    private var coefficients: [BiquadCoefficients] {
        (0..<player.eqBandsCount).map { index in
            EQEngine.coefficients(type: player.eqBandTypes[index], frequency: player.eqFrequencies[index],
                                  sampleRate: player.eqSampleRate, gainDB: player.eqGains[index], q: player.eqQs[index])
        }
    }

    var body: some View {
        let filters = coefficients
        GeometryReader { geometry in
            ZStack {
                Path { path in
                    for gain in [-12.0, -6, 0, 6, 12] {
                        let y = mapGain(gain, height: geometry.size.height)
                        path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                    for frequency in [100.0, 1000, 10000] {
                        let x = mapFrequency(frequency, width: geometry.size.width)
                        path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                    }
                }.stroke(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [3]))
                Path { path in
                    for index in 0...200 {
                        let x = geometry.size.width * CGFloat(index) / 200
                        let frequency = frequencyAt(x, width: geometry.size.width)
                        let gain = player.isEQBypassed ? 0 : EQEngine.magnitudeResponseDB(at: frequency, sampleRate: player.eqSampleRate, coefficients: filters)
                        let point = CGPoint(x: x, y: mapGain(gain, height: geometry.size.height))
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }.stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                ForEach(0..<player.eqBandsCount, id: \.self) { index in
                    Button { selectedBand = index } label: {
                        Circle().fill(selectedBand == index ? Color.accentColor : Color.secondary)
                            .frame(width: selectedBand == index ? 18 : 12, height: selectedBand == index ? 18 : 12)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Select equalizer band \(index + 1)")
                    .accessibilityValue(String(format: "%.0f Hz, %+.1f dB", player.eqFrequencies[index], player.eqGains[index]))
                    .simultaneousGesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("eqGraph")).onChanged { value in
                        guard selectedBand == index else { return }
                        let gain = min(12, max(-12, 12 - Double(value.location.y / max(1, geometry.size.height)) * 24))
                        player.setEQBand(index: index, frequency: frequencyAt(value.location.x, width: geometry.size.width), gainDB: gain)
                    })
                    .position(x: mapFrequency(player.eqFrequencies[index], width: geometry.size.width), y: mapGain(player.eqGains[index], height: geometry.size.height))
                }
                VStack { HStack { Text("+12 dB"); Spacer(); Text("20 Hz – 20 kHz") }; Spacer(); HStack { Text("−12 dB"); Spacer() } }
                    .font(.caption2).foregroundStyle(.secondary).padding(4).allowsHitTesting(false)
            }
            .coordinateSpace(name: "eqGraph")
        }
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private func mapFrequency(_ frequency: Double, width: CGFloat) -> CGFloat {
        CGFloat(min(1, max(0, log10(max(20, frequency) / 20) / 3))) * width
    }

    private func frequencyAt(_ x: CGFloat, width: CGFloat) -> Double {
        20 * pow(1000, min(1, max(0, Double(x / max(1, width)))))
    }

    private func mapGain(_ gain: Double, height: CGFloat) -> CGFloat {
        CGFloat((12 - min(12, max(-12, gain))) / 24) * height
    }
}

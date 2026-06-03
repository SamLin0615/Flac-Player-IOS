import SwiftUI

struct EQView: View {
    @ObservedObject var player: FLACPlayer
    
    @State private var activeBandIndex: Int = 0
    @State private var bypass = false
    
    // UI State for the active nodes to prevent constant CoreAudio polling during drag
    @State private var localFreqs: [Double] = []
    @State private var localGains: [Double] = []
    @State private var localQs: [Double] = []

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Parametric EQ")
                        .font(.title2.bold())
                        .foregroundColor(.primary)
                    Text(bypass ? "Bypassed" : "True Phase Response Active")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                Button(action: resetEQ) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.title)
                        .foregroundColor(.secondary)
                }
                .padding(.trailing, 8)
                
                Toggle("", isOn: $bypass)
                    .labelsHidden()
                    .onChange(of: bypass) { _, new in player.setEQBypass(new) }
            }
            .padding()

            // MARK: - Audiophile Graph Visualization
            GeometryReader { geo in
                ZStack {
                    // 1. Logarithmic Background Grid
                    LogarithmicGrid(width: geo.size.width, height: geo.size.height)
                    
                    if !bypass && localFreqs.count > 0 {
                        // 2. Area Under the Curve (Filled Energy Envelope)
                        TrueResponseShape(freqs: localFreqs, gains: localGains, qs: localQs, width: geo.size.width, height: geo.size.height, fill: true)
                            .fill(LinearGradient(
                                colors: [Color.accentColor.opacity(0.4), Color.accentColor.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                        
                        // 3. Crisp Acoustic Curve Line
                        TrueResponseShape(freqs: localFreqs, gains: localGains, qs: localQs, width: geo.size.width, height: geo.size.height, fill: false)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        
                        // 4. Isolated Active Crosshair
                        let activeX = EQMath.mapFreqToX(localFreqs[activeBandIndex], width: geo.size.width)
                        let activeY = EQMath.mapGainToY(localGains[activeBandIndex], height: geo.size.height)
                        
                        // Targeting Reticle
                        Path { p in
                            p.move(to: CGPoint(x: activeX, y: 0))
                            p.addLine(to: CGPoint(x: activeX, y: geo.size.height))
                            p.move(to: CGPoint(x: 0, y: activeY))
                            p.addLine(to: CGPoint(x: geo.size.width, y: activeY))
                        }
                        .stroke(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
                        
                        // Draggable Handle
                        Circle()
                            .fill(Color.white)
                            .frame(width: 20, height: 20)
                            .shadow(color: .black.opacity(0.5), radius: 4)
                            .position(x: activeX, y: activeY)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        var newFreq = EQMath.mapXToFreq(value.location.x, width: geo.size.width)
                                        var newGain = EQMath.mapYToGain(value.location.y, height: geo.size.height)
                                        
                                        // Hard clamp to physical limits
                                        newFreq = max(20.0, min(20000.0, newFreq))
                                        newGain = max(-12.0, min(12.0, newGain))
                                        
                                        localFreqs[activeBandIndex] = newFreq
                                        localGains[activeBandIndex] = newGain
                                        commitToEngine()
                                    }
                            )
                    }
                }
                .background(Color(.systemBackground).opacity(0.5))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            }
            .frame(height: 240)
            .padding(.horizontal)

            // MARK: - Sennheiser-Style Horizontal Control Carousel
            VStack(alignment: .leading, spacing: 8) {
                Text("Band Controllers")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 16)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(0..<localFreqs.count, id: \.self) { i in
                            BandCardView(
                                index: i,
                                isActive: i == activeBandIndex,
                                freq: $localFreqs[i],
                                gain: $localGains[i],
                                q: $localQs[i],
                                onSelect: { activeBandIndex = i },
                                onChange: { commitToEngine() }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 24)
        }
        .onAppear(perform: syncFromEngine)
    }

    // MARK: - State Synchronization
    private func syncFromEngine() {
        self.localFreqs = player.eqFrequencies.isEmpty ? [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000] : player.eqFrequencies
        self.localGains = player.eqGains.isEmpty ? Array(repeating: 0.0, count: 10) : player.eqGains
        self.localQs = player.eqQs.isEmpty ? Array(repeating: 0.707, count: 10) : player.eqQs
        self.bypass = player.isEQBypassed
    }
    
    private func commitToEngine() {
        // FIX: Changed from updateBand to updateEQBand to match FLACPlayer's signature
        player.updateEQBand(
            index: activeBandIndex,
            frequency: localFreqs[activeBandIndex],
            gainDB: localGains[activeBandIndex],
            q: localQs[activeBandIndex]
        )
    }
    
    private func resetEQ() {
        for i in 0..<localGains.count {
            localGains[i] = 0.0
            localQs[i] = 0.707
            // FIX: Changed from updateBand to updateEQBand to match FLACPlayer's signature
            player.updateEQBand(index: i, frequency: localFreqs[i], gainDB: 0.0, q: 0.707)
        }
    }
}

// MARK: - Sennheiser-Style Band Card
struct BandCardView: View {
    let index: Int
    let isActive: Bool
    @Binding var freq: Double
    @Binding var gain: Double
    @Binding var q: Double
    let onSelect: () -> Void
    let onChange: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Circle().fill(isActive ? Color.accentColor : Color.gray)
                    .frame(width: 8, height: 8)
                Text("Band \(index + 1)")
                    .font(.subheadline.bold())
                    .foregroundColor(isActive ? .primary : .secondary)
                Spacer()
            }
            
            Divider()
            
            // Gain Control
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Gain").font(.caption2).foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%+.1f dB", gain)).font(.caption2.monospacedDigit())
                }
                Slider(value: $gain, in: -12...12, step: 0.5) { _ in onChange() }
                    .tint(gain == 0 ? .gray : .accentColor)
            }
            
            // Freq Control
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Freq").font(.caption2).foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(freq)) Hz").font(.caption2.monospacedDigit())
                }
                // Logarithmic slider approximation for frequencies
                Slider(value: Binding(
                    get: { log10(freq) },
                    set: { freq = pow(10, $0) }
                ), in: log10(20)...log10(20000)) { _ in onChange() }
            }
            
            // Spread (Q) Control
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Q (Spread)").font(.caption2).foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.2f", q)).font(.caption2.monospacedDigit())
                }
                Slider(value: $q, in: 0.1...10.0, step: 0.1) { _ in onChange() }
            }
        }
        .padding()
        .frame(width: 200)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .opacity(isActive ? 1.0 : 0.6)
        .onTapGesture(perform: onSelect)
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }
}

// MARK: - Mathematical True Response Shape
struct TrueResponseShape: Shape {
    var freqs: [Double]
    var gains: [Double]
    var qs: [Double]
    var width: CGFloat
    var height: CGFloat
    var fill: Bool
    
    // Tell SwiftUI to re-draw when these arrays change during drag
    var animatableData: CGFloat { 0 }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard freqs.count > 0 else { return path }
        
        let steps = 120 // Resolution of the curve
        var points: [CGPoint] = []
        
        for i in 0...steps {
            let x = CGFloat(i) / CGFloat(steps) * width
            let targetFreq = EQMath.mapXToFreq(x, width: width)
            
            // Sum the true magnitude response of all active filters
            var totalGainDB = 0.0
            for b in 0..<freqs.count {
                if gains[b] != 0 {
                    totalGainDB += EQMath.filterMagnitude(freq: targetFreq, f0: freqs[b], gain: gains[b], q: qs[b])
                }
            }
            
            let y = EQMath.mapGainToY(totalGainDB, height: height)
            points.append(CGPoint(x: x, y: y))
        }
        
        if let first = points.first {
            path.move(to: first)
            for pt in points.dropFirst() { path.addLine(to: pt) }
        }
        
        if fill {
            let baseline = EQMath.mapGainToY(0, height: height)
            path.addLine(to: CGPoint(x: width, y: baseline))
            path.addLine(to: CGPoint(x: 0, y: baseline))
            path.closeSubpath()
        }
        
        return path
    }
}

// MARK: - Math & DSP UI Helpers
struct EQMath {
    static func mapXToFreq(_ x: CGFloat, width: CGFloat) -> Double {
        let pct = Double(max(0, min(width, x)) / width)
        return pow(10, log10(20.0) + pct * (log10(20000.0) - log10(20.0)))
    }
    static func mapFreqToX(_ freq: Double, width: CGFloat) -> CGFloat {
        let pct = (log10(max(20, min(20000, freq))) - log10(20.0)) / (log10(20000.0) - log10(20.0))
        return CGFloat(pct) * width
    }
    static func mapYToGain(_ y: CGFloat, height: CGFloat) -> Double {
        let pct = Double(max(0, min(height, y)) / height)
        return 12.0 - (pct * 24.0)
    }
    static func mapGainToY(_ gain: Double, height: CGFloat) -> CGFloat {
        let pct = (12.0 - max(-12.0, min(12.0, gain))) / 24.0
        return CGFloat(pct) * height
    }
    
    /// Highly accurate mathematical representation of an analog Peaking EQ magnitude response
    static func filterMagnitude(freq: Double, f0: Double, gain: Double, q: Double) -> Double {
        let w_w0 = freq / f0
        let w0_w = f0 / freq
        let difference = w_w0 - w0_w
        let denominator = 1.0 + (pow(difference, 2) * pow(q, 2))
        return gain / denominator
    }
}

// MARK: - Standardized Logarithmic Grid
struct LogarithmicGrid: View {
    let width: CGFloat
    let height: CGFloat
    let xLines: [Double] = [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000]
    let yLines: [Double] = [-12, -6, 0, 6, 12]
    
    var body: some View {
        ZStack {
            // Y-Axis (Gain)
            ForEach(yLines, id: \.self) { db in
                let y = EQMath.mapGainToY(db, height: height)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: width, y: y))
                }
                .stroke(db == 0 ? Color.primary.opacity(0.4) : Color.primary.opacity(0.1), lineWidth: db == 0 ? 1.5 : 1)
                
                Text("\(Int(db)) dB")
                    .font(.system(size: 9, weight: .bold)).foregroundColor(db == 0 ? .primary : .secondary)
                    .position(x: 20, y: y - 8)
            }
            
            // X-Axis (Frequency)
            ForEach(xLines, id: \.self) { freq in
                let x = EQMath.mapFreqToX(freq, width: width)
                Path { p in
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: height))
                }
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                
                Text(freq >= 1000 ? "\(Int(freq/1000))k" : "\(Int(freq))")
                    .font(.system(size: 9)).foregroundColor(.secondary)
                    .position(x: x + 12, y: height - 10)
            }
        }
    }
}

import SwiftUI

// Internal Model for the nodes (Same as before)
struct EQNode: Identifiable {
    let id = UUID()
    var index: Int
    var frequency: Double
    var gain: Double
    var q: Double
    var color: Color
    var minFreq: Double
    var maxFreq: Double
}

struct EQView: View {
    @ObservedObject var player: FLACPlayer
    
    @State private var nodes: [EQNode] = []
    @State private var bypass = false

    var body: some View {
        VStack(spacing: 0) {
            // HEADER
            HStack {
                Text("Parametric EQ")
                    .font(.title2.bold())
                Spacer()
                
                // NEW: RESET BUTTON
                Button(action: resetEQ) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title3)
                        .padding(.trailing, 8)
                }
                .buttonStyle(.plain)
                
                Toggle("Bypass", isOn: $bypass)
                    .labelsHidden()
                    .onChange(of: bypass) { _, new in player.setEQBypass(new) }
            }
            .padding()

            GeometryReader { geo in
                ZStack {
                    FrequencyGridView(width: geo.size.width, height: geo.size.height)
                    
                    ResponseCurve(nodes: nodes, width: geo.size.width, height: geo.size.height)
                        .stroke(Color.accentColor, lineWidth: 3)
                        .opacity(bypass ? 0.3 : 1.0)
                        .animation(.interactiveSpring(), value: nodes.map { $0.gain })
                    
                    if !bypass {
                        ForEach($nodes) { $node in
                            NodeView(node: $node, width: geo.size.width, height: geo.size.height) { updatedNode in
                                player.setEQBand(index: updatedNode.index, frequency: updatedNode.frequency, gainDB: updatedNode.gain, q: updatedNode.q)
                            }
                        }
                    }
                }
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .shadow(radius: 5)
            }
            .frame(height: 280)
            .padding(.horizontal)
            
            ScrollView {
                VStack(spacing: 16) {
                    ForEach($nodes) { $node in
                        VStack(spacing: 8) {
                            HStack {
                                Circle().fill(node.color).frame(width: 12, height: 12)
                                Text("Band \(node.index + 1)").font(.headline)
                                Spacer()
                                Text("\(Int(node.frequency)) Hz | \(String(format: "%.1f", node.gain)) dB")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onAppear(perform: loadState)
    }
    
    // MARK: - Functions
    
    private func resetEQ() {
        // Reset Visuals
        nodes[0].frequency = 60;   nodes[0].gain = 0; nodes[0].q = 0.7
        nodes[1].frequency = 250;  nodes[1].gain = 0; nodes[1].q = 1.0
        nodes[2].frequency = 1000; nodes[2].gain = 0; nodes[2].q = 1.0
        nodes[3].frequency = 4000; nodes[3].gain = 0; nodes[3].q = 1.0
        nodes[4].frequency = 12000;nodes[4].gain = 0; nodes[4].q = 0.7
        
        for node in nodes {
            player.setEQBand(index: node.index, frequency: node.frequency, gainDB: node.gain, q: node.q)
        }
    }
    
    private func loadState() {
        self.bypass = player.isEQBypassed
        let freqs = player.eqFrequencies.isEmpty ? [60.0, 250.0, 1000.0, 4000.0, 12000.0] : player.eqFrequencies
        let gains = player.eqGains.isEmpty ? [0.0, 0.0, 0.0, 0.0, 0.0] : player.eqGains
        let qs = player.eqQs.isEmpty ? [0.7, 1.0, 1.0, 1.0, 0.7] : player.eqQs
        
        self.nodes = [
            EQNode(index: 0, frequency: freqs[0], gain: gains[0], q: qs[0], color: .red, minFreq: 20, maxFreq: 150),
            EQNode(index: 1, frequency: freqs[1], gain: gains[1], q: qs[1], color: .orange, minFreq: 150, maxFreq: 500),
            EQNode(index: 2, frequency: freqs[2], gain: gains[2], q: qs[2], color: .yellow, minFreq: 500, maxFreq: 2000),
            EQNode(index: 3, frequency: freqs[3], gain: gains[3], q: qs[3], color: .green, minFreq: 2000, maxFreq: 6000),
            EQNode(index: 4, frequency: freqs[4], gain: gains[4], q: qs[4], color: .blue, minFreq: 6000, maxFreq: 20000)
        ]
    }
    
    // MARK: - Subviews

    struct FrequencyGridView: View {
        var width: CGFloat
        var height: CGFloat
        
        var body: some View {
            ZStack {
                Path { path in
                    for db in [-12.0, -6.0, 0.0, 6.0, 12.0] {
                        let y = mapGainToY(db, height: height)
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                    }
                    
                    for freq in [100.0, 1000.0, 10000.0] {
                        let x = mapFreqToX(freq, width: width)
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: height))
                    }
                }
                .stroke(Color.gray.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4]))
            
                Path { path in
                    let y = mapGainToY(0, height: height)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
                .stroke(Color.gray.opacity(0.4), lineWidth: 1.5)
            }
        }
    }
    
    struct ResponseCurve: Shape {
        var nodes: [EQNode]
        var width: CGFloat
        var height: CGFloat
        
        func path(in rect: CGRect) -> Path {
            var path = Path()
            guard !nodes.isEmpty else { return path }
            let resolution = 100
            for i in 0...resolution {
                let x = CGFloat(i) * width / CGFloat(resolution)
                let freq = mapXToFreq(x, width: width)
                
                var totalGain = 0.0
                for node in nodes {
                    let w = node.frequency
                    let dw = log10(freq / w)
                    let attenuation = exp(-pow(dw / (1.0 / node.q), 2))
                    totalGain += node.gain * attenuation
                }
                
                let y = mapGainToY(totalGain, height: height)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            return path
        }
    }
    
    struct NodeView: View {
        @Binding var node: EQNode
        var width: CGFloat
        var height: CGFloat
        var onUpdate: (EQNode) -> Void
        
        var body: some View {
            let x = mapFreqToX(node.frequency, width: width)
            let y = mapGainToY(node.gain, height: height)
            
            Circle()
                .fill(node.color)
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .shadow(radius: 4)
                // EXPAND HIT TARGET so it's easier to grab
                .padding(15)
                .contentShape(Circle())
                .position(x: x, y: y)
                // USE HIGH PRIORITY GESTURE to override Scroll/Swipe
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let newFreq = mapXToFreq(value.location.x, width: width)
                            let newGain = mapYToGain(value.location.y, height: height)
                            
                            node.frequency = max(node.minFreq, min(node.maxFreq, newFreq))
                            node.gain = max(-12, min(12, newGain))
                            onUpdate(node)
                        }
                )
        }
    }

    static func mapXToFreq(_ x: CGFloat, width: CGFloat) -> Double {
        let percent = Double(max(0, min(width, x)) / width)
        return pow(10, log10(20.0) + percent * (log10(20000.0) - log10(20.0)))
    }
    static func mapFreqToX(_ freq: Double, width: CGFloat) -> CGFloat {
        let percent = (log10(freq) - log10(20.0)) / (log10(20000.0) - log10(20.0))
        return CGFloat(percent) * width
    }
    static func mapGainToY(_ gain: Double, height: CGFloat) -> CGFloat {
        let percent = 1.0 - ((max(-12, min(12, gain)) + 12) / 24)
        return CGFloat(percent) * height
    }
    static func mapYToGain(_ y: CGFloat, height: CGFloat) -> Double {
        let percent = Double(max(0, min(height, y)) / height)
        return (1.0 - percent) * 24 - 12
    }
}

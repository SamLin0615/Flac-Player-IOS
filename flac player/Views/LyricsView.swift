import SwiftUI

struct LyricsView: View {
    let song: Song?

    var body: some View {
        NavigationView {
            ScrollView {
                if let lyrics = song?.lyrics, !lyrics.isEmpty {
                    Text(lyrics)
                        .padding()
                        .font(.body)
                        .multilineTextAlignment(.center)
                } else {
                    Text("No lyrics available.")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Lyrics")
        }
    }
}

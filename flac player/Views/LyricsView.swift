import SwiftUI

struct LyricsView: View {
    @Environment(\.dismiss) private var dismiss
    let song: Song

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(song.lyrics ?? "No lyrics available.")
                    .font(.title3).lineSpacing(8).frame(maxWidth: .infinity, alignment: .leading).padding(24)
                    .textSelection(.enabled)
            }
            .navigationTitle("Lyrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

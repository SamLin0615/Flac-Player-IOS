import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var library: MusicLibrary
    @StateObject private var player = FLACPlayer()
    @State private var showFileImporter = false
    @State private var showSearch = false
    @State private var playerOffsetY: CGFloat = ScreenBounds.current.height

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationView {
                VStack(spacing: 0) {
                    LibraryView(player: player)
                }
                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle("Library")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Import") { showFileImporter = true }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { showSearch = true }) {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                }
            }
            .navigationViewStyle(.stack)
            .padding(.bottom, 70)

            MiniPlayerView(player: player,
                           playerOffsetY: $playerOffsetY,
                           isPlayerVisible: playerOffsetY < ScreenBounds.current.height * 0.5)

            FullPlayerView(player: player,
                           playerOffsetY: $playerOffsetY,
                           dismiss: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    playerOffsetY = ScreenBounds.current.height
                }
            })
            .offset(y: playerOffsetY)
            .allowsHitTesting(playerOffsetY < ScreenBounds.current.height * 0.5)
            .ignoresSafeArea()
        }
        .onAppear { playerOffsetY = ScreenBounds.current.height }
        .sheet(isPresented: $showSearch) { SearchView(library: library, player: player) }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [UTType(filenameExtension: "flac")!]) { result in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let src = try result.get()
                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    var dest = docs.appendingPathComponent(src.lastPathComponent)
                    var i = 1
                    while FileManager.default.fileExists(atPath: dest.path) {
                        dest = docs.appendingPathComponent("\(i)_\(src.lastPathComponent)")
                        i += 1
                    }
                    if src.startAccessingSecurityScopedResource() {
                        defer { src.stopAccessingSecurityScopedResource() }
                        try FileManager.default.copyItem(at: src, to: dest)
                    } else {
                        try FileManager.default.copyItem(at: src, to: dest)
                    }
                    DispatchQueue.main.async {
                        library.refresh()
                    }
                } catch {
                    print("Import error: \(error)")
                }
            }
        }
    }
}

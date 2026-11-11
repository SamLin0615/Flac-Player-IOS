import SwiftUI
import UIKit

@main
struct flac_playerApp: App {
    @StateObject private var library = MusicLibrary()
    @StateObject private var player = FLACPlayer()
    @StateObject private var presets = EQPresetManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(presets)
                .onAppear { library.refresh() }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    library.refresh()
                }
        }
    }
}

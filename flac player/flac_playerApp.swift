import SwiftUI

@main
struct flac_playerApp: App {
    @StateObject var library = MusicLibrary()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .onAppear {
                    library.refresh()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    // Refresh when coming back to foreground (e.g., after iTunes file transfer)
                    library.refresh()
                }
        }
    }
}

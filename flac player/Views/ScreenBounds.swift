import SwiftUI

struct ScreenBounds {
    static var current: CGRect {
        // Find the active window scene safely
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first { $0 is UIWindowScene } as? UIWindowScene
        
        if let bounds = windowScene?.screen.bounds, bounds.height > 0 {
            return bounds
        }
        
        // Warning-free fallback for the split second before the window initializes
        // (Prevents the 0-height freeze trap)
        return CGRect(x: 0, y: 0, width: 400, height: 900)
    }
}

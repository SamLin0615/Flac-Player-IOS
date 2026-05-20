import SwiftUI
import MediaPlayer

struct VolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsVolumeSlider = true
        view.tintColor = .systemGray
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) { }
}

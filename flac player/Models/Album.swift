import Foundation
import UIKit

struct Album: Identifiable {
    struct ID: Hashable {
        let artist: String
        let title: String
    }
    let id: ID
    let title: String
    let artist: String
    let year: Int?
    let artwork: UIImage?
    let songs: [Song]
}

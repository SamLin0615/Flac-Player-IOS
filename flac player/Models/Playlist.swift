import Foundation

struct Playlist: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var songIDs: [UUID]

    init(id: UUID = UUID(), name: String, songIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.songIDs = songIDs
    }
}

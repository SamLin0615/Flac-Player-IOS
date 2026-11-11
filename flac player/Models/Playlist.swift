import Foundation

struct Playlist: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var songIDs: [String]
    let createdAt: Date

    init(id: UUID = UUID(), name: String, songIDs: [String] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.songIDs = songIDs
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey { case id, name, songIDs, createdAt }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        songIDs = try container.decode([String].self, forKey: .songIDs)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
    }
}

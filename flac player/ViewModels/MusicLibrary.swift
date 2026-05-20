import Foundation
import Combine

class MusicLibrary: ObservableObject {
    @Published var songs: [Song] = []
    @Published var playlists: [Playlist] = []
    @Published var newTracksAdded: Int = 0

    private var previousCount: Int = 0
    private let playlistsURL: URL
    private let cacheURL: URL
    private var amplitudeCache: [String: [Float]] = [:]
    private let amplitudeQueue = DispatchQueue(label: "amplitude", qos: .utility)
    
    var artists: [String] {
        Array(Set(songs.map { $0.artist })).sorted()
    }

    var albums: [(key: String, songs: [Song])] {
        Dictionary(grouping: songs) { $0.album }
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value.sorted {
                ($0.discNumber ?? 0, $0.trackNumber ?? 0) < ($1.discNumber ?? 0, $1.trackNumber ?? 0)
            }) }
    }

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        playlistsURL = docs.appendingPathComponent("playlists.json")
        cacheURL = docs.appendingPathComponent("amplitudeCache.json")
        loadPlaylists()
        loadCache()
    }

    // MARK: - Refresh song list
    func refresh() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard let enumerator = FileManager.default.enumerator(at: docs, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
            var found: [Song] = []
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension.lowercased() == "flac",
                   let song = Song(url: fileURL) {
                    var s = song
                    s.amplitudeData = self.amplitudeCache[fileURL.path] ?? []
                    found.append(s)
                }
            }
            let sorted = found.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
            DispatchQueue.main.async {
                self.objectWillChange.send()
                self.songs = sorted
                // compute missing amplitudes on the background queue again
                for song in sorted where self.amplitudeCache[song.url.path] == nil {
                    self.computeAndCacheAmplitude(for: song)
                }
            }
        }
    }

    private func loadCache() {
        if let data = try? Data(contentsOf: cacheURL),
           let dict = try? JSONDecoder().decode([String: [Float]].self, from: data) {
            amplitudeCache = dict
        }
    }

    private func saveCache() {
        if let data = try? JSONEncoder().encode(amplitudeCache) {
            try? data.write(to: cacheURL)
        }
    }

    private func computeAndCacheAmplitude(for song: Song) {
        let key = song.url.path
        guard amplitudeCache[key] == nil else { return }
        amplitudeQueue.async { [weak self] in
            guard let self = self else { return }
            let data = AmplitudeEngine.compute(for: song.url)
            DispatchQueue.main.async {
                self.amplitudeCache[key] = data
                self.saveCache()
                // update the song in the published array
                if let idx = self.songs.firstIndex(where: { $0.url.path == key }) {
                    var updated = self.songs[idx]
                    updated.amplitudeData = data
                    self.songs[idx] = updated
                }
            }
        }
    }

    // MARK: - Playlists
    func loadPlaylists() {
        if let data = try? Data(contentsOf: playlistsURL),
           let decoded = try? JSONDecoder().decode([Playlist].self, from: data) {
            playlists = decoded
        }
    }

    func savePlaylists() {
        if let data = try? JSONEncoder().encode(playlists) {
            try? data.write(to: playlistsURL)
        }
    }

    func createPlaylist(name: String) {
        let new = Playlist(name: name)
        playlists.append(new)
        savePlaylists()
    }

    func deletePlaylist(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        savePlaylists()
    }

    func addSong(_ song: Song, to playlist: Playlist) {
        if let idx = playlists.firstIndex(where: { $0.id == playlist.id }) {
            if !playlists[idx].songIDs.contains(song.id) {
                playlists[idx].songIDs.append(song.id)
                savePlaylists()
            }
        }
    }

    func removeSong(_ song: Song, from playlist: Playlist) {
        if let idx = playlists.firstIndex(where: { $0.id == playlist.id }) {
            playlists[idx].songIDs.removeAll { $0 == song.id }
            savePlaylists()
        }
    }

    func songsForPlaylist(_ playlist: Playlist) -> [Song] {
        playlist.songIDs.compactMap { id in songs.first { $0.id == id } }
    }
}

import Foundation
import Combine

class MusicLibrary: ObservableObject {
    @Published var songs: [Song] = [] { didSet { rebuildGroups() } }
    @Published var playlists: [Playlist] = []
    @Published var newTracksAdded = 0
    @Published private(set) var playStats: [String: PlayStats] = [:]
    private(set) var albums: [Album] = []
    private(set) var artists: [String] = []
    private var songsByID: [String: Song] = [:]
    private let playlistsURL: URL
    private let cacheURL: URL
    private let statsURL: URL
    private var amplitudeCache: [String: [Float]] = [:]
    private var pending: Set<String> = []
    private var completedAmplitudes: [String: [Float]] = [:]
    private var cacheSave: DispatchWorkItem?
    private var completedSinceSave = 0
    private let amplitudeQueue = DispatchQueue(label: "amplitude", qos: .utility)

    var recentlyAdded: [Song] { Array(songs.sorted { $0.dateAdded > $1.dateAdded }.prefix(50)) }
    var recentlyPlayed: [Song] {
        Array(songs.filter { playStats[$0.id]?.lastPlayed != nil }.sorted {
            (playStats[$0.id]?.lastPlayed ?? .distantPast) > (playStats[$1.id]?.lastPlayed ?? .distantPast)
        }.prefix(50))
    }
    var mostPlayed: [Song] {
        Array(songs.filter { (playStats[$0.id]?.playCount ?? 0) > 0 }.sorted {
            let left = playStats[$0.id]?.playCount ?? 0
            let right = playStats[$1.id]?.playCount ?? 0
            return left == right ? $0.title < $1.title : left > right
        }.prefix(50))
    }

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        playlistsURL = docs.appendingPathComponent("playlists.json")
        cacheURL = docs.appendingPathComponent("amplitudeCache.v2.json")
        statsURL = docs.appendingPathComponent("playStats.json")
        loadPlaylists()
        if let data = try? Data(contentsOf: cacheURL),
           let decoded = try? JSONDecoder().decode([String: [Float]].self, from: data) { amplitudeCache = decoded }
        if let data = try? Data(contentsOf: statsURL),
           let decoded = try? JSONDecoder().decode([String: PlayStats].self, from: data) { playStats = decoded }
    }

    private func rebuildGroups() {
        songsByID = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        artists = Array(Set(songs.map { $0.albumArtist })).sorted()
        albums = Dictionary(grouping: songs) { Album.ID(artist: $0.albumArtist, title: $0.album) }
            .map { key, tracks in
                let sorted = tracks.sorted {
                    ($0.discNumber ?? 0, $0.trackNumber ?? 0, $0.title) < ($1.discNumber ?? 0, $1.trackNumber ?? 0, $1.title)
                }
                return Album(id: key, title: key.title, artist: key.artist,
                             year: sorted.compactMap { $0.year }.first,
                             artwork: sorted.compactMap { $0.artwork }.first, songs: sorted)
            }.sorted { ($0.artist, $0.title) < ($1.artist, $1.title) }
    }

    func refresh() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let enumerator = FileManager.default.enumerator(at: docs,
                includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return }
            var found: [Song] = []
            for case let url as URL in enumerator {
                if url.pathExtension.lowercased() == "flac",
                   (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                   let song = Song(url: url) { found.append(song) }
            }
            let sorted = found.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
            DispatchQueue.main.async {
                guard let self = self else { return }
                let oldIDs = Set(self.songs.map { $0.id })
                self.newTracksAdded = sorted.filter { !oldIDs.contains($0.id) }.count
                self.songs = sorted.map { song in
                    var updated = song
                    updated.amplitudeData = self.amplitudeCache[song.id] ?? []
                    return updated
                }
                for song in self.songs where self.amplitudeCache[song.id] == nil { self.computeAndCacheAmplitude(for: song) }
            }
        }
    }

    private func saveCache() {
        cacheSave?.cancel()
        completedSinceSave = 0
        let results = completedAmplitudes
        completedAmplitudes.removeAll()
        if !results.isEmpty {
            songs = songs.map { song in
                guard let amplitude = results[song.id] else { return song }
                var updated = song
                updated.amplitudeData = amplitude
                return updated
            }
        }
        if let data = try? JSONEncoder().encode(amplitudeCache) { try? data.write(to: cacheURL, options: .atomic) }
    }

    private func computeAndCacheAmplitude(for song: Song) {
        guard amplitudeCache[song.id] == nil, pending.insert(song.id).inserted else { return }
        amplitudeQueue.async { [weak self] in
            let data = AmplitudeEngine.compute(for: song.url)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.pending.remove(song.id)
                guard !data.isEmpty else { return }
                self.amplitudeCache[song.id] = data
                self.completedAmplitudes[song.id] = data
                self.completedSinceSave += 1
                self.cacheSave?.cancel()
                if self.completedSinceSave >= 20 { self.saveCache() }
                else {
                    let work = DispatchWorkItem { [weak self] in self?.saveCache() }
                    self.cacheSave = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
                }
            }
        }
    }

    func loadPlaylists() {
        if let data = try? Data(contentsOf: playlistsURL),
           let decoded = try? JSONDecoder().decode([Playlist].self, from: data) { playlists = decoded }
    }

    func savePlaylists() {
        if let data = try? JSONEncoder().encode(playlists) { try? data.write(to: playlistsURL, options: .atomic) }
    }

    @discardableResult
    func createPlaylist(name: String) -> Playlist {
        let playlist = Playlist(name: name)
        playlists.append(playlist)
        savePlaylists()
        return playlist
    }

    func renamePlaylist(_ playlist: Playlist, name: String) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[index].name = name
        savePlaylists()
    }

    func deletePlaylist(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        savePlaylists()
    }

    func addSongs(_ songs: [Song], to playlist: Playlist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        var existing = Set(playlists[index].songIDs)
        for song in songs where existing.insert(song.id).inserted { playlists[index].songIDs.append(song.id) }
        savePlaylists()
    }

    func removeSongs(at offsets: IndexSet, from playlist: Playlist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        for offset in offsets.sorted(by: >) where playlists[index].songIDs.indices.contains(offset) {
            playlists[index].songIDs.remove(at: offset)
        }
        savePlaylists()
    }

    func moveSongs(from offsets: IndexSet, to destination: Int, in playlist: Playlist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        var ids = playlists[index].songIDs
        let valid = offsets.filter { ids.indices.contains($0) }
        let moving = valid.map { ids[$0] }
        let target = min(max(destination, 0), ids.count)
        for offset in valid.reversed() { ids.remove(at: offset) }
        ids.insert(contentsOf: moving, at: target - valid.filter { $0 < target }.count)
        playlists[index].songIDs = ids
        savePlaylists()
    }

    func songsForPlaylist(_ playlist: Playlist) -> [Song] {
        let current = playlists.first { $0.id == playlist.id } ?? playlist
        return current.songIDs.compactMap { songsByID[$0] }
    }

    func recordPlay(_ song: Song) {
        var stats = playStats[song.id] ?? PlayStats()
        stats.playCount += 1
        stats.lastPlayed = Date()
        playStats[song.id] = stats
        if let data = try? JSONEncoder().encode(playStats) { try? data.write(to: statsURL, options: .atomic) }
    }
}

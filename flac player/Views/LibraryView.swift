import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var player: FLACPlayer
    @AppStorage("LibrarySongSort") private var sortOrder = "Title"
    @State private var filter: LibraryFilter = .songs
    @State private var importing = false
    @State private var importError: String?
    @State private var showingImportError = false

    private enum LibraryFilter: String, CaseIterable {
        case songs = "Songs", albums = "Albums", artists = "Artists"
    }

    private var sortedSongs: [Song] {
        library.songs.sorted { left, right in
            switch sortOrder {
            case "Artist": return (left.artist, left.album, left.title, left.id) < (right.artist, right.album, right.title, right.id)
            case "Album": return (left.album, left.albumArtist, left.discNumber ?? 0, left.trackNumber ?? 0, left.title) < (right.album, right.albumArtist, right.discNumber ?? 0, right.trackNumber ?? 0, right.title)
            case "Date Added": return left.dateAdded == right.dateAdded ? left.id < right.id : left.dateAdded > right.dateAdded
            default: return (left.title, left.artist, left.id) < (right.title, right.artist, right.id)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Library", selection: $filter) {
                ForEach(LibraryFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).padding()
            if library.songs.isEmpty {
                ContentUnavailableView {
                    Label("Your Music, Lossless", systemImage: "music.note")
                } description: {
                    Text("Import FLAC files here, copy them into this app’s folder in Files, or use Finder file sharing from your Mac.")
                } actions: {
                    Button("Import Music", systemImage: "square.and.arrow.down") { importing = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                switch filter {
                case .songs: songsList
                case .albums:
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 16)], spacing: 24) {
                            ForEach(library.albums) { album in
                                NavigationLink { AlbumDetailView(album: album) } label: { AlbumCard(album: album) }
                                    .buttonStyle(.plain).collectionActions(album.songs)
                            }
                        }.padding()
                    }
                case .artists:
                    List(library.artists, id: \.self) { artist in
                        NavigationLink { ArtistDetailView(artist: artist) } label: {
                            Label(artist, systemImage: "person.crop.circle").frame(minHeight: 44)
                        }
                    }.listStyle(.plain)
                }
            }
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Import", systemImage: "square.and.arrow.down") { importing = true }
            }
            if filter == .songs {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Sort Songs", selection: $sortOrder) {
                            ForEach(["Title", "Artist", "Album", "Date Added"], id: \.self) { Text($0).tag($0) }
                        }
                    } label: { Label("Sort Songs", systemImage: "arrow.up.arrow.down") }
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "flac") ?? .audio], allowsMultipleSelection: true) { result in
            importFiles(result)
        }
        .alert("Import Failed", isPresented: $showingImportError) {
            Button("OK", role: .cancel) {}
        } message: { Text(importError ?? "The selected files could not be imported.") }
    }

    private var songsList: some View {
        let songs = sortedSongs
        return List {
            HStack {
                Button { player.play(songs: songs, shuffle: true) } label: { Label("Shuffle All", systemImage: "shuffle").frame(maxWidth: .infinity, minHeight: 44) }
                Button { player.play(songs: songs) } label: { Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 44) }
            }.buttonStyle(.bordered).listRowSeparator(.hidden)
            ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                Button { player.play(songs: songs, startAt: index) } label: { SongRow(song: song) }
                    .buttonStyle(.plain).songActions(song)
            }
        }.listStyle(.plain)
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        DispatchQueue.global(qos: .userInitiated).async {
            var errors: [String] = []
            do {
                let sources = try result.get()
                let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                for source in sources {
                    let access = source.startAccessingSecurityScopedResource()
                    defer { if access { source.stopAccessingSecurityScopedResource() } }
                    do {
                        var destination = documents.appendingPathComponent(source.lastPathComponent)
                        var suffix = 1
                        while FileManager.default.fileExists(atPath: destination.path) {
                            destination = documents.appendingPathComponent("\(suffix)_\(source.lastPathComponent)")
                            suffix += 1
                        }
                        try FileManager.default.copyItem(at: source, to: destination)
                    } catch { errors.append("\(source.lastPathComponent): \(error.localizedDescription)") }
                }
            } catch { errors.append(error.localizedDescription) }
            DispatchQueue.main.async {
                library.refresh()
                if !errors.isEmpty { importError = errors.joined(separator: "\n"); showingImportError = true }
            }
        }
    }
}

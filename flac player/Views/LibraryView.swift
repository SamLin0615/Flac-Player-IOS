import SwiftUI

struct LibraryView: View {
    @ObservedObject var player: FLACPlayer
    @EnvironmentObject var library: MusicLibrary
    @State private var selectedFilter: LibraryFilter = .songs

    enum LibraryFilter: String, CaseIterable {
        case songs = "Songs", artists = "Artists", albums = "Albums"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(LibraryFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                List {
                    switch selectedFilter {
                    case .songs:
                        ForEach(library.songs) { song in
                            Button(action: {
                                if let idx = library.songs.firstIndex(of: song) {
                                    player.playQueue(songs: library.songs, startIndex: idx)
                                }
                            }) {
                                SongRow(song: song)
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                        }
                    case .artists:
                        ForEach(library.artists, id: \.self) { artist in
                            NavigationLink(destination: ArtistDetailView(artist: artist, library: library, player: player)) {
                                Text(artist).padding(.vertical, 8)
                            }
                        }
                    case .albums:
                        ForEach(library.albums, id: \.key) { album in
                            NavigationLink(destination: AlbumDetailView(album: album.key, library: library, player: player)) {
                                HStack {
                                    if let art = album.songs.first?.artwork {
                                        Image(uiImage: art)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 50, height: 50)
                                            .cornerRadius(6)
                                            .clipped()
                                    } else {
                                        Image(systemName: "music.note")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 24, height: 24)
                                            .padding(13)
                                            .background(Color.gray.opacity(0.3))
                                            .cornerRadius(6)
                                    }
                                    VStack(alignment: .leading) {
                                        Text(album.key)
                                            .font(.system(.body, design: .rounded).weight(.semibold))
                                            .lineLimit(1)
                                        Text(album.songs.first?.artist ?? "")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
                .listStyle(.plain)  // Moved outside the List content
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(.systemGroupedBackground))
        }
    }
}

// MARK: - Reusable Components
struct AlbumCard: View {
    let name: String
    let artist: String
    let artwork: UIImage?
    var body: some View {
        VStack(alignment: .leading) {
            if let art = artwork {
                Image(uiImage: art).resizable().scaledToFill()
                    .frame(width: 150, height: 150).cornerRadius(8).clipped()
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.2))
                    .frame(width: 150, height: 150)
                    .overlay(Image(systemName: "music.note").foregroundColor(.gray))
            }
            Text(name).font(.headline).lineLimit(1)
            Text(artist).font(.caption).foregroundColor(.secondary).lineLimit(1)
        }
    }
}

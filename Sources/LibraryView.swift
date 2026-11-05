import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var library: LibraryStore
    @State private var section: LibrarySection = .recent
    @State private var showImporter = false
    @State private var showSettings = false

    enum LibrarySection: String, CaseIterable, Identifiable {
        case recent = "Недавние"
        case playlists = "Плейлисты"
        case artists = "Артисты"
        case albums = "Альбомы"
        case songs = "Песни"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Group {
                if library.tracks.isEmpty && !library.isScanning {
                    EmptyLibraryView {
                        showImporter = true
                    }
                } else {
                    VStack(spacing: 0) {
                        Picker("Раздел", selection: $section) {
                            ForEach(LibrarySection.allCases) { s in
                                Text(s.rawValue).tag(s)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)

                        switch section {
                        case .recent: RecentSection()
                        case .playlists: PlaylistsSection()
                        case .artists: ArtistsSection()
                        case .albums: AlbumsSection()
                        case .songs: SongsSection()
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Медиатека")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result, !urls.isEmpty {
                    library.importFiles(urls)
                }
            }
            .overlay(alignment: .top) {
                if library.isScanning {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("Сканирование…")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    .background(Capsule().fill(.thinMaterial))
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }
}

// MARK: - Недавние

struct RecentSection: View {
    @EnvironmentObject var library: LibraryStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20, pinnedViews: []) {
                if !library.recentAlbums.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Недавно добавленное")
                            .font(.title2.weight(.bold))
                            .padding(.horizontal, 16)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 18) {
                            ForEach(Array(library.recentAlbums.prefix(8))) { album in
                                AlbumCard(album: album)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                let recentTracks = library.recentTracks.prefix(15)
                if !recentTracks.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Новые треки")
                            .font(.title2.weight(.bold))
                            .padding(.horizontal, 16)
                            .padding(.bottom, 6)
                        ForEach(Array(recentTracks)) { t in
                            TrackListButton(track: t, context: Array(recentTracks))
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Песни

struct SongsSection: View {
    @EnvironmentObject var library: LibraryStore

    private var sorted: [Track] {
        library.tracks.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
    }

    var body: some View {
        List {
            ForEach(Array(sorted.enumerated()), id: \.element.id) { i, t in
                TrackListButton(track: t, context: sorted, showNumber: nil)
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Альбомы

struct AlbumsSection: View {
    @EnvironmentObject var library: LibraryStore

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 18) {
                ForEach(library.sortedAlbumsAZ) { album in
                    AlbumCard(album: album)
                }
            }
            .padding(16)
        }
    }
}

struct AlbumCard: View {
    let album: Album
    var width: CGFloat?

    var body: some View {
        NavigationLink {
            AlbumDetailView(albumID: album.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ArtworkView(seed: album.id, data: album.artwork)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(width: width, height: width)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
                Text(album.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(album.artist)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Артисты

struct ArtistsSection: View {
    @EnvironmentObject var library: LibraryStore

    var body: some View {
        List {
            ForEach(library.artists) { artist in
                NavigationLink {
                    ArtistDetailView(artistID: artist.id)
                } label: {
                    HStack(spacing: 12) {
                        ArtworkView(seed: artist.id, data: artist.artwork)
                            .frame(width: 46, height: 46)
                            .clipShape(Circle())
                        Text(artist.name)
                            .font(.system(size: 16))
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Плейлисты

struct PlaylistsSection: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: AudioPlayer
    @State private var showNew = false
    @State private var newName = ""

    var body: some View {
        List {
            Button {
                showNew = true
            } label: {
                Label("Новый плейлист", systemImage: "plus")
                    .foregroundColor(.amRed)
                    .font(.system(size: 17))
            }

            ForEach(library.playlists) { pl in
                NavigationLink {
                    PlaylistDetailView(playlistID: pl.id)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(seedGradient(pl.name))
                                .frame(width: 46, height: 46)
                            Image(systemName: "music.note")
                                .foregroundColor(.white)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pl.name).font(.system(size: 16))
                            Text("\(pl.trackIDs.count) песен")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        library.deletePlaylist(pl.id)
                    } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .alert("Новый плейлист", isPresented: $showNew) {
            TextField("Название", text: $newName)
            Button("Создать") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { library.createPlaylist(name: name) }
                newName = ""
            }
            Button("Отмена", role: .cancel) { newName = "" }
        }
    }
}

// MARK: - universal row button

struct TrackListButton: View {
    let track: Track
    let context: [Track]
    var showNumber: Int?
    var showAlbumInfo: Bool = true
    var onDeleteFromPlaylist: (() -> Void)?

    @EnvironmentObject var player: AudioPlayer

    var body: some View {
        Button {
            play()
        } label: {
            SongRow(track: track, number: showNumber, showAlbumInfo: showAlbumInfo)
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .modifier(TrackMenu(track: track, contextTracks: context, onDeleteFromPlaylist: onDeleteFromPlaylist))
    }

    private func play() {
        if let i = context.firstIndex(where: { $0.id == track.id }) {
            player.play(context, startIndex: i)
        } else {
            player.play([track])
        }
    }
}

// MARK: - альбом

struct AlbumDetailView: View {
    let albumID: String
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: AudioPlayer

    private var album: Album? { library.album(id: albumID) }
    private var tracks: [Track] { library.tracks(albumID: albumID) }

    var body: some View {
        Group {
            if let album {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ArtworkView(seed: album.id, data: album.artwork)
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
                            .frame(maxWidth: 280)
                            .frame(maxWidth: .infinity)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(album.title)
                                .font(.system(size: 22, weight: .bold))
                            Text(album.artist)
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundColor(.amRed)
                            let subtitle = [album.genre.isEmpty ? nil : album.genre, album.year > 0 ? String(album.year) : nil]
                                .compactMap { $0 }
                                .joined(separator: " • ")
                            if !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 20)

                        HStack(spacing: 24) {
                            Button {
                                player.play(tracks, context: "АЛЬБОМА «\(album.title.uppercased())»")
                            } label: {
                                Label("Воспроизвести", systemImage: "play.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.amRed)
                            }
                            Button {
                                player.shuffleOn = true
                                player.play(tracks, context: "АЛЬБОМА «\(album.title.uppercased())»")
                            } label: {
                                Label("Перемешать", systemImage: "shuffle")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.amRed)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)

                        Divider().padding(.horizontal, 20)

                        VStack(spacing: 2) {
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { i, t in
                                TrackListButton(track: t, context: tracks, showNumber: i + 1, showAlbumInfo: false)
                            }
                        }

                        let total = tracks.reduce(0.0) { $0 + $1.duration }
                        Text("\(tracks.count) песен, \(fmtTotalTime(total))")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 20)
                    }
                    .padding(.top, 10)
                }
            } else {
                EmptyLibraryView()
            }
        }
        .navigationTitle(album?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - артист

struct ArtistDetailView: View {
    let artistID: String
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: AudioPlayer

    private var artist: Artist? { library.artists.first { $0.id == artistID } }
    private var tracks: [Track] { library.tracks(ids: artist?.trackIDs ?? []) }
    private var albums: [Album] { library.albums(artistID: artistID) }

    var body: some View {
        Group {
            if let artist {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ArtworkView(seed: artist.id, data: artist.artwork)
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                            .frame(maxWidth: 240)
                            .frame(maxWidth: .infinity)

                        Text(artist.name)
                            .font(.system(size: 26, weight: .bold))
                            .frame(maxWidth: .infinity)

                        HStack(spacing: 24) {
                            Button {
                                player.play(tracks, context: "АРТИСТА \(artist.name.uppercased())")
                            } label: {
                                Label("Воспроизвести", systemImage: "play.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.amRed)
                            }
                            Button {
                                player.shuffleOn = true
                                player.play(tracks, context: "АРТИСТА \(artist.name.uppercased())")
                            } label: {
                                Label("Перемешать", systemImage: "shuffle")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.amRed)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        let top = Array(tracks.sorted {
                            if $0.playCount != $1.playCount { return $0.playCount > $1.playCount }
                            return $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
                        }.prefix(8))

                        if !top.isEmpty {
                            Text("Популярные треки")
                                .font(.title3.weight(.bold))
                                .padding(.top, 8)
                            ForEach(top) { t in
                                TrackListButton(track: t, context: top)
                            }
                        }

                        if !albums.isEmpty {
                            Text("Альбомы")
                                .font(.title3.weight(.bold))
                                .padding(.top, 10)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(albums) { a in
                                        AlbumCard(album: a, width: 140)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            } else {
                EmptyLibraryView()
            }
        }
        .navigationTitle(artist?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - плейлист

struct PlaylistDetailView: View {
    let playlistID: UUID
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: AudioPlayer
    @State private var showPicker = false

    private var playlist: Playlist? { library.playlist(id: playlistID) }
    private var tracks: [Track] { library.tracks(ids: playlist?.trackIDs ?? []) }

    var body: some View {
        Group {
            if let pl = playlist {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(seedGradient(pl.name))
                            Image(systemName: "music.note")
                                .font(.system(size: 54))
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: 240)
                        .frame(maxWidth: .infinity)
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)

                        Text(pl.name)
                            .font(.system(size: 24, weight: .bold))
                            .frame(maxWidth: .infinity)

                        HStack(spacing: 24) {
                            Button {
                                player.play(tracks, context: "ПЛЕЙЛИСТА «\(pl.name.uppercased())»")
                            } label: {
                                Label("Воспроизвести", systemImage: "play.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.amRed)
                            }
                            Button {
                                player.shuffleOn = true
                                player.play(tracks, context: "ПЛЕЙЛИСТА «\(pl.name.uppercased())»")
                            } label: {
                                Label("Перемешать", systemImage: "shuffle")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.amRed)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        Divider()

                        if tracks.isEmpty {
                            Text("Пустой плейлист. Добавьте песни кнопкой «+».")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { i, t in
                                TrackListButton(
                                    track: t,
                                    context: tracks,
                                    onDeleteFromPlaylist: { library.removeFromPlaylist(trackID: t.id, playlistID: pl.id) }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showPicker = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                .sheet(isPresented: $showPicker) {
                    SongPickerView { ids in
                        library.addTracksToPlaylist(ids, playlistID: pl.id)
                    }
                }
            }
        }
        .navigationTitle(playlist?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - выбор песен для плейлиста

struct SongPickerView: View {
    var onDone: ([String]) -> Void
    @EnvironmentObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var query = ""

    private var filtered: [Track] {
        let all = library.tracks.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        if query.isEmpty { return all }
        let q = query.lowercased()
        return all.filter {
            $0.displayTitle.lowercased().contains(q) ||
            $0.displayArtist.lowercased().contains(q) ||
            $0.displayAlbum.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { t in
                    Button {
                        if selected.contains(t.id) { selected.remove(t.id) } else { selected.insert(t.id) }
                    } label: {
                        HStack {
                            Image(systemName: selected.contains(t.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selected.contains(t.id) ? .amRed : .secondary)
                            SongRow(track: t, showArtwork: true)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .searchable(text: $query, prompt: "Песни, артисты, альбомы")
            .navigationTitle("Добавить песни")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") {
                        onDone(Array(selected))
                        dismiss()
                    }
                }
            }
        }
    }
}

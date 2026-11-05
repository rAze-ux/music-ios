import SwiftUI

// MARK: - Слушать

struct ListenNowView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: AudioPlayer

    var body: some View {
        NavigationStack {
            ScrollView {
                if library.tracks.isEmpty {
                    VStack(spacing: 10) {
                        Text("Здесь появится то, что вы слушаете")
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                        Text("Добавьте музыку в медиатеку — и подборки соберутся автоматически.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .padding(.top, 120)
                } else {
                    VStack(alignment: .leading, spacing: 26) {
                        section("Топ подборок") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    MixCard(title: "Микс дня", subtitle: "Обновляется каждый день", colors: [Color(red: 0.42, green: 0.36, blue: 0.95), Color(red: 0.78, green: 0.29, blue: 0.96)]) {
                                        player.play(Array(library.tracks.shuffled().prefix(30)), context: "ПОДБОРКИ «МИКС ДНЯ»")
                                    }
                                    MixCard(title: "Любимое", subtitle: "То, что вы слушаете чаще всего", colors: [Color(red: 0.98, green: 0.24, blue: 0.36), Color(red: 0.75, green: 0.1, blue: 0.3)]) {
                                        let top = library.topTracks
                                        player.play(top.isEmpty ? Array(library.tracks.prefix(20)) : top, context: "ПОДБОРКИ «ЛЮБИМОЕ»")
                                    }
                                    MixCard(title: "По-свежему", subtitle: "Новые добавления в медиатеке", colors: [Color(red: 0.05, green: 0.55, blue: 0.98), Color(red: 0.35, green: 0.82, blue: 0.98)]) {
                                        player.play(Array(library.recentTracks.prefix(25)), context: "ПОДБОРКИ «ПО-СВЕЖЕМУ»")
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }

                        if !library.recentAlbums.isEmpty {
                            section("Недавно добавленное") {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 14) {
                                        ForEach(Array(library.recentAlbums.prefix(12))) { album in
                                            AlbumCard(album: album, width: 160)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                        }

                        let top = library.topTracks
                        if !top.isEmpty {
                            section("Часто слушаете") {
                                ForEach(Array(top.prefix(10))) { t in
                                    TrackListButton(track: t, context: Array(top.prefix(10)))
                                        .padding(.horizontal, 16)
                                }
                            }
                        }

                        if !library.artists.isEmpty {
                            section("Артисты в вашей медиатеке") {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 16) {
                                        ForEach(Array(library.artists.prefix(15))) { artist in
                                            NavigationLink {
                                                ArtistDetailView(artistID: artist.id)
                                            } label: {
                                                VStack(spacing: 6) {
                                                    ArtworkView(seed: artist.id, data: artist.artwork)
                                                        .frame(width: 92, height: 92)
                                                        .clipShape(Circle())
                                                        .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
                                                    Text(artist.name)
                                                        .font(.system(size: 12))
                                                        .foregroundColor(.primary)
                                                        .lineLimit(1)
                                                        .frame(width: 96)
                                                }
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 10)
                }
            }
            .navigationTitle("Слушать")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2.weight(.bold))
                .padding(.horizontal, 16)
            content()
        }
    }
}

struct MixCard: View {
    let title: String
    let subtitle: String
    let colors: [Color]
    let onPlay: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                Button(action: onPlay) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 34))
                        .foregroundColor(.white)
                }
                .padding(.top, 8)
            }
            .padding(14)
        }
        .frame(width: 250, height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.18), radius: 5, y: 3)
    }
}

// MARK: - Обзор

struct BrowseView: View {
    @EnvironmentObject var library: LibraryStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if !library.recentAlbums.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Новинки медиатеки")
                                .font(.title2.weight(.bold))
                                .padding(.horizontal, 16)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(Array(library.recentAlbums.prefix(12))) { album in
                                        AlbumCard(album: album, width: 160)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }

                    let genres = library.genreNames()
                    if !genres.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Категории")
                                .font(.title2.weight(.bold))
                                .padding(.horizontal, 16)
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                                ForEach(genres.prefix(16), id: \.self) { g in
                                    NavigationLink {
                                        GenreDetailView(genre: g)
                                    } label: {
                                        ZStack(alignment: .bottomLeading) {
                                            seedGradient(g)
                                            Text(g)
                                                .font(.system(size: 19, weight: .bold))
                                                .foregroundColor(.white)
                                                .padding(10)
                                        }
                                        .frame(height: 92)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    if library.tracks.isEmpty {
                        Text("Добавьте музыку — категории появятся из жанров ваших файлов.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 24)
                            .padding(.top, 60)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 10)
            }
            .navigationTitle("Обзор")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct GenreDetailView: View {
    let genre: String
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: AudioPlayer

    private var tracks: [Track] { library.tracks(genre: genre) }

    var body: some View {
        List {
            ForEach(tracks) { t in
                TrackListButton(track: t, context: tracks)
            }
        }
        .listStyle(.plain)
        .navigationTitle(genre)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    player.shuffleOn = true
                    player.play(tracks, context: "КАТЕГОРИИ «\(genre.uppercased())»")
                } label: {
                    Image(systemName: "shuffle")
                }
            }
        }
    }
}

// MARK: - Радио

struct RadioView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: AudioPlayer

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if library.tracks.isEmpty {
                        Text("Станции соберутся из вашей медиатеки, когда вы добавите музыку.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.top, 120)
                    } else {
                        StationCard(
                            title: "Микс дня",
                            subtitle: "Случайная подборка из всей медиатеки",
                            colors: [Color(red: 0.42, green: 0.36, blue: 0.95), Color(red: 0.85, green: 0.2, blue: 0.55)]
                        ) {
                            player.play(Array(library.tracks.shuffled().prefix(40)), context: "СТАНЦИИ «МИКС ДНЯ»")
                        }
                        StationCard(
                            title: "Хиты медиатеки",
                            subtitle: "Ваши самые прослушиваемые песни",
                            colors: [Color(red: 0.98, green: 0.24, blue: 0.36), Color(red: 0.6, green: 0.05, blue: 0.3)]
                        ) {
                            let top = library.topTracks
                            player.play(top.isEmpty ? Array(library.tracks.shuffled().prefix(30)) : top, context: "СТАНЦИИ «ХИТЫ МЕДИАТЕКИ»")
                        }
                        StationCard(
                            title: "Спокойная волна",
                            subtitle: "Фоновая подборка на каждый день",
                            colors: [Color(red: 0.1, green: 0.55, blue: 0.6), Color(red: 0.15, green: 0.3, blue: 0.55)]
                        ) {
                            player.play(Array(library.tracks.shuffled().prefix(25)), context: "СТАНЦИИ «СПОКОЙНАЯ ВОЛНА»")
                        }
                        StationCard(
                            title: "По-свежему",
                            subtitle: "Только новые добавления",
                            colors: [Color(red: 0.95, green: 0.5, blue: 0.1), Color(red: 0.95, green: 0.25, blue: 0.4)]
                        ) {
                            player.play(Array(library.recentTracks.prefix(30)), context: "СТАНЦИИ «ПО-СВЕЖЕМУ»")
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Радио")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct StationCard: View {
    let title: String
    let subtitle: String
    let colors: [Color]
    let onPlay: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                }
                Spacer()
                Button(action: onPlay) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                }
            }
            .padding(16)
        }
        .frame(height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
    }
}

// MARK: - Поиск

struct SearchView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: AudioPlayer
    @State private var query = ""

    private var filteredTracks: [Track] {
        let q = query.lowercased()
        return library.tracks.filter {
            $0.displayTitle.lowercased().contains(q) ||
            $0.displayArtist.lowercased().contains(q) ||
            $0.displayAlbum.lowercased().contains(q)
        }
    }

    private var filteredAlbums: [Album] {
        let q = query.lowercased()
        return library.albums.filter {
            $0.title.lowercased().contains(q) || $0.artist.lowercased().contains(q)
        }
    }

    private var filteredArtists: [Artist] {
        library.artists.filter { $0.name.lowercased().contains(query.lowercased()) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if query.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Недавно добавленное")
                                .font(.title3.weight(.bold))
                                .padding(.horizontal, 16)
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 18) {
                                ForEach(Array(library.recentAlbums.prefix(6))) { album in
                                    AlbumCard(album: album)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.top, 10)
                    }
                } else {
                    List {
                        if !filteredTracks.isEmpty {
                            Section("Песни") {
                                ForEach(Array(filteredTracks.prefix(20))) { t in
                                    TrackListButton(track: t, context: filteredTracks)
                                }
                            }
                        }
                        if !filteredAlbums.isEmpty {
                            Section("Альбомы") {
                                ForEach(filteredAlbums.prefix(10)) { a in
                                    NavigationLink {
                                        AlbumDetailView(albumID: a.id)
                                    } label: {
                                        HStack(spacing: 12) {
                                            ArtworkView(seed: a.id, data: a.artwork)
                                                .frame(width: 46, height: 46)
                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(a.title).font(.system(size: 16))
                                                Text("Альбом • \(a.artist)")
                                                    .font(.system(size: 13))
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        if !filteredArtists.isEmpty {
                            Section("Артисты") {
                                ForEach(filteredArtists) { a in
                                    NavigationLink {
                                        ArtistDetailView(artistID: a.id)
                                    } label: {
                                        HStack(spacing: 12) {
                                            ArtworkView(seed: a.id, data: a.artwork)
                                                .frame(width: 46, height: 46)
                                                .clipShape(Circle())
                                            Text(a.name).font(.system(size: 16))
                                        }
                                    }
                                }
                            }
                        }
                        if filteredTracks.isEmpty && filteredAlbums.isEmpty && filteredArtists.isEmpty {
                            Text("Нет результатов")
                                .foregroundColor(.secondary)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Поиск")
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Артисты, песни, альбомы"
            )
        }
    }
}

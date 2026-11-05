import Foundation
import Combine

final class LibraryStore: ObservableObject {

    @Published private(set) var tracks: [Track] = []
    @Published private(set) var albums: [Album] = []
    @Published private(set) var artists: [Artist] = []
    @Published private(set) var playlists: [Playlist] = []
    @Published var isScanning = false
    @Published var lastScanDate: Date?

    let musicFolder: URL

    static let audioExtensions = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "caf"]

    private var byID: [String: Track] = [:]
    private var albumByID: [String: Album] = [:]
    private var signatures: [String: String] = [:]
    private let cacheFile: URL
    private let playlistsFile: URL

    // MARK: - init

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        musicFolder = docs.appendingPathComponent("Музыка", isDirectory: true)
        cacheFile = docs.appendingPathComponent("library_cache.json")
        playlistsFile = docs.appendingPathComponent("playlists.json")
        try? FileManager.default.createDirectory(at: musicFolder, withIntermediateDirectories: true)
        loadCache()
        loadPlaylists()
        NotificationCenter.default.addObserver(
            forName: .amResetPlayStats, object: nil, queue: .main
        ) { [weak self] _ in
            self?.resetPlayStats()
        }
    }

    // MARK: - lookup helpers

    func track(id: String) -> Track? { byID[id] }
    func album(id: String) -> Album? { albumByID[id] }
    func tracks(ids: [String]) -> [Track] { ids.compactMap { byID[$0] } }

    var recentTracks: [Track] { tracks.sorted { $0.addedAt > $1.addedAt } }
    var recentAlbums: [Album] { albums.sorted { $0.addedAt > $1.addedAt } }
    var topTracks: [Track] { tracks.filter { $0.playCount > 0 }.sorted { $0.playCount > $1.playCount } }
    var sortedAlbumsAZ: [Album] { albums.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending } }

    func albums(artistID: String) -> [Album] {
        albums.filter { $0.id.hasPrefix(artistID + "|") }.sorted { $0.year < $1.year }
    }

    func tracks(albumID: String) -> [Track] {
        guard let a = albumByID[albumID] else { return [] }
        return tracks(ids: a.trackIDs)
    }

    func genreNames() -> [String] {
        var counts: [String: Int] = [:]
        for t in tracks where !t.genre.isEmpty { counts[t.genre, default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }.map { $0.key }
    }

    func tracks(genre: String) -> [Track] {
        tracks.filter { $0.genre == genre }
    }

    // MARK: - scanning

    func rescan() {
        guard !isScanning else { return }
        isScanning = true
        let folder = musicFolder
        let oldTracks = tracks
        let oldSignatures = signatures

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var found: [(url: URL, rel: String, sig: String)] = []
            if let enumerator = FileManager.default.enumerator(
                at: folder,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
            ) {
                for case let url as URL in enumerator {
                    let ext = url.pathExtension.lowercased()
                    guard Self.audioExtensions.contains(ext) else { continue }
                    let vals = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                    let size = vals?.fileSize ?? 0
                    let mtime = vals?.contentModificationDate?.timeIntervalSince1970 ?? 0
                    let rel = String(url.path.dropFirst(folder.path.count + 1))
                    found.append((url, rel, "\(size)-\(mtime)"))
                }
            }

            var oldDict: [String: Track] = [:]
            for t in oldTracks { oldDict[t.relativePath] = t }

            var newTracks: [Track] = []
            newTracks.reserveCapacity(found.count)
            var newSigs: [String: String] = [:]

            for f in found {
                newSigs[f.rel] = f.sig
                if let old = oldDict[f.rel], oldSignatures[f.rel] == f.sig {
                    newTracks.append(old)
                    continue
                }
                let meta = MetadataReader.parse(url: f.url)
                let track = Track(
                    relativePath: f.rel,
                    fileName: f.url.lastPathComponent,
                    title: meta.title,
                    artist: meta.artist,
                    albumArtist: meta.albumArtist,
                    album: meta.album,
                    genre: meta.genre,
                    year: meta.year,
                    trackNumber: meta.track,
                    discNumber: meta.disc,
                    duration: meta.duration,
                    artwork: meta.artwork,
                    addedAt: oldDict[f.rel]?.addedAt ?? Date(),
                    playCount: oldDict[f.rel]?.playCount ?? 0,
                    lyrics: meta.lyrics,
                    bpm: nil
                )
                newTracks.append(track)
            }

            DispatchQueue.main.async {
                self.tracks = newTracks
                self.signatures = newSigs
                self.rebuildIndexes()
                self.saveCache()
                self.isScanning = false
                self.lastScanDate = Date()
            }
        }
    }

    func rebuildIndexes() {
        var map: [String: Track] = [:]
        for t in tracks { map[t.relativePath] = t }
        byID = map

        // Альбомы: группировка по исполнителю альбома + названию
        var albumGroups: [String: [Track]] = [:]
        for t in tracks {
            let key = "\(t.artistKey)|\(t.displayAlbum.lowercased())"
            albumGroups[key, default: []].append(t)
        }
        var newAlbums: [Album] = []
        var newAlbumMap: [String: Album] = [:]
        for (key, group) in albumGroups {
            let sorted = group.sorted {
                if $0.discNumber != $1.discNumber { return $0.discNumber < $1.discNumber }
                if $0.trackNumber != $1.trackNumber { return $0.trackNumber < $1.trackNumber }
                return $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
            }
            let first = sorted[0]
            let album = Album(
                id: key,
                title: first.displayAlbum,
                artist: first.displayArtist,
                year: first.year,
                genre: first.genre,
                trackIDs: sorted.map { $0.id },
                artwork: sorted.first(where: { $0.artwork != nil })?.artwork,
                addedAt: sorted.map { $0.addedAt }.min() ?? Date()
            )
            newAlbums.append(album)
            newAlbumMap[key] = album
        }
        albums = newAlbums
        albumByID = newAlbumMap

        // Артисты
        var artistGroups: [String: [Track]] = [:]
        for t in tracks { artistGroups[t.artistKey, default: []].append(t) }
        var newArtists: [Artist] = []
        for (key, group) in artistGroups {
            let albumKeys = Set(group.map { "\($0.artistKey)|\($0.displayAlbum.lowercased())" })
            let artist = Artist(
                id: key,
                name: group[0].displayArtist,
                albumIDs: Array(albumKeys),
                trackIDs: group.map { $0.id },
                artwork: group.first(where: { $0.artwork != nil })?.artwork
            )
            newArtists.append(artist)
        }
        artists = newArtists.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func registerPlay(id: String) {
        guard var t = byID[id] else { return }
        t.playCount += 1
        byID[id] = t
        if let i = tracks.firstIndex(where: { $0.id == id }) {
            tracks[i] = t
        }
        if let ai = albums.firstIndex(where: { $0.trackIDs.contains(id) }),
           albums[ai].artwork == nil, t.artwork != nil {
            albums[ai].artwork = t.artwork
        }
        saveCache()
    }

    func setBPM(id: String, bpm: Double) {
        guard var t = byID[id] else { return }
        t.bpm = bpm
        byID[id] = t
        if let i = tracks.firstIndex(where: { $0.id == id }) {
            tracks[i] = t
        }
        saveCache()
    }

    /// Автомикс: ищем похожий трек — сначала по темпу (BPM ±6%), затем по жанру, чуть добавляем популярность.
    func similarTracks(to track: Track) -> [Track] {
        var scored: [(Track, Double)] = []
        for t in tracks where t.id != track.id {
            var score = Double(t.playCount) * 0.05
            if let b1 = track.bpm, let b2 = t.bpm, b1 > 0 {
                let diff = abs(b1 - b2) / b1
                if diff <= 0.06 {
                    score += 3
                } else if diff <= 0.12 {
                    score += 1
                }
            }
            if !track.genre.isEmpty, t.genre == track.genre {
                score += 1.5
            }
            scored.append((t, score))
        }
        guard !scored.isEmpty else { return [] }
        let top = scored.sorted { $0.1 > $1.1 }.prefix(6)
        return top.map { $0.0 }.shuffled()
    }

    func resetPlayStats() {
        var updated = tracks
        for i in updated.indices { updated[i].playCount = 0 }
        tracks = updated
        rebuildIndexes()
        saveCache()
    }

    // MARK: - import

    func importFiles(_ urls: [URL]) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            for src in urls {
                let scoped = src.startAccessingSecurityScopedResource()
                defer { if scoped { src.stopAccessingSecurityScopedResource() } }
                let base = (src.lastPathComponent as NSString).deletingPathExtension
                let ext = (src.lastPathComponent as NSString).pathExtension
                var dest = self.musicFolder.appendingPathComponent(src.lastPathComponent)
                var counter = 1
                while FileManager.default.fileExists(atPath: dest.path) {
                    dest = self.musicFolder.appendingPathComponent("\(base) (\(counter)).\(ext)")
                    counter += 1
                }
                try? FileManager.default.copyItem(at: src, to: dest)
            }
            DispatchQueue.main.async { self.rescan() }
        }
    }

    // MARK: - playlists

    func createPlaylist(name: String) {
        let pl = Playlist(id: UUID(), name: name, trackIDs: [], createdAt: Date())
        playlists.append(pl)
        savePlaylists()
    }

    func addToPlaylist(trackID: String, playlistID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[i].trackIDs.append(trackID)
        savePlaylists()
    }

    func addTracksToPlaylist(_ ids: [String], playlistID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[i].trackIDs.append(contentsOf: ids)
        savePlaylists()
    }

    func removeFromPlaylist(trackID: String, playlistID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[i].trackIDs.removeAll { $0 == trackID }
        savePlaylists()
    }

    func deletePlaylist(_ id: UUID) {
        playlists.removeAll { $0.id == id }
        savePlaylists()
    }

    func playlist(id: UUID) -> Playlist? { playlists.first { $0.id == id } }

    // MARK: - persistence

    private func saveCache() {
        let cache = LibraryCache(tracks: tracks, signatures: signatures, lastScan: lastScanDate)
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheFile, options: .atomic)
        }
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheFile),
              let cache = try? JSONDecoder().decode(LibraryCache.self, from: data) else { return }
        tracks = cache.tracks
        signatures = cache.signatures
        lastScanDate = cache.lastScan
        rebuildIndexes()
    }

    private func savePlaylists() {
        if let data = try? JSONEncoder().encode(playlists) {
            try? data.write(to: playlistsFile, options: .atomic)
        }
    }

    private func loadPlaylists() {
        guard let data = try? Data(contentsOf: playlistsFile),
              let pls = try? JSONDecoder().decode([Playlist].self, from: data) else { return }
        playlists = pls
    }
}

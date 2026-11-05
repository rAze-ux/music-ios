import Foundation

struct Track: Identifiable, Codable, Hashable {
    var relativePath: String
    var fileName: String
    var title: String
    var artist: String
    var albumArtist: String
    var album: String
    var genre: String
    var year: Int
    var trackNumber: Int
    var discNumber: Int
    var duration: TimeInterval
    var artwork: Data?
    var addedAt: Date
    var playCount: Int
    var lyrics: String?
    var bpm: Double?

    var id: String { relativePath }

    var displayTitle: String {
        if !title.isEmpty { return title }
        return (fileName as NSString).deletingPathExtension
    }
    var displayArtist: String { artist.isEmpty ? "Неизвестный исполнитель" : artist }
    var displayAlbum: String { album.isEmpty ? "Неизвестный альбом" : album }
    var artistKey: String { (albumArtist.isEmpty ? artist : albumArtist).lowercased() }
}

struct Album: Identifiable, Hashable {
    var id: String
    var title: String
    var artist: String
    var year: Int
    var genre: String
    var trackIDs: [String]
    var artwork: Data?
    var addedAt: Date
}

struct Artist: Identifiable, Hashable {
    var id: String
    var name: String
    var albumIDs: [String]
    var trackIDs: [String]
    var artwork: Data?
}

struct Playlist: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var trackIDs: [String]
    var createdAt: Date
}

struct LibraryCache: Codable {
    var tracks: [Track]
    var signatures: [String: String]
    var lastScan: Date?
}

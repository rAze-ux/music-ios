import Foundation
import AVFoundation

struct ParsedMeta {
    var title = ""
    var artist = ""
    var albumArtist = ""
    var album = ""
    var genre = ""
    var year = 0
    var track = 0
    var disc = 0
    var duration: TimeInterval = 0
    var artwork: Data?
    var lyrics: String?
}

enum MetadataReader {

    static func parse(url: URL) -> ParsedMeta {
        var meta = ParsedMeta()
        let asset = AVURLAsset(url: url)
        meta.duration = CMTimeGetSeconds(asset.duration)
        if meta.duration.isNaN || meta.duration.isInfinite { meta.duration = 0 }

        let items = asset.commonMetadata

        func text(_ id: AVMetadataIdentifier) -> String {
            AVMetadataItem.metadataItems(from: items, filteredByIdentifier: id).first?.stringValue ?? ""
        }
        func number(_ ids: [AVMetadataIdentifier]) -> Int {
            for id in ids {
                if let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: id).first {
                    if let n = item.numberValue?.intValue, n > 0 { return n }
                    if let s = item.stringValue {
                        let digits = s.prefix { $0.isNumber }
                        if let n = Int(digits), n > 0 { return n }
                    }
                }
            }
            return 0
        }

        meta.title = text(.commonIdentifierTitle)
        meta.artist = text(.commonIdentifierArtist)
        meta.album = text(.commonIdentifierAlbumName)
        // жанр берём через common-ключ ("genre"), у commonIdentifierGenre нет Swift-члена
        for item in items where item.commonKey?.rawValue == "genre" {
            meta.genre = item.stringValue ?? ""
            break
        }
        meta.albumArtist = text(.iTunesMetadataAlbumArtist)
        let dateStr = text(.commonIdentifierCreationDate)
        meta.year = Int(dateStr.prefix { $0.isNumber }) ?? 0
        meta.track = number([.iTunesMetadataTrackNumber, .id3MetadataTrackNumber])
        meta.disc = number([.iTunesMetadataDiscNumber, .id3MetadataPartOfASet])
        meta.artwork = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .commonIdentifierArtwork).first?.dataValue
        if meta.artwork == nil {
            for item in items where item.commonKey?.rawValue == "artwork" {
                meta.artwork = item.dataValue
                break
            }
        }
        for item in items where item.commonKey?.rawValue == "lyrics" {
            meta.lyrics = item.stringValue
            break
        }

        let ext = url.pathExtension.lowercased()
        if ext == "mp3" {
            let id3 = ID3Parser.parse(url: url)
            if meta.title.isEmpty { meta.title = id3.title }
            if meta.artist.isEmpty { meta.artist = id3.artist }
            if meta.album.isEmpty { meta.album = id3.album }
            if meta.genre.isEmpty { meta.genre = id3.genre }
            if meta.year == 0 { meta.year = id3.year }
            if meta.track == 0 { meta.track = id3.track }
            if meta.artwork == nil { meta.artwork = id3.artwork }
            if meta.lyrics == nil { meta.lyrics = id3.lyrics }
        }

        if meta.title.isEmpty {
            meta.title = ""
        }
        return meta
    }
}

/// Компактный парсер тегов ID3v2.3 / ID3v2.4 для MP3 (AVFoundation не всегда отдаёт обложку).
enum ID3Parser {

    struct Result {
        var title = ""
        var artist = ""
        var album = ""
        var genre = ""
        var year = 0
        var track = 0
        var artwork: Data?
        var lyrics: String?
    }

    static func parse(url: URL) -> Result {
        var result = Result()
        guard let fh = try? FileHandle(forReadingFrom: url) else { return result }
        defer { try? fh.close() }

        guard let header = try? fh.read(upToCount: 10), header.count == 10,
              header[0] == 0x49, header[1] == 0x44, header[2] == 0x33 else { return result }

        let major = Int(header[3])
        guard major == 3 || major == 4 else { return result }
        let flags = header[5]
        var tagSize = 0
        for i in 6..<10 { tagSize = (tagSize << 7) | Int(header[i]) }

        guard let data = try? fh.read(upToCount: tagSize), data.count > 10 else { return result }
        let buf = (flags & 0x80) != 0 ? unsync(data) : data

        var pos = 0
        if flags & 0x40 != 0, buf.count >= 6 {
            if major == 3 {
                pos = 4 + be32(buf, 0)
            } else {
                pos = ss32(buf, 0)
            }
        }

        while pos + 10 <= buf.count {
            let idData = buf.subdata(in: pos..<pos + 4)
            guard let fid = String(data: idData, encoding: .isoLatin1), fid.range(of: "^[A-Z0-9]{4}$", options: .regularExpression) != nil else { break }
            let fsize = major == 4 ? ss32(buf, pos + 4) : be32(buf, pos + 4)
            if fsize <= 0 || pos + 10 + fsize > buf.count { break }
            let frame = buf.subdata(in: (pos + 10)..<(pos + 10 + fsize))

            switch fid {
            case "TIT2": result.title = clean(text(frame))
            case "TPE1": result.artist = clean(text(frame))
            case "TALB": result.album = clean(text(frame))
            case "TCON": result.genre = cleanGenre(clean(text(frame)))
            case "TYER", "TDRC": result.year = Int(clean(text(frame)).prefix { $0.isNumber }) ?? 0
            case "TRCK": result.track = Int(clean(text(frame)).prefix { $0.isNumber }) ?? 0
            case "USLT": result.lyrics = uslt(frame)
            case "APIC": result.artwork = apic(frame)
            default: break
            }
            pos += 10 + fsize
        }
        return result
    }

    // MARK: - helpers

    private static func unsync(_ d: Data) -> Data {
        var out = Data(capacity: d.count)
        var i = 0
        let bytes = [UInt8](d)
        while i < bytes.count {
            out.append(bytes[i])
            if bytes[i] == 0xFF, i + 1 < bytes.count, bytes[i + 1] == 0x00 { i += 1 }
            i += 1
        }
        return out
    }

    private static func be32(_ d: Data, _ off: Int) -> Int {
        let b = [UInt8](d.subdata(in: off..<off + 4))
        return (Int(b[0]) << 24) | (Int(b[1]) << 16) | (Int(b[2]) << 8) | Int(b[3])
    }

    private static func ss32(_ d: Data, _ off: Int) -> Int {
        let b = [UInt8](d.subdata(in: off..<off + 4))
        return ((Int(b[0]) & 0x7F) << 21) | ((Int(b[1]) & 0x7F) << 14) | ((Int(b[2]) & 0x7F) << 7) | (Int(b[3]) & 0x7F)
    }

    private static func text(_ frame: Data) -> String {
        guard frame.count > 1 else { return "" }
        let enc = frame[frame.startIndex]
        let body = frame.subdata(in: (frame.startIndex + 1)..<frame.endIndex)
        switch enc {
        case 0: return String(data: body, encoding: .isoLatin1) ?? ""
        case 1: return String(data: body, encoding: .utf16) ?? ""
        case 2: return String(data: body, encoding: .utf16BigEndian) ?? ""
        default: return String(data: body, encoding: .utf8) ?? ""
        }
    }

    private static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanGenre(_ s: String) -> String {
        if s.hasPrefix("("), let close = s.firstIndex(of: ")") {
            let inner = String(s[s.index(after: s.startIndex)..<close])
            if Int(inner) != nil { return String(s[s.index(after: close)...]) }
        }
        return s
    }

    private static func apic(_ frame: Data) -> Data? {
        guard frame.count > 4 else { return nil }
        let bytes = [UInt8](frame)
        let enc = bytes[0]
        var i = 1
        while i < bytes.count, bytes[i] != 0 { i += 1 }  // mime
        if i >= bytes.count { return nil }
        i += 1            // null mime
        i += 1            // picture type
        if enc == 1 || enc == 2 {
            while i + 1 < bytes.count, !(bytes[i] == 0 && bytes[i + 1] == 0) { i += 2 }  // description (utf16)
            i += 2
        } else {
            while i < bytes.count, bytes[i] != 0 { i += 1 }  // description
            i += 1
        }
        guard i < bytes.count else { return nil }
        return frame.subdata(in: i..<bytes.count)
    }

    /// USLT (unsynchronized lyrics): enc(1) + lang(3) + descriptor(0-terminated) + text
    private static func uslt(_ frame: Data) -> String? {
        guard frame.count > 4 else { return nil }
        let bytes = [UInt8](frame)
        let enc = bytes[0]
        var i = 4  // enc + lang
        if enc == 1 || enc == 2 {
            while i + 1 < bytes.count, !(bytes[i] == 0 && bytes[i + 1] == 0) { i += 2 }
            i += 2
        } else {
            while i < bytes.count, bytes[i] != 0 { i += 1 }
            i += 1
        }
        guard i < bytes.count else { return nil }
        let body = frame.subdata(in: i..<bytes.count)
        switch enc {
        case 1: return String(data: body, encoding: .utf16)
        case 2: return String(data: body, encoding: .utf16BigEndian)
        case 3: return String(data: body, encoding: .utf8)
        default: return String(data: body, encoding: .isoLatin1)
        }
    }
}

import SwiftUI

// MARK: - helpers

func fmtTime(_ t: TimeInterval) -> String {
    let s = max(0, Int(t.rounded()))
    return String(format: "%d:%02d", s / 60, s % 60)
}

func fmtTotalTime(_ t: TimeInterval) -> String {
    let m = Int(t) / 60
    if m >= 60 { return String(format: "%d ч %d мин", m / 60, m % 60) }
    return "\(m) мин"
}

func stableHash(_ s: String) -> Int {
    var h: UInt64 = 5381
    for b in s.utf8 { h = (h &* 33) &+ UInt64(b) }
    return Int(truncatingIfNeeded: h)
}

func seedGradient(_ seed: String, bright: Bool = true) -> LinearGradient {
    let h = Double(abs(stableHash(seed) % 360)) / 360.0
    let top = Color(hue: h, saturation: bright ? 0.62 : 0.5, brightness: bright ? 0.92 : 0.75)
    let bottom = Color(hue: (h + 0.09).truncatingRemainder(dividingBy: 1), saturation: 0.72, brightness: 0.5)
    return LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension Color {
    static let amRed = Color(red: 250.0 / 255.0, green: 35.0 / 255.0, blue: 59.0 / 255.0)
}

// MARK: - artwork

struct ArtworkView: View {
    var seed: String = ""
    var data: Data?

    var body: some View {
        if let d = data, let img = UIImage(data: d) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                seedGradient(seed)
                Image(systemName: "music.note")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
    }
}

// MARK: - song row

struct SongRow: View {
    let track: Track
    var number: Int?
    var showAlbumInfo = true
    var showArtwork = true

    @EnvironmentObject var player: AudioPlayer

    var body: some View {
        HStack(spacing: 12) {
            if let n = number {
                Text("\(n)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 28, alignment: .center)
            } else if showArtwork {
                ArtworkView(seed: track.album, data: track.artwork)
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(track.displayTitle)
                    .font(.system(size: 16))
                    .foregroundColor(player.current?.id == track.id ? .amRed : .primary)
                    .lineLimit(1)
                Text(showAlbumInfo ? "\(track.displayArtist) • \(track.displayAlbum)" : track.displayArtist)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(fmtTime(track.duration))
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - track context menu

struct TrackMenu: ViewModifier {
    let track: Track
    let contextTracks: [Track]
    let onDeleteFromPlaylist: (() -> Void)?

    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var library: LibraryStore

    func body(content: Content) -> some View {
        content.contextMenu {
            Button { playNow() } label: { Label("Воспроизвести", systemImage: "play.fill") }
            Button { insertNext() } label: { Label("Слушать далее", systemImage: "text.line.first.and.arrowtriangle.forward") }
            Button { playLast() } label: { Label("В конец очереди", systemImage: "text.line.last.and.arrowtriangle.forward") }
            Divider()
            NavigationLink(destination: AlbumDetailView(albumID: track.albumID())) {
                Label("Перейти к альбому", systemImage: "square.stack")
            }
            if !track.artistKey.isEmpty {
                NavigationLink(destination: ArtistDetailView(artistID: track.artistKey)) {
                    Label("Перейти к исполнителю", systemImage: "person")
                }
            }
            Divider()
            AddToPlaylistButton(trackID: track.id)
            if let del = onDeleteFromPlaylist {
                Button(role: .destructive) { del() } label: { Label("Удалить из плейлиста", systemImage: "minus.circle") }
            }
        }
    }

    private func playNow() {
        if contextTracks.isEmpty {
            player.play([track], context: "МЕДИАТЕКИ")
        } else if let i = contextTracks.firstIndex(where: { $0.id == track.id }) {
            player.play(contextTracks, startIndex: i)
        } else {
            player.play([track], context: "МЕДИАТЕКИ")
        }
    }

    private func insertNext() {
        player.insertNext(track)
    }

    private func playLast() {
        player.appendToQueue(track)
    }
}

extension Notification.Name {
    static let amShowAddToPlaylist = Notification.Name("amShowAddToPlaylist")
    static let amResetPlayStats = Notification.Name("amResetPlayStats")
}

// MARK: - lyrics

struct LyricLine: Identifiable {
    let id: Int
    let time: TimeInterval?
    let text: String
}

func parseLyrics(_ raw: String) -> [LyricLine] {
    var out: [LyricLine] = []
    let regex = try? NSRegularExpression(pattern: "\\[(\\d{1,2}):(\\d{1,2})(?:[.:](\\d{1,3}))?\\]")
    for rawLine in raw.components(separatedBy: .newlines) {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.isEmpty { continue }
        var time: TimeInterval?
        var text = line
        if let re = regex {
            let ns = line as NSString
            let matches = re.matches(in: line, range: NSRange(location: 0, length: ns.length))
            if let m = matches.first, m.range.location == 0 {
                let mm = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let ss = Double(ns.substring(with: m.range(at: 2))) ?? 0
                var frac = 0.0
                if m.range(at: 3).location != NSNotFound {
                    frac = Double("0." + ns.substring(with: m.range(at: 3))) ?? 0
                }
                time = mm * 60 + ss + frac
                text = String(ns.substring(from: m.range.upperBound)).trimmingCharacters(in: .whitespaces)
            }
        }
        if !text.isEmpty {
            out.append(LyricLine(id: out.count, time: time, text: text))
        }
    }
    return out
}

func lyricsAreSynced(_ lines: [LyricLine]) -> Bool {
    let withTime = lines.filter { $0.time != nil }.count
    return lines.count >= 4 && withTime >= lines.count / 2
}

func currentLyricIndex(_ lines: [LyricLine], at t: TimeInterval) -> Int? {
    var result: Int?
    for (i, line) in lines.enumerated() {
        if let time = line.time, time <= t { result = i } else if time != nil { break }
    }
    return result
}

extension UIImage {
    func resized(maxSide: CGFloat) -> UIImage {
        let maxDim = max(size.width, size.height)
        guard maxDim > maxSide, maxDim > 0 else { return self }
        let scale = maxSide / maxDim
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}

struct TrackRef: Identifiable {
    let id: String
}

struct AddToPlaylistButton: View {
    let trackID: String

    var body: some View {
        Button {
            NotificationCenter.default.post(
                name: .amShowAddToPlaylist,
                object: nil,
                userInfo: ["trackID": trackID]
            )
        } label: {
            Label("Добавить в плейлист…", systemImage: "music.note.list")
        }
    }
}

struct PlaylistPickerSheet: View {
    let trackID: String
    @EnvironmentObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var newPlaylistName = ""
    @State private var showNewAlert = false

    var body: some View {
        NavigationStack {
            List {
                Button {
                    showNewAlert = true
                } label: {
                    Label("Новый плейлист", systemImage: "plus")
                        .foregroundColor(.amRed)
                }
                ForEach(library.playlists) { pl in
                    Button {
                        library.addToPlaylist(trackID: trackID, playlistID: pl.id)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pl.name).foregroundColor(.primary)
                            Text("\(pl.trackIDs.count) песен")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Плейлисты")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") { dismiss() }
                }
            }
            .alert("Новый плейлист", isPresented: $showNewAlert) {
                TextField("Название", text: $newPlaylistName)
                Button("Создать") {
                    let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        library.createPlaylist(name: name)
                        if let pl = library.playlists.last {
                            library.addToPlaylist(trackID: trackID, playlistID: pl.id)
                        }
                        dismiss()
                    }
                    newPlaylistName = ""
                }
                Button("Отмена", role: .cancel) { newPlaylistName = "" }
            }
        }
    }
}

extension Track {
    func albumID() -> String {
        "\(artistKey)|\(displayAlbum.lowercased())"
    }
}

// MARK: - empty state

struct EmptyLibraryView: View {
    var showAdd: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note.house")
                .font(.system(size: 56))
                .foregroundColor(.secondary)
            Text("Медиатека пуста")
                .font(.title3.weight(.semibold))
            Text("Добавьте песни кнопкой ниже или скопируйте файлы в папку «Музыка» приложения через Finder (кабель).")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            if let showAdd {
                Button(action: showAdd) {
                    Label("Добавить музыку", systemImage: "plus")
                        .font(.system(size: 16, weight: .semibold))
                }
                .tint(.amRed)
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

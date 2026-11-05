import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject var player: AudioPlayer
    @Environment(\.dismiss) private var dismiss

    @State private var isScrubbing = false
    @State private var scrubValue = 0.0
    @State private var showQueue = false
    @State private var showLyrics = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Spacer(minLength: 12)
                artwork
                Spacer(minLength: 20)
                titleRow
                scrubber
                    .padding(.top, 10)
                volumeRow
                    .padding(.top, 10)
                controls
                    .padding(.top, 14)
                Spacer(minLength: 16)
                bottomRow
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)

            if showLyrics {
                LyricsPanel(onClose: { withAnimation { showLyrics = false } })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .sheet(isPresented: $showQueue) {
            QueueSheet()
        }
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 22, weight: .semibold))
            }
            Spacer()
            VStack(spacing: 1) {
                Text("ИГРАЕТ ИЗ")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(player.contextTitle)
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
            }
            Spacer()
            Button {
                showQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 20, weight: .semibold))
            }
        }
        .foregroundColor(.primary)
    }

    private var artwork: some View {
        Group {
            if let t = player.current {
                ArtworkView(seed: t.album, data: t.artwork)
            } else {
                ArtworkView()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 10)
        .frame(maxWidth: 320)
        .opacity(showLyrics ? 0.1 : 1)
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(player.current?.displayTitle ?? "Ничего не играет")
                    .font(.system(size: 21, weight: .bold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(player.current?.displayArtist ?? "—")
                        .font(.system(size: 20))
                        .foregroundColor(.amRed)
                        .lineLimit(1)
                    if let bpm = player.current?.bpm {
                        Text(String(format: "%.0f BPM", bpm))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer(minLength: 8)
            Menu {
                if let t = player.current {
                    NavigationLink(destination: AlbumDetailView(albumID: t.albumID())) {
                        Label("Перейти к альбому", systemImage: "square.stack")
                    }
                    AddToPlaylistButton(trackID: t.id)
                    Button {
                        player.removeFromQueue(trackID: t.id)
                    } label: {
                        Label("Убрать из очереди", systemImage: "minus.circle")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var scrubber: some View {
        VStack(spacing: 4) {
            Slider(
                value: isScrubbing
                    ? $scrubValue
                    : Binding(
                        get: { player.duration > 0 ? player.currentTime / player.duration : 0 },
                        set: { _ in }
                    ),
                in: 0...1
            ) { editing in
                if editing {
                    scrubValue = player.duration > 0 ? player.currentTime / player.duration : 0
                    isScrubbing = true
                } else {
                    player.seek(fraction: scrubValue)
                    isScrubbing = false
                }
            }
            .tint(.primary.opacity(0.85))

            HStack {
                Text(fmtTime(isScrubbing ? scrubValue * player.duration : player.currentTime))
                Spacer()
                Text("-" + fmtTime(max(0, player.duration - (isScrubbing ? scrubValue * player.duration : player.currentTime))))
            }
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .monospacedDigit()
        }
    }

    private var volumeRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Slider(value: Binding(
                get: { Double(player.volume) },
                set: { player.volume = Float($0) }
            ), in: 0...1)
            .tint(.secondary.opacity(0.5))
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
    }

    private var controls: some View {
        HStack {
            Button {
                player.shuffleOn.toggle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(player.shuffleOn ? .amRed : .primary)
            }
            .frame(maxWidth: .infinity)

            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 27))
            }
            .frame(maxWidth: .infinity)

            Button {
                player.toggle()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 40, weight: .medium))
            }
            .frame(maxWidth: .infinity)

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 27))
            }
            .frame(maxWidth: .infinity)

            Button {
                player.repeatMode = player.repeatMode == .off ? .all : (player.repeatMode == .all ? .one : .off)
            } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(player.repeatMode != .off ? .amRed : .primary)
            }
            .frame(maxWidth: .infinity)
        }
        .foregroundColor(.primary)
    }

    private var bottomRow: some View {
        HStack {
            Button {
                withAnimation { showLyrics = true }
            } label: {
                Image(systemName: showLyrics ? "quote.bubble.fill" : "quote.bubble")
                    .font(.system(size: 18))
                    .foregroundColor(showLyrics ? .amRed : .primary)
            }
            Spacer()
            if UserDefaults.standard.bool(forKey: "automixEnabled") || UserDefaults.standard.object(forKey: "automixEnabled") == nil {
                Text("AUTOMIX")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.amRed)
            }
            Spacer()
            Button {
                showQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 17))
            }
        }
        .foregroundColor(.primary)
    }
}

// MARK: - текст песни

struct LyricsPanel: View {
    var onClose: () -> Void
    @EnvironmentObject var player: AudioPlayer

    private var lines: [LyricLine] {
        guard let raw = player.current?.lyrics, !raw.isEmpty else { return [] }
        return parseLyrics(raw)
    }

    var body: some View {
        let parsed = lines
        let synced = lyricsAreSynced(parsed)
        VStack(spacing: 0) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 20, weight: .semibold))
                }
                Spacer()
                Text("ТЕКСТ ПЕСНИ")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                Color.clear.frame(width: 20, height: 20)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)

            if parsed.isEmpty {
                Spacer()
                Text("В тегах этого файла нет текста")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            } else if synced {
                SyncedLyricsList(lines: parsed)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(parsed) { line in
                            Text(line.text)
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundColor(.primary.opacity(0.75))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
                }
            }
        }
        .background(.thinMaterial, in: Rectangle())
    }
}

struct SyncedLyricsList: View {
    let lines: [LyricLine]
    @EnvironmentObject var player: AudioPlayer

    var body: some View {
        let current = currentLyricIndex(lines, at: player.currentTime)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    Color.clear.frame(height: 120).id(-1)
                    ForEach(lines) { line in
                        let isCurrent = line.time != nil && currentLyricIndex(lines, at: player.currentTime) == line.id
                        Text(line.text)
                            .font(.system(size: isCurrent ? 24 : 20, weight: .bold))
                            .foregroundColor(isCurrent ? .primary : .primary.opacity(0.35))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                            .onTapGesture {
                                if let t = line.time { player.seek(to: t) }
                            }
                    }
                    Color.clear.frame(height: 160).id(-2)
                }
                .padding(.horizontal, 28)
            }
            .onChange(of: current) { idx in
                if let idx {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(idx, anchor: .center)
                    }
                }
            }
        }
    }
}

// MARK: - очередь

struct QueueSheet: View {
    @EnvironmentObject var player: AudioPlayer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let cur = player.current {
                    Section("Сейчас играет") {
                        Button {
                            player.playFromQueue(player.index)
                        } label: {
                            SongRow(track: cur)
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                    }
                }
                if player.queue.count > 1 {
                    Section("Далее") {
                        ForEach(Array(player.queue.enumerated()), id: \.element.id) { i, t in
                            if i != player.index {
                                Button {
                                    player.playFromQueue(i)
                                } label: {
                                    SongRow(track: t)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        player.removeFromQueue(at: i)
                                    } label: {
                                        Label("Убрать", systemImage: "minus.circle")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Очередь")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

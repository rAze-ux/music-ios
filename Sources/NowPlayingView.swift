import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject var player: AudioPlayer
    @Environment(\.dismiss) private var dismiss

    @State private var isScrubbing = false
    @State private var scrubValue = 0.0
    @State private var showQueue = false

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
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(player.current?.displayTitle ?? "Ничего не играет")
                    .font(.system(size: 21, weight: .bold))
                    .lineLimit(1)
                Text(player.current?.displayArtist ?? "—")
                    .font(.system(size: 20))
                    .foregroundColor(.amRed)
                    .lineLimit(1)
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
                showQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 17))
            }
            Spacer()
            Text("\(player.queue.count) песен в очереди")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
            Color.clear.frame(width: 17, height: 17)
        }
    }
}

// MARK: - queue sheet

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

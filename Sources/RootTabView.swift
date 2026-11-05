import SwiftUI

struct RootTabView: View {
    @EnvironmentObject var player: AudioPlayer
    @State private var selection = 3
    @State private var playlistTrack: TrackRef?

    var body: some View {
        TabView(selection: $selection) {
            ListenNowView()
                .tabItem { Label("Слушать", systemImage: "play.circle.fill") }
                .tag(0)
            BrowseView()
                .tabItem { Label("Обзор", systemImage: "square.grid.2x2.fill") }
                .tag(1)
            RadioView()
                .tabItem { Label("Радио", systemImage: "dot.radiowaves.left.and.right") }
                .tag(2)
            LibraryView()
                .tabItem { Label("Медиатека", systemImage: "music.note.list") }
                .tag(3)
            SearchView()
                .tabItem { Label("Поиск", systemImage: "magnifyingglass") }
                .tag(4)
        }
        .tint(.amRed)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MiniPlayerBar()
        }
        .onReceive(NotificationCenter.default.publisher(for: .amShowAddToPlaylist)) { note in
            if let id = note.userInfo?["trackID"] as? String {
                playlistTrack = TrackRef(id: id)
            }
        }
        .sheet(item: $playlistTrack) { ref in
            PlaylistPickerSheet(trackID: ref.id)
        }
    }
}

// MARK: - mini player

struct MiniPlayerBar: View {
    @EnvironmentObject var player: AudioPlayer
    @State private var showFull = false

    var body: some View {
        Group {
            if let t = player.current {
                VStack(spacing: 0) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.12))
                            Capsule()
                                .fill(Color.amRed)
                                .frame(width: player.duration > 0 ? geo.size.width * CGFloat(player.currentTime / player.duration) : 0)
                        }
                    }
                    .frame(height: 2.5)

                    HStack(spacing: 10) {
                        ArtworkView(seed: t.album, data: t.artwork)
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.displayTitle)
                                .font(.system(size: 14, weight: .medium))
                                .lineLimit(1)
                            Text(t.displayArtist)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Button {
                            player.toggle()
                        } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 20))
                        }
                        .padding(.horizontal, 6)
                        Button {
                            player.next()
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 20))
                        }
                        .padding(.leading, 6)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .foregroundColor(.primary)
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.thinMaterial)
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
                .contentShape(Rectangle())
                .onTapGesture { showFull = true }
                .fullScreenCover(isPresented: $showFull) {
                    NowPlayingView()
                }
            }
        }
    }
}

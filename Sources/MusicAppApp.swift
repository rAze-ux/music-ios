import SwiftUI

@main
struct MusicAppApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var player = AudioPlayer()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(library)
                .environmentObject(player)
                .onAppear {
                    player.onTrackPlayed = { track in
                        library.registerPlay(id: track.id)
                    }
                    library.rescan()
                }
        }
    }
}

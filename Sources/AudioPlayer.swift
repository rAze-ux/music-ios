import Foundation
import AVFoundation
import MediaPlayer
import UIKit

final class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {

    enum RepeatMode: Int {
        case off = 0, all = 1, one = 2
    }

    @Published private(set) var queue: [Track] = []
    @Published private(set) var index: Int = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published var contextTitle: String = "МЕДИАТЕКИ"
    @Published var volume: Float = 1.0 {
        didSet { audioPlayer?.volume = volume }
    }
    @Published var shuffleOn = false { didSet { rebuildOrder(preserveCurrent: true) } }
    @Published var repeatMode: RepeatMode = .off

    var current: Track? { queue.indices.contains(index) ? queue[index] : nil }
    var duration: TimeInterval { audioPlayer?.duration ?? current?.duration ?? 0 }

    var onTrackPlayed: ((Track) -> Void)?

    private var audioPlayer: AVAudioPlayer?
    private var playOrder: [Int] = []
    private var orderPos = 0
    private var timer: Timer?

    // MARK: - setup

    override init() {
        super.init()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        setupRemoteCommands()
        setupInterruptionHandling()
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in self?.resume(); return .success }
        center.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        center.nextTrackCommand.addTarget { [weak self] _ in self?.next(); return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in self?.previous(); return .success }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self.seek(to: e.positionTime)
            return .success
        }
    }

    private func setupInterruptionHandling() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            switch type {
            case .began:
                self.pause()
            case .ended:
                let optsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let opts = AVAudioSession.InterruptionOptions(rawValue: optsRaw)
                if opts.contains(.shouldResume) { self.resume() }
            @unknown default:
                break
            }
        }
    }

    // MARK: - playback control

    func play(_ tracks: [Track], startIndex: Int = 0, context: String = "МЕДИАТЕКИ") {
        guard !tracks.isEmpty else { return }
        queue = tracks
        contextTitle = context
        if shuffleOn {
            playOrder = Array(0..<queue.count).shuffled()
            if let i = playOrder.firstIndex(of: startIndex) { playOrder.swapAt(0, i) }
            orderPos = 0
            index = playOrder[0]
        } else {
            playOrder = Array(0..<queue.count)
            orderPos = startIndex
            index = startIndex
        }
        startCurrent()
    }

    func playFromQueue(_ i: Int) {
        guard queue.indices.contains(i) else { return }
        if shuffleOn {
            playOrder = Array(0..<queue.count).shuffled()
            if let p = playOrder.firstIndex(of: i) { playOrder.swapAt(0, p) }
            orderPos = 0
        } else {
            playOrder = Array(0..<queue.count)
            orderPos = i
        }
        index = i
        startCurrent()
    }

    func toggle() {
        isPlaying ? pause() : resume()
    }

    func resume() {
        guard audioPlayer != nil else { return }
        audioPlayer?.play()
        isPlaying = true
        startTimer()
        updateNowPlaying()
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        timer?.invalidate()
        updateNowPlaying()
    }

    func stop() {
        timer?.invalidate()
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentTime = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func next(auto: Bool = false) {
        if auto, repeatMode == .one {
            restartCurrent()
            return
        }
        let nextPos = orderPos + 1
        if nextPos < playOrder.count {
            orderPos = nextPos
        } else if repeatMode == .all || !auto {
            orderPos = 0
        } else {
            pause()
            seek(to: 0)
            return
        }
        index = playOrder[orderPos]
        startCurrent()
    }

    func previous() {
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        orderPos = orderPos > 0 ? orderPos - 1 : playOrder.count - 1
        index = playOrder[orderPos]
        startCurrent()
    }

    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = max(0, min(time, duration))
        currentTime = audioPlayer?.currentTime ?? 0
        updateNowPlaying()
    }

    func seek(fraction: Double) {
        seek(to: duration * fraction)
    }

    // MARK: - queue editing

    func insertNext(_ track: Track) {
        guard !queue.isEmpty else { play([track]); return }
        let at = min(index + 1, queue.count)
        queue.insert(track, at: at)
        rebuildOrder(preserveCurrent: true)
    }

    func appendToQueue(_ track: Track) {
        if queue.isEmpty {
            play([track])
        } else {
            queue.append(track)
            rebuildOrder(preserveCurrent: true)
        }
    }

    func removeFromQueue(at offset: Int) {
        guard queue.indices.contains(offset) else { return }
        let wasCurrent = offset == index
        queue.remove(at: offset)
        if offset < index { index -= 1 }
        if wasCurrent {
            index = min(index, queue.count - 1)
            if queue.isEmpty {
                stop()
            } else if isPlaying {
                startCurrent()
            }
        } else {
            rebuildOrder(preserveCurrent: true)
        }
    }

    func removeFromQueue(trackID: String) {
        guard trackID != current?.id else { return }
        if let i = queue.firstIndex(where: { $0.id == trackID }) {
            removeFromQueue(at: i)
        }
    }

    private func restartCurrent() {
        seek(to: 0)
        resume()
    }

    private func startCurrent() {
        guard queue.indices.contains(index), let track = current else { return }
        timer?.invalidate()
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("Музыка", isDirectory: true).appendingPathComponent(track.relativePath)
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.volume = volume
            audioPlayer?.play()
            isPlaying = true
            currentTime = 0
            startTimer()
            updateNowPlaying()
            onTrackPlayed?(track)
        } catch {
            audioPlayer = nil
            isPlaying = false
            next()
        }
    }

    // MARK: - shuffle order

    private func rebuildOrder(preserveCurrent: Bool) {
        guard !queue.isEmpty else { return }
        let cur = queue.indices.contains(index) ? index : 0
        if shuffleOn {
            playOrder = Array(0..<queue.count).shuffled()
            if let p = playOrder.firstIndex(of: cur) {
                orderPos = p
            } else {
                orderPos = 0
            }
        } else {
            playOrder = Array(0..<queue.count)
            orderPos = playOrder.firstIndex(of: cur) ?? 0
        }
    }

    // MARK: - timer

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let p = self.audioPlayer else { return }
            self.currentTime = p.currentTime
        }
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { self.next(auto: true) }
    }

    // MARK: - Now Playing (lock screen)

    private func updateNowPlaying() {
        guard let t = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: t.displayTitle,
            MPMediaItemPropertyArtist: t.displayArtist,
            MPMediaItemPropertyAlbumTitle: t.displayAlbum,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let data = t.artwork, let img = UIImage(data: data) {
            let art = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
            info[MPMediaItemPropertyArtwork] = art
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

import Foundation
import AVFoundation
import MediaPlayer
import UIKit

/// Плеер на AVAudioEngine: два PlayerNode для диджей-кроссфейда (автомикс),
/// 10-полосный эквалайзер, защита от аварийных циклов.
final class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {

    enum RepeatMode: Int {
        case off = 0, all = 1, one = 2
    }

    @Published private(set) var queue: [Track] = []
    @Published private(set) var index: Int = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var automixNext: Track?
    @Published var contextTitle: String = "МЕДИАТЕКИ"
    @Published var volume: Float = 1.0 {
        didSet { engine?.mainMixerNode.outputVolume = volume }
    }
    @Published var shuffleOn = false { didSet { rebuildOrder(preserveCurrent: true) } }
    @Published var repeatMode: RepeatMode = .off

    var current: Track? { queue.indices.contains(index) ? queue[index] : nil }
    var duration: TimeInterval { currentDuration.isFinite && currentDuration > 0 ? currentDuration : 0 }

    var onTrackPlayed: ((Track) -> Void)?
    var similarProvider: ((Track) -> [Track])?
    var onBPMAnalyzed: ((String, Double) -> Void)?

    private var engine: AVAudioEngine?
    private var eqNode: AVAudioUnitEQ?
    private var nodes: [AVAudioPlayerNode] = []
    private var activeIdx = 0
    private var currentFile: AVAudioFile?
    private var currentDuration: TimeInterval = 0
    private var playOffset: TimeInterval = 0
    private var playStartDate = Date()
    private var pausedAt: TimeInterval = 0
    private var generation = 0
    private var crossfadeStarted = false
    private var autoSkipTimes: [Date] = []
    private var analyzing: Set<String> = []
    private var timer: Timer?

    // MARK: - init

    override init() {
        super.init()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { /* плеер всё равно попробует стартовать */ }
        setupRemoteCommands()
        setupInterruptionHandling()
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyEQSettings()
        }
    }

    private var fadeDuration: Double {
        let f = UserDefaults.standard.double(forKey: "crossfadeSeconds")
        return f > 0 ? min(8, f) : 4
    }
    private var automixEnabled: Bool {
        UserDefaults.standard.object(forKey: "automixEnabled") == nil ? true : UserDefaults.standard.bool(forKey: "automixEnabled")
    }

    // MARK: - engine

    @discardableResult
    private func ensureEngine() -> Bool {
        if engine == nil {
            let e = AVAudioEngine()
            let eq = AVAudioUnitEQ(numberOfBands: EQPresets.frequencies.count)
            for (i, f) in EQPresets.frequencies.enumerated() {
                let b = eq.bands[i]
                b.filterType = .peaking
                b.frequency = f
                b.bandwidth = 1.0
                b.gain = 0
                b.bypass = true
            }
            let a = AVAudioPlayerNode()
            let b = AVAudioPlayerNode()
            e.attach(a)
            e.attach(b)
            e.attach(eq)
            e.connect(a, to: eq, format: nil)
            e.connect(b, to: eq, format: nil)
            e.connect(eq, to: e.mainMixerNode, format: nil)
            engine = e
            eqNode = eq
            nodes = [a, b]
            activeIdx = 0
            e.mainMixerNode.outputVolume = volume
            applyEQSettings()
        }
        guard let e = engine else { return false }
        if !e.isRunning {
            do {
                try e.start()
            } catch {
                return false
            }
        }
        return true
    }

    private func applyEQSettings() {
        guard let eq = eqNode else { return }
        let d = UserDefaults.standard
        let enabled = d.bool(forKey: "eqEnabled")
        let preset = d.string(forKey: "eqPreset") ?? "Flat"
        let customStr = d.string(forKey: "eqCustom") ?? "0,0,0,0,0,0,0,0,0,0"
        var gains = EQPresets.gains[preset] ?? Array(repeating: 0, count: EQPresets.frequencies.count)
        if preset == "Custom" {
            let parsed = customStr.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if parsed.count == EQPresets.frequencies.count { gains = parsed }
        }
        for i in 0..<EQPresets.frequencies.count {
            let band = eq.bands[i]
            band.bypass = !enabled
            if i < gains.count {
                band.gain = Float(max(-12, min(12, gains[i])))
            }
        }
    }

    private func musicURL(_ track: Track) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Музыка", isDirectory: true).appendingPathComponent(track.relativePath)
    }

    // MARK: - public control

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
        guard current != nil, ensureEngine() else { return }
        let node = nodes[activeIdx]
        if !node.isPlaying { node.play() }
        isPlaying = true
        playOffset = pausedAt
        playStartDate = Date()
        startTimer()
        updateNowPlaying()
    }

    func pause() {
        guard engine != nil else { return }
        nodes[activeIdx].pause()
        isPlaying = false
        pausedAt = currentTime
        timer?.invalidate()
        updateNowPlaying()
    }

    func stop() {
        generation += 1
        timer?.invalidate()
        timer = nil
        nodes.forEach { $0.stop() }
        isPlaying = false
        currentTime = 0
        pausedAt = 0
        automixNext = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func next(auto: Bool = false) {
        if auto, repeatMode == .one, current != nil {
            seek(to: 0)
            resumeIfNeededAfterSeek()
            return
        }
        let canAdvance = orderPos + 1 < playOrder.count || repeatMode == .all || !auto
        guard canAdvance, !playOrder.isEmpty else {
            pause()
            seek(to: 0)
            resumeIfNeededAfterSeek()
            return
        }
        advanceOrder()
        transition(fadeDuration: 0.35)
    }

    func previous() {
        if currentTime > 3 {
            seek(to: 0)
            resumeIfNeededAfterSeek()
            return
        }
        guard !playOrder.isEmpty else { return }
        orderPos = orderPos > 0 ? orderPos - 1 : playOrder.count - 1
        index = playOrder[orderPos]
        transition(fadeDuration: 0.35)
    }

    func seek(to time: TimeInterval) {
        guard current != nil, currentFile != nil, ensureEngine() else { return }
        let t = max(0, min(time, duration))
        let node = nodes[activeIdx]
        node.stop()
        if isPlaying {
            scheduleSegment(from: t)
            node.play()
            playOffset = t
            playStartDate = Date()
        }
        pausedAt = t
        currentTime = t
        updateNowPlaying()
    }

    func seek(fraction: Double) {
        seek(to: duration * fraction)
    }

    // MARK: - queue editing

    func insertNext(_ track: Track) {
        guard !queue.isEmpty else { play([track]); return }
        queue.insert(track, at: min(index + 1, queue.count))
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

    // MARK: - internals

    private var playOrder: [Int] = []
    private var orderPos = 0

    private func startCurrent() {
        guard let track = current else { stop(); return }
        guard ensureEngine(), !nodes.isEmpty else { return }
        generation += 1
        crossfadeStarted = false
        automixNext = nil
        pausedAt = 0
        let g = generation
        if scheduleTrack(track, on: nodes[activeIdx], fadeIn: 0, gen: g) {
            isPlaying = true
            startTimer()
            updateNowPlaying()
            onTrackPlayed?(track)
            analyzeIfNeeded(track)
        } else {
            handleLoadFailure()
        }
    }

    private func transition(fadeDuration fade: Double) {
        guard let track = current else { stop(); return }
        guard ensureEngine(), nodes.count == 2 else { return }
        generation += 1
        let g = generation
        let newIdx = 1 - activeIdx
        let newNode = nodes[newIdx]
        let oldNode = nodes[activeIdx]
        if scheduleTrack(track, on: newNode, fadeIn: max(fade, 0.05), gen: g) {
            if fade > 0.05 {
                oldNode.setVolume(0, fadeDuration: fade)
                activeIdx = newIdx
                DispatchQueue.main.asyncAfter(deadline: .now() + fade + 0.15) {
                    oldNode.stop()
                    oldNode.volume = 1
                }
            } else {
                activeIdx = newIdx
                oldNode.stop()
            }
            isPlaying = true
            startTimer()
            updateNowPlaying()
            onTrackPlayed?(track)
            analyzeIfNeeded(track)
        } else {
            handleLoadFailure()
        }
    }

    @discardableResult
    private func scheduleTrack(_ track: Track, on node: AVAudioPlayerNode, fadeIn: Double, gen: Int) -> Bool {
        guard let file = try? AVAudioFile(forReading: musicURL(track)) else { return false }
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0, file.length > 0 else { return false }
        currentFile = file
        currentDuration = Double(file.length) / sampleRate
        node.stop()
        node.volume = fadeIn > 0 ? 0 : 1
        node.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async { self?.naturalEnd(gen: gen) }
        }
        node.play()
        if fadeIn > 0 { node.setVolume(1, fadeDuration: fadeIn) }
        playOffset = 0
        playStartDate = Date()
        return true
    }

    private func scheduleSegment(from t: TimeInterval) {
        guard let file = currentFile else { return }
        let sr = file.processingFormat.sampleRate
        let node = nodes[activeIdx]
        let startFrame = AVAudioFramePosition(t * sr)
        let framesLeft = AVAudioFramePosition(currentDuration * sr) - startFrame
        guard framesLeft > 1 else { return }
        node.volume = 1
        let g = generation
        node.scheduleSegment(
            fromFrame: startFrame,
            frameCount: AVAudioFrameCount(framesLeft),
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.naturalEnd(gen: g) }
        }
    }

    private func resumeIfNeededAfterSeek() {
        if isPlaying { /* seek уже продолжил воспроизведение */ } else { /* остаёмся на паузе */ }
    }

    private func naturalEnd(gen: Int) {
        guard gen == generation else { return }
        next(auto: true)
    }

    private func handleLoadFailure() {
        autoSkipTimes.append(Date())
        autoSkipTimes = autoSkipTimes.filter { $0.timeIntervalSinceNow > -5 }
        if autoSkipTimes.count >= 3 {
            stop()
            return
        }
        let canAdvance = orderPos + 1 < playOrder.count || repeatMode == .all
        guard canAdvance else { stop(); return }
        advanceOrder()
        startCurrent()
    }

    private func advanceOrder() {
        if orderPos + 1 < playOrder.count {
            orderPos += 1
        } else if repeatMode == .all {
            orderPos = 0
        }
        index = playOrder.indices.contains(orderPos) ? playOrder[orderPos] : 0
    }

    // MARK: - automix

    private func maybeAutomix() {
        guard automixEnabled, !crossfadeStarted, isPlaying,
              duration > 0,
              currentTime >= duration - fadeDuration,
              currentTime < duration else { return }
        guard let cur = current else { return }
        guard let similar = pickSimilar(to: cur) else {
            crossfadeStarted = true  // похожей нет — доиграем и перейдём естественно
            return
        }
        crossfadeStarted = true
        forceNext(similar)
        automixNext = similar
        transition(fadeDuration: fadeDuration)
        automixNext = current?.id == similar.id ? similar : nil
    }

    private func pickSimilar(to track: Track) -> Track? {
        let pool = similarProvider?(track) ?? []
        return pool.first { $0.id != track.id }
    }

    /// Вставляет трек сразу после текущего и делает его следующим по порядку.
    private func forceNext(_ t: Track) {
        let insertAt = min(index + 1, queue.count)
        queue.insert(t, at: insertAt)
        rebuildOrder(preserveCurrent: true)
        if let p = playOrder.firstIndex(of: index), let q = playOrder.firstIndex(of: insertAt), q != p + 1 {
            playOrder.swapAt(q, p + 1)
        }
    }

    // MARK: - BPM analysis

    private func analyzeIfNeeded(_ track: Track) {
        guard track.bpm == nil, !analyzing.contains(track.id) else { return }
        analyzing.insert(track.id)
        let url = musicURL(track)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let bpm = BPMDetector.analyze(url: url)
            DispatchQueue.main.async {
                self?.analyzing.remove(track.id)
                if let bpm, bpm > 0 {
                    self?.onBPMAnalyzed?(track.id, bpm)
                }
            }
        }
    }

    // MARK: - shuffle order

    private func rebuildOrder(preserveCurrent: Bool) {
        guard !queue.isEmpty else { return }
        let cur = queue.indices.contains(index) ? index : 0
        if shuffleOn {
            playOrder = Array(0..<queue.count).shuffled()
            if let p = playOrder.firstIndex(of: cur) { orderPos = p } else { orderPos = 0 }
        } else {
            playOrder = Array(0..<queue.count)
            orderPos = playOrder.firstIndex(of: cur) ?? 0
        }
    }

    // MARK: - timer

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.isPlaying {
                let t = self.playOffset + Date().timeIntervalSince(self.playStartDate)
                self.currentTime = min(t, self.duration)
                self.maybeAutomix()
            }
        }
    }

    // MARK: - AVAudioPlayerDelegate (совместимость)

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { self.next(auto: true) }
    }

    // MARK: - remote commands / now playing

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
                if AVAudioSession.InterruptionOptions(rawValue: optsRaw).contains(.shouldResume) {
                    if let e = self.engine, !e.isRunning { try? e.start() }
                    if self.isPlaying || self.current != nil { self.resume() }
                }
            @unknown default:
                break
            }
        }
    }

    private func updateNowPlaying() {
        guard let t = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        let dur = duration
        let elapsed = currentTime.isFinite && currentTime >= 0 ? currentTime : 0
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: t.displayTitle,
            MPMediaItemPropertyArtist: t.displayArtist,
            MPMediaItemPropertyAlbumTitle: t.displayAlbum,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if dur > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = dur
        }
        if let data = t.artwork, let img = UIImage(data: data)?.resized(maxSide: 512), img.size.width > 0 {
            let art = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
            info[MPMediaItemPropertyArtwork] = art
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

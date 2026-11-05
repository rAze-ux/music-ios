import Foundation
import AVFoundation

/// Простая оценка BPM: огибающая энергии + автокорреляция в диапазоне 60–180 BPM.
enum BPMDetector {

    static func analyze(url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let sr = format.sampleRate
        guard sr > 0 else { return nil }
        let maxFrames = AVAudioFramePosition(min(file.length, AVAudioFramePosition(sr * 60)))
        guard maxFrames > sr else { return nil }

        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else { return nil }
        let dec = max(1, Int(sr / 11025))
        let win = 256
        var env: [Float] = []
        var acc: Float = 0
        var accN = 0

        while true {
            let remaining = maxFrames - file.framePosition
            guard remaining > 0 else { break }
            let toRead = AVAudioFrameCount(min(4096, Int(remaining)))
            do {
                try file.read(into: buf, frameCount: toRead)
            } catch { break }
            guard let ch = buf.floatChannelData?[0], buf.frameCount > 0 else { break }
            let n = Int(buf.frameCount)
            var i = 0
            while i < n {
                acc += abs(ch[i])
                accN += 1
                i += dec
                if accN >= win {
                    env.append(acc / Float(accN))
                    acc = 0
                    accN = 0
                }
            }
            if buf.frameCount < toRead { break }
        }
        guard env.count > 64 else { return nil }

        var onset: [Float] = []
        onset.reserveCapacity(env.count)
        for i in 1..<env.count {
            onset.append(max(0, env[i] - env[i - 1]))
        }

        let effRate = sr / Float(dec * win)
        let minLag = Int(effRate * 60.0 / 180.0)
        let maxLag = Int(effRate * 60.0 / 60.0)
        guard minLag > 0, maxLag < onset.count else { return nil }

        var best: Float = 0
        var bestLag = 0
        for lag in minLag...maxLag {
            var s: Float = 0
            let lim = onset.count - lag
            var i = 0
            while i < lim {
                s += onset[i] * onset[i + lag]
                i += 1
            }
            if s > best {
                best = s
                bestLag = lag
            }
        }
        guard bestLag > 0 else { return nil }

        var bpm = 60.0 * Double(effRate) / Double(bestLag)
        while bpm < 70 { bpm *= 2 }
        while bpm > 180 { bpm /= 2 }
        return bpm
    }
}

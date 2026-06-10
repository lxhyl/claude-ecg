import AppKit
import AVFoundation

/// Synthesises the four ECG tones as PCM, writes them to temp `.caf` files, and
/// plays them via `NSSound`.
///
/// `NSSound` is used rather than `AVAudioEngine` so playback survives
/// output-device switches (e.g. when OBS or other recording tools change the
/// system default output mid-session).
final class AudioPlayer {
    /// Length of the flatline alarm tone; `HeartbeatEngine` waits this long
    /// before settling into idle.
    static let alarmDuration: TimeInterval = 2.5

    private let beatSound: NSSound?
    private let arrhythmiaSound: NSSound?
    private let attentionSound: NSSound?
    private let alarmSound: NSSound?

    var muteBeat = false
    var muteAlarm = false

    init() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else {
            NSLog("ECGBar: could not create audio format; sounds disabled")
            beatSound = nil
            arrhythmiaSound = nil
            attentionSound = nil
            alarmSound = nil
            return
        }

        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ECGBar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        func sound(from buffer: AVAudioPCMBuffer?, file: String) -> NSSound? {
            guard let buffer,
                  let url = AudioPlayer.write(buffer, to: dir.appendingPathComponent(file)) else { return nil }
            return NSSound(contentsOf: url, byReference: false)
        }

        beatSound = sound(
            from: AudioPlayer.makeTone(frequency: 880, duration: 0.06, attack: 0.005, decay: 0.03, gain: 0.15, format: format),
            file: "beat.caf")
        arrhythmiaSound = sound(
            from: AudioPlayer.makeTone(frequency: 392, duration: 0.10, attack: 0.005, decay: 0.05, gain: 0.18, format: format),
            file: "arrhythmia.caf")
        attentionSound = sound(
            from: AudioPlayer.makeChime(frequencies: [880, 1318], noteDuration: 0.07, gap: 0.03, gain: 0.16, format: format),
            file: "attention.caf")
        alarmSound = sound(
            from: AudioPlayer.makeTone(frequency: 1_000, duration: Self.alarmDuration, attack: 0.03, decay: 0.2, gain: 0.25, format: format),
            file: "alarm.caf")
    }

    func playBeat()       { play(beatSound,       muted: muteBeat) }
    func playArrhythmia() { play(arrhythmiaSound, muted: muteBeat) }
    func playAttention()  { play(attentionSound,  muted: muteBeat) }
    func playAlarm()      { play(alarmSound,      muted: muteAlarm) }

    private func play(_ sound: NSSound?, muted: Bool) {
        guard !muted, let sound else { return }
        if sound.isPlaying { sound.stop() }
        sound.play()
    }

    private static func write(_ buffer: AVAudioPCMBuffer, to url: URL) -> URL? {
        try? FileManager.default.removeItem(at: url)
        do {
            let file = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
            try file.write(from: buffer)
            return url
        } catch {
            NSLog("ECGBar: write \(url.lastPathComponent) failed: \(error)")
            return nil
        }
    }

    private static func makeTone(frequency: Double, duration: Double, attack: Double, decay: Double, gain: Float, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sr = format.sampleRate
        let totalFrames = Int(duration * sr)
        guard totalFrames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames)),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(totalFrames)
        let attackFrames = max(1, Int(attack * sr))
        let decayFrames = max(1, Int(decay * sr))
        let sustainEnd = totalFrames - decayFrames
        for i in 0..<totalFrames {
            let t = Double(i) / sr
            let s = Float(sin(2.0 * .pi * frequency * t))
            var env: Float = 1.0
            if i < attackFrames {
                env = Float(i) / Float(attackFrames)
            } else if i >= sustainEnd {
                env = Float(totalFrames - i) / Float(decayFrames)
            }
            data[i] = s * env * gain
        }
        return buffer
    }

    private static func makeChime(frequencies: [Double], noteDuration: Double, gap: Double, gain: Float, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sr = format.sampleRate
        let noteFrames = Int(noteDuration * sr)
        let gapFrames = Int(gap * sr)
        let totalFrames = noteFrames * frequencies.count + gapFrames * max(0, frequencies.count - 1)
        guard totalFrames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames)),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(totalFrames)
        let attackFrames = max(1, Int(0.005 * sr))
        let decayFrames = max(1, Int(0.04 * sr))
        for i in 0..<totalFrames { data[i] = 0 }
        var cursor = 0
        for (idx, freq) in frequencies.enumerated() {
            let sustainEnd = noteFrames - decayFrames
            for j in 0..<noteFrames {
                let t = Double(j) / sr
                let s = Float(sin(2.0 * .pi * freq * t))
                var env: Float = 1.0
                if j < attackFrames {
                    env = Float(j) / Float(attackFrames)
                } else if j >= sustainEnd {
                    env = Float(noteFrames - j) / Float(decayFrames)
                }
                data[cursor + j] = s * env * gain
            }
            cursor += noteFrames
            if idx < frequencies.count - 1 { cursor += gapFrames }
        }
        return buffer
    }
}

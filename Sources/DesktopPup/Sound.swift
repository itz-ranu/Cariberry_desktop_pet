import AVFoundation
import Foundation
import QuartzCore

/// Tiny synthesiser so every species has its own voice without shipping audio files.
final class SoundKit {
    static let shared = SoundKit()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    /// A second node for the looping study sound, so it never fights her voice.
    private let bed = AVAudioPlayerNode()
    private var bedBuffers: [Ambience: AVAudioPCMBuffer] = [:]
    private var bedPlaying: Ambience?
    /// Which music/noise she should be playing once it's ready, and which are still rendering.
    private var wanted: Ambience?
    private var rendering: Set<Ambience> = []
    private var beatSeconds: [Ambience: Double] = [:]
    private var bedStartedAt = 0.0
    private let fmt: AVAudioFormat?
    private var cache: [String: AVAudioPCMBuffer] = [:]
    private var started = false

    private init() {
        fmt = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: fmt)
        engine.attach(bed)
        engine.connect(bed, to: engine.mainMixerNode, format: fmt)
        engine.mainMixerNode.outputVolume = 0.45
    }

    private func ensureRunning() {
        guard !started else { return }
        do { try engine.start(); player.play(); started = true } catch { started = false }
    }

    /// Drop a sound of your own into ~/Library/Application Support/DesktopPup/Sounds/ and it
    /// replaces the synthesised one: `purr`, `bell`, `click` or `munch` (.wav, .caf, .aiff,
    /// .m4a or .mp3). Real recordings sound richer than anything generated in code, and
    /// nothing is bundled so you pick exactly the sounds you like.
    private func loadSample(_ name: String) -> AVAudioPCMBuffer? {
        guard let fmt else { return nil }
        let dir = Store.dir.appendingPathComponent("Sounds", isDirectory: true)
        for ext in ["wav", "caf", "aiff", "m4a", "mp3"] {
            let url = dir.appendingPathComponent("\(name).\(ext)")
            guard FileManager.default.fileExists(atPath: url.path),
                  let file = try? AVAudioFile(forReading: url),
                  let src = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(min(file.length, 44_100 * 6))),
                  (try? file.read(into: src)) != nil,
                  let converter = AVAudioConverter(from: file.processingFormat, to: fmt) else { continue }
            let ratio = fmt.sampleRate / file.processingFormat.sampleRate
            guard let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(Double(src.frameLength) * ratio) + 1024) else { continue }
            var fed = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if fed { status.pointee = .endOfStream; return nil }
                fed = true
                status.pointee = .haveData
                return src
            }
            if error == nil, out.frameLength > 0 { return out }
        }
        return nil
    }

    private func play(_ key: String, sample: String? = nil, _ make: () -> [Float]) {
        guard Prefs.sounds else { return }
        guard let fmt else { return }
        ensureRunning()
        guard started else { return }
        let buf: AVAudioPCMBuffer
        if let cached = cache[key] {
            buf = cached
        } else if let sample, let user = loadSample(sample) {
            cache[key] = user
            buf = user
        } else {
            let samples = make()
            guard let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(samples.count)),
                  let ch = b.floatChannelData else { return }
            b.frameLength = AVAudioFrameCount(samples.count)
            for i in 0..<samples.count { ch[0][i] = samples[i] }
            cache[key] = b
            buf = b
        }
        player.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
    }

    // MARK: - Study sounds

    /// Starts, changes or stops the looping background sound. Safe to call as often as
    /// you like: it only does work when something actually changed.
    func ambience(_ kind: Ambience, playing: Bool, volume: Double) {
        bed.volume = Float(max(0, min(1, volume)))
        // the quick-mute button silences the study sound too, not just her voice
        guard playing, kind != .off, Prefs.sounds else {
            wanted = nil
            if bedPlaying != nil { bed.stop(); bedPlaying = nil }
            return
        }
        wanted = kind
        if bedPlaying != nil, bedPlaying != kind { bed.stop(); bedPlaying = nil }
        guard bedPlaying != kind, let fmt else { return }
        ensureRunning()
        guard started else { return }

        if let buffer = bedBuffers[kind] {
            bed.stop()
            bed.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
            bed.play()
            bedStartedAt = CACurrentMediaTime()
            bedPlaying = kind
            return
        }

        // Music takes a moment to compose (about a second), so it's rendered off the main
        // thread and starts the instant it's ready. Nature sounds are quick enough to do inline.
        let make: @Sendable () -> (samples: [Float], beat: Double) = {
            if let track = LoFi.render(kind) { return (track.samples, track.beatSeconds) }
            return (Synth.bed(kind), 0)
        }
        guard !rendering.contains(kind) else { return }
        rendering.insert(kind)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let (samples, beat) = make()
            DispatchQueue.main.async {
                guard let self else { return }
                self.rendering.remove(kind)
                guard let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(samples.count)),
                      let ch = b.floatChannelData else { return }
                b.frameLength = AVAudioFrameCount(samples.count)
                samples.withUnsafeBufferPointer { src in
                    ch[0].update(from: src.baseAddress!, count: samples.count)
                }
                self.bedBuffers[kind] = b
                self.beatSeconds[kind] = beat
                if self.wanted == kind { self.ambience(kind, playing: true, volume: Double(self.bed.volume)) }
            }
        }
    }

    /// Dev helper (`DesktopPup --render-voices dir`): plays every voice once so each is synthesised,
    /// then writes everything cached out as a .wav. The Windows app ships these exact sounds.
    func exportVoices(to dir: URL) {
        Prefs.sounds = true
        for sp in Species.allCases {
            bark(species: sp, times: 2); bark(species: sp, times: 3)
            yip(species: sp); whine(species: sp); munch(species: sp); happy(species: sp)
        }
        bell(); click()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (key, buf) in cache {
            guard let ch = buf.floatChannelData, buf.frameLength > 0 else { continue }
            let samples = Array(UnsafeBufferPointer(start: ch[0], count: Int(buf.frameLength)))
            try? LoFi.wav(samples).write(to: dir.appendingPathComponent("\(key).wav"))
            print(key)
        }
        for kind in Ambience.nature {
            try? LoFi.wav(Synth.bed(kind)).write(to: dir.deletingLastPathComponent().appendingPathComponent("music/\(kind.rawValue).wav"))
            print(kind.rawValue)
        }
    }

    /// Whether the lo-fi band is playing right now, and which beat of its loop we're on, so her
    /// head-bob can land on the very beat she's playing. Nil when no music is on.
    func musicBeat() -> Int? {
        guard let kind = bedPlaying, kind.isMusic, let beat = beatSeconds[kind], beat > 0 else { return nil }
        let t = CACurrentMediaTime() - bedStartedAt - 0.04      // a touch for output latency
        return t < 0 ? nil : Int(t / beat)
    }

    // MARK: - Voices
    // Each call picks a per-voice synthesis path. A dog barks, a cat hisses, a bunny
    // thumps: same emotional beat, a genuinely different sound. Fox and panda share
    // the dog's voice at a different pitch.

    /// The loud "you're distracted" sound.
    func bark(species: Species, times: Int = 2) {
        let k = species.pitch
        switch species.voice {
        case .dog:
            play("bark_dog\(times)_\(k)") {
                var out: [Float] = []
                for i in 0..<times {
                    out += Synth.woof(f0: (470 - Double(i) * 30) * k, drop: 0.46, dur: 0.17, gain: 0.9)
                    out += Synth.silence(0.075)
                }
                return out
            }
        case .cat:
            play("bark_cat") { Synth.hiss(dur: 0.34, gain: 0.55) }
        case .squeak:
            // a stamped hind foot: bunnies and hamsters thump, they don't bark
            play("bark_squeak") {
                var out: [Float] = []
                for _ in 0..<2 {
                    out += Synth.woof(f0: 130, drop: 0.55, dur: 0.1, gain: 0.9, noise: 0.35)
                    out += Synth.silence(0.09)
                }
                return out
            }
        }
    }

    /// A short, upbeat chirp: used for most everyday interactions (petted, played
    /// with, called over).
    func yip(species: Species) {
        let k = species.pitch
        switch species.voice {
        case .dog:
            play("yip_dog_\(k)") { Synth.woof(f0: 820 * k, drop: 0.62, dur: 0.10, gain: 0.65, noise: 0.10) }
        case .cat:
            play("yip_cat") { Synth.meow(f0Start: 700, f0Peak: 1050, f0End: 850, dur: 0.16, gain: 0.55) }
        case .squeak:
            play("yip_squeak") { Synth.meow(f0Start: 1500, f0Peak: 2100, f0End: 1700, dur: 0.08, gain: 0.4) }
        }
    }

    /// The soft, sad "I'm hungry / neglected" sound.
    func whine(species: Species) {
        switch species.voice {
        case .dog:
            play("whine_dog") { Synth.whine() }
        case .cat:
            play("whine_cat") { Synth.meow(f0Start: 520, f0Peak: 760, f0End: 420, dur: 0.55, gain: 0.4) }
        case .squeak:
            play("whine_squeak") { Synth.meow(f0Start: 1300, f0Peak: 1700, f0End: 1000, dur: 0.3, gain: 0.3) }
        }
    }

    /// Eating: a bowl of kibble sounds nothing like a cat's quick, dainty bites.
    func munch(species: Species) {
        switch species.voice {
        case .dog:
            play("munch_dog") {
                var out: [Float] = []
                for i in 0..<4 {
                    out += Synth.crunch(dur: 0.06, gain: 0.5 - Double(i) * 0.05)
                    out += Synth.silence(0.07)
                }
                return out
            }
        case .cat, .squeak:
            let quick = species.voice == .squeak
            play(quick ? "munch_squeak" : "munch_cat") {
                var out: [Float] = []
                for i in 0..<(quick ? 7 : 5) {
                    out += Synth.crunch(dur: 0.04, gain: (0.3 - Double(i) * 0.025), pitch: quick ? 1.9 : 1.6)
                    out += Synth.silence(quick ? 0.04 : 0.055)
                }
                return out
            }
        }
    }

    /// The celebratory sound: entrance greeting, milestones, waking up happy.
    func happy(species: Species) {
        let k = species.pitch
        switch species.voice {
        case .dog:
            play("happy_dog_\(k)") {
                Synth.woof(f0: 620 * k, drop: 1.9, dur: 0.09, gain: 0.45, noise: 0.05)
                + Synth.silence(0.03)
                + Synth.woof(f0: 880 * k, drop: 2.0, dur: 0.10, gain: 0.45, noise: 0.05)
            }
        case .cat:
            play("happy_cat", sample: "purr") { Synth.purr(dur: 0.65, gain: 0.5) }
        case .squeak:
            play("happy_squeak") {
                Synth.meow(f0Start: 1500, f0Peak: 2000, f0End: 1800, dur: 0.07, gain: 0.4)
                + Synth.silence(0.04)
                + Synth.meow(f0Start: 1700, f0Peak: 2300, f0End: 2000, dur: 0.08, gain: 0.4)
            }
        }
    }

    /// A short, satisfying UI-click: the moment her paw lands on the close button
    /// (Settings ▸ Auto-close Reels tabs). Same for every species — this is a click
    /// on a button, not a vocalisation.
    /// A soft two-note bell: finishing a task, earning a badge, a mood check-in.
    func bell() {
        play("bell", sample: "bell") { Synth.bell() }
    }

    func click() {
        play("ui_click", sample: "click") { Synth.click() }
    }
}

private enum Synth {
    static let sr = 44_100.0

    /// A seamless loop of study sound. Each is generated a little long, and the start
    /// is cross-faded with the overhang, so the loop point is inaudible.
    static func bed(_ kind: Ambience) -> [Float] {
        let seconds = kind == .waves ? 18.0 : 12.0
        let n = Int(seconds * sr)
        let fade = Int(1.2 * sr)
        var raw = [Float](repeating: 0, count: n + fade)
        var lp = 0.0, lp2 = 0.0, brown = 0.0
        var droplets: [(Int, Double)] = []
        if kind == .rain {
            for _ in 0..<Int(seconds * 55) { droplets.append((Int.random(in: 0..<(n + fade)), Double.random(in: 0.25...1))) }
        }
        let dropIndex = Dictionary(grouping: droplets, by: { $0.0 })
        var tick = 0.0
        for i in 0..<(n + fade) {
            let t = Double(i) / sr
            let w = Double.random(in: -1...1)
            var s = 0.0
            switch kind {
            case .off, .lofi, .rainy, .cafe, .night: break
            case .brown:
                brown = (brown + 0.02 * w) / 1.02
                s = brown * 3.2
            case .rain:
                lp += (w - lp) * 0.35
                lp2 += (lp - lp2) * 0.05
                s = (lp - lp2) * 0.34                               // the hiss
                brown = (brown + 0.02 * w) / 1.02
                s += brown * 0.9                                    // distant rumble under it
                if let hits = dropIndex[i] { for h in hits { tick = max(tick, h.1) } }
                s += w * tick * 0.5 * (tick > 0.02 ? 1 : 0)         // each drop: a tiny noisy tick
                tick *= 0.9985
            case .waves:
                lp += (w - lp) * 0.025
                let swell = pow(0.5 + 0.5 * sin(2 * .pi * t / 9.0 - 1.2), 1.6)
                let foam = pow(0.5 + 0.5 * sin(2 * .pi * t / 9.0 - 0.6), 3)
                lp2 += (w - lp2) * 0.3
                s = lp * 4.2 * (0.25 + 0.75 * swell) + (lp2 - lp) * 0.12 * foam
            }
            raw[i] = Float(s)
        }
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n { out[i] = raw[i] }
        for i in 0..<fade {
            let k = Float(i) / Float(fade)
            out[i] = raw[i] * k + raw[n + i] * (1 - k)
        }
        let peak = max(0.001, out.map { abs($0) }.max() ?? 1)
        let gain = 0.55 / peak
        return out.map { $0 * gain }
    }

    static func silence(_ dur: Double) -> [Float] {
        [Float](repeating: 0, count: Int(dur * sr))
    }

    /// A single bark syllable: harmonic stack whose pitch drops, plus a noise transient.
    static func woof(f0: Double, drop: Double, dur: Double, gain: Double, noise: Double = 0.22) -> [Float] {
        let n = Int(dur * sr)
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0
        var lp = 0.0
        for i in 0..<n {
            let t = Double(i) / sr
            let u = t / dur
            let f = f0 * pow(drop, u) * (1 + sin(t * 42) * 0.02)
            phase += f / sr
            var s = 0.0
            for k in 1...7 {
                s += sin(2 * .pi * phase * Double(k)) / Double(k)
            }
            s *= 0.55
            s += Double.random(in: -1...1) * noise * exp(-u * 9)
            // soft low-pass gives it a chesty, doggy body
            lp += (s - lp) * 0.42
            let attack = min(1, t / 0.006)
            let env = attack * exp(-u * 4.2) * (1 - u * 0.15)
            out[i] = Float(lp * env * gain * 0.7)
        }
        return out
    }

    /// Rising-falling nasal whine.
    static func whine() -> [Float] {
        let dur = 0.55
        let n = Int(dur * sr)
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0
        var lp = 0.0
        for i in 0..<n {
            let t = Double(i) / sr
            let u = t / dur
            let f = 480 + sin(u * .pi) * 380 + sin(t * 15) * 22
            phase += f / sr
            var s = sin(2 * .pi * phase) * 0.7 + sin(4 * .pi * phase) * 0.22
            s += Double.random(in: -1...1) * 0.03
            lp += (s - lp) * 0.5
            let env = min(1, t / 0.05) * min(1, (dur - t) / 0.18)
            out[i] = Float(lp * env * 0.30)
        }
        return out
    }

    /// Kibble crunch: `pitch` scales the noise's low-pass cutoff, higher = lighter/dryer.
    static func crunch(dur: Double, gain: Double, pitch: Double = 1.0) -> [Float] {
        let n = Int(dur * sr)
        var out = [Float](repeating: 0, count: n)
        var lp = 0.0
        let coeff = min(0.95, 0.75 * pitch)
        for i in 0..<n {
            let u = Double(i) / Double(n)
            let s = Double.random(in: -1...1)
            lp += (s - lp) * coeff
            out[i] = Float(lp * exp(-u * 6) * gain * 0.5)
        }
        return out
    }

    /// Sustained bandpass-ish noise: a cat's hiss. No pitch, just an angry hot texture.
    static func hiss(dur: Double, gain: Double) -> [Float] {
        let n = Int(dur * sr)
        var out = [Float](repeating: 0, count: n)
        var lp1 = 0.0, lp2 = 0.0
        for i in 0..<n {
            let t = Double(i) / sr, u = t / dur
            let s = Double.random(in: -1...1)
            lp1 += (s - lp1) * 0.5      // low-pass...
            lp2 += (lp1 - lp2) * 0.06   // ...minus a slower low-pass = a bandpass-y hiss
            let band = lp1 - lp2
            let attack = min(1, t / 0.02)
            let env = attack * (1 - u * 0.3)
            out[i] = Float(band * env * gain)
        }
        return out
    }

    /// A meow: a formant-ish sweep from `f0Start` up to `f0Peak` and back down to
    /// `f0End`, exactly the "mrrreow" contour a real cat makes.
    static func meow(f0Start: Double, f0Peak: Double, f0End: Double, dur: Double, gain: Double) -> [Float] {
        let n = Int(dur * sr)
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0, lp = 0.0
        for i in 0..<n {
            let t = Double(i) / sr
            let u = t / dur
            // rises in the first third, eases down for the rest: cats front-load the pitch
            let f: Double = u < 0.35
                ? f0Start + (f0Peak - f0Start) * (u / 0.35)
                : f0Peak + (f0End - f0Peak) * ((u - 0.35) / 0.65)
            phase += f / sr
            var s = sin(2 * .pi * phase) + sin(4 * .pi * phase) * 0.45 + sin(6 * .pi * phase) * 0.15
            s += Double.random(in: -1...1) * 0.02
            lp += (s - lp) * 0.6
            let env = min(1, t / 0.03) * min(1, (dur - t) / 0.12)
            out[i] = Float(lp * env * gain * 0.5)
        }
        return out
    }

    /// A soft glassy bell: a few inharmonic partials that decay at different speeds, which is
    /// what makes a struck bell sound like a bell and not a beep.
    static func bell() -> [Float] {
        let dur = 0.9
        let n = Int(dur * sr)
        var out = [Float](repeating: 0, count: n)
        let partials: [(Double, Double, Double)] = [(1568, 1.0, 5.5), (2352, 0.55, 7.5), (3136, 0.3, 9), (4220, 0.15, 12)]
        for i in 0..<n {
            let t = Double(i) / sr
            var s = 0.0
            for (f, amp, decay) in partials { s += sin(2 * .pi * f * t) * amp * exp(-t * decay) }
            let attack = min(1, t / 0.004)
            out[i] = Float(s * attack * 0.22)
        }
        return out
    }

    /// A crisp little "tock": a fast-decaying high tone plus a touch of noise for
    /// texture, the same shape a UI click/tap sound effect usually has.
    static func click() -> [Float] {
        let dur = 0.07
        let n = Int(dur * sr)
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / sr
            let u = t / dur
            phase += 1350.0 / sr
            var s = sin(2 * .pi * phase) * 0.7
            s += Double.random(in: -1...1) * 0.15 * exp(-u * 14)
            let env = exp(-u * 24)
            out[i] = Float(s * env * 0.55)
        }
        return out
    }

    /// A warm, buzzy purr: a low tone whose amplitude is modulated ~28 times a
    /// second, the same trick a real purr uses (laryngeal muscle twitching).
    static func purr(dur: Double, gain: Double) -> [Float] {
        let n = Int(dur * sr)
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0, modPhase = 0.0
        for i in 0..<n {
            let t = Double(i) / sr
            phase += 95.0 / sr
            modPhase += 27.0 / sr
            let carrier = sin(2 * .pi * phase) + sin(4 * .pi * phase) * 0.3
            let mod = 0.55 + 0.45 * sin(2 * .pi * modPhase)
            let attack = min(1, t / 0.08)
            let release = min(1, (dur - t) / 0.15)
            out[i] = Float(carrier * mod * attack * release * gain * 0.5)
        }
        return out
    }

}

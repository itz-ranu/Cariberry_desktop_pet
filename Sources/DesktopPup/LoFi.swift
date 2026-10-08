import Foundation

/// A tiny lo-fi band that lives in code: a Rhodes-style piano playing seventh chords, a
/// music-box melody, a soft bass, swung drums, vinyl crackle and a little room reverb. Each
/// station is a 16 bar loop (about a minute) rendered once, in the background, the first time
/// it's played. Nothing is downloaded and no audio files ship with her.
///
/// The loop is exactly 64 beats long, so the pet can bop to the very beat she's playing.
/// Everything wraps around the end of the buffer (a note's tail, the reverb, the filters),
/// so the loop point is inaudible.
enum LoFi {
    struct Track {
        var samples: [Float]
        /// How long one beat lasts, in seconds, so her head-bob can lock onto it.
        var beatSeconds: Double
    }

    private struct Plan {
        var bpm: Double
        var swing: Double          // how late the off-beat 16ths land, as a fraction of a 16th
        var chords: [[Int]]        // four voicings (MIDI notes), then a turnaround chord
        var bass: [Int]            // a bass note for each of those five chords
        var scale: [Int]           // notes the melody may use
        var rain = 0.0             // 0...1
        var pad = 0.0              // 0...1, a slow, glowing chord underneath
        var snare = 1.0            // 0...1
        var hats = 1.0             // 0...1
        var melody = 0.65          // chance of a melody phrase in a bar
        var warmth = 0.22          // one-pole low-pass on the keys: lower = more muffled
        var seed: UInt64
    }

    private static let sr = 44_100.0
    private static let bars = 16

    private static func plan(for kind: Ambience) -> Plan? {
        switch kind {
        case .lofi:     // IV - iii - ii - I, the classic late-night loop (C major)
            return Plan(bpm: 74, swing: 0.28,
                        chords: [[53, 57, 60, 64], [52, 55, 59, 62], [50, 53, 57, 60, 64], [48, 55, 59, 62, 64], [53, 59, 64, 67]],
                        bass: [41, 40, 38, 36, 43],
                        scale: [72, 74, 76, 79, 81, 84, 86], seed: 11)
        case .rainy:    // a minor mood with rain on the window
            return Plan(bpm: 68, swing: 0.24,
                        chords: [[57, 60, 64, 67, 71], [53, 57, 60, 64], [48, 55, 59, 64], [55, 59, 62, 64], [52, 56, 59, 62]],
                        bass: [45, 41, 48, 43, 40],
                        scale: [69, 72, 74, 76, 79, 81, 84], rain: 0.8, pad: 0.35, snare: 0.8, hats: 0.7, melody: 0.55, warmth: 0.18, seed: 23)
        case .cafe:     // a swung ii - V - I - vi, like a corner coffee shop
            return Plan(bpm: 84, swing: 0.4,
                        chords: [[53, 57, 60, 64], [53, 59, 62, 64], [52, 55, 59, 62], [55, 59, 60, 64], [50, 56, 60, 65]],
                        bass: [38, 43, 48, 45, 44],
                        scale: [72, 74, 76, 79, 81, 83, 84], snare: 0.55, hats: 1.0, melody: 0.8, warmth: 0.26, seed: 37)
        case .night:    // slow and glowy: for the late shift
            return Plan(bpm: 62, swing: 0.2,
                        chords: [[51, 55, 58, 62], [48, 51, 55, 58, 62], [56, 60, 63, 67], [53, 58, 62, 65], [55, 58, 62, 65]],
                        bass: [39, 36, 44, 46, 43],
                        scale: [75, 77, 79, 82, 84, 86, 89], pad: 0.8, snare: 0.35, hats: 0.5, melody: 0.45, warmth: 0.15, seed: 51)
        default:
            return nil
        }
    }

    // MARK: Rendering

    static func render(_ kind: Ambience) -> Track? {
        guard let p = plan(for: kind) else { return nil }
        let beatSamples = sr * 60 / p.bpm
        let n = Int((beatSamples * Double(bars * 4)).rounded())
        let beat = Double(n) / Double(bars * 4)
        let stepLen = beat / 4
        let barLen = stepLen * 16
        let seconds = Double(n) / sr
        var rng = RNG(seed: p.seed)

        var keys = Bus(n), mel = Bus(n), bass = Bus(n), drums = Bus(n), pad = Bus(n)

        // when a 16th step lands, with swing on the off-beats and a little human wobble
        func at(_ bar: Int, _ step: Int, jitter: Double = 0.006) -> Int {
            var t = (Double(bar * 16 + step)) * stepLen
            if step % 2 == 1 { t += p.swing * stepLen }
            return Int(t + (rng.unit() - 0.5) * 2 * jitter * sr)
        }
        func hz(_ m: Int) -> Double { 440 * pow(2, (Double(m) - 69) / 12) }

        let compPatterns: [[Int]] = [[0, 6, 10], [0, 7, 11], [0, 6], [0, 10, 14], [0, 5, 10]]

        for bar in 0..<bars {
            let phrase = bar / 4
            let slot = bar % 4
            // the last bar of the last phrase turns around onto a different chord
            let ci = (phrase == 3 && slot == 3) ? 4 : slot
            let chord = p.chords[ci]
            let root = p.bass[ci]
            let barStart = Int(Double(bar) * barLen)

            // keys: a strummed chord, then softer re-hits that fall off the beat
            let pattern = compPatterns[(bar + phrase * 2 + Int(p.seed)) % compPatterns.count]
            for (hit, step) in pattern.enumerated() {
                let vel = (hit == 0 ? 0.95 : 0.5 + rng.unit() * 0.15) * (phrase == 0 ? 0.85 : 1)
                let start = at(bar, step)
                for (i, m) in chord.enumerated() {
                    rhodes(&keys, start: start + i * 520, hz: hz(m), vel: vel * (0.8 + rng.unit() * 0.25),
                           len: hit == 0 ? 2.6 : 1.2, decay: hit == 0 ? 1.5 : 2.6)
                }
            }

            // a slow pad that glows underneath on the dreamier stations
            if p.pad > 0 {
                for m in chord { padNote(&pad, start: barStart, hz: hz(m - 12), len: barLen / sr * 1.15, gain: p.pad) }
            }

            // bass: root on the one, a lazy answer later in the bar
            subBass(&bass, start: at(bar, 0, jitter: 0.003), hz: hz(root), vel: 0.95, len: beat / sr * 1.6)
            let answer = [10, 7, 11, 10][slot]
            subBass(&bass, start: at(bar, answer, jitter: 0.004), hz: hz(slot == 3 ? root + 7 : root), vel: 0.6, len: beat / sr * 0.9)
            if phrase >= 2 && slot % 2 == 1 { subBass(&bass, start: at(bar, 14), hz: hz(root + 12), vel: 0.35, len: 0.3) }

            // drums: a lighter intro phrase, then the full groove, a fill at the very end
            let lighter = phrase == 0
            kick(&drums, start: at(bar, 0, jitter: 0.003), vel: 0.95)
            kick(&drums, start: at(bar, slot % 2 == 0 ? 10 : 7), vel: 0.7)
            if !lighter || bar >= 2 {
                for s in [4, 12] { snare(&drums, start: at(bar, s, jitter: 0.008), vel: 0.62 * p.snare, rng: &rng) }
            }
            if p.hats > 0 {
                for s in stride(from: 0, to: 16, by: 2) {
                    let accent = s % 4 == 0 ? 1.0 : 0.55
                    hat(&drums, start: at(bar, s), vel: accent * 0.38 * p.hats * (0.8 + rng.unit() * 0.3), open: s == 14 && slot % 2 == 1, rng: &rng)
                }
                if bar == bars - 1 { for s in [13, 15] { hat(&drums, start: at(bar, s), vel: 0.3 * p.hats, open: false, rng: &rng) } }
            }

            // melody: a few music-box notes that wander around the scale
            let chance = phrase == 3 && slot >= 2 ? p.melody * 0.4 : p.melody
            if rng.unit() < chance {
                var idx = Int(rng.unit() * Double(p.scale.count))
                let count = 1 + Int(rng.unit() * 3.4)
                let steps = [0, 2, 3, 6, 8, 10, 11, 12].shuffled(using: &rng).prefix(count).sorted()
                for s in steps {
                    idx = min(p.scale.count - 1, max(0, idx + Int(rng.unit() * 3) - 1))
                    let f = hz(p.scale[idx])
                    let vel = 0.45 + rng.unit() * 0.3
                    let start = at(bar, s)
                    musicBox(&mel, start: start, hz: f, vel: vel)
                    musicBox(&mel, start: start + Int(stepLen * 3), hz: f, vel: vel * 0.32)      // an echo,
                    musicBox(&mel, start: start + Int(stepLen * 6), hz: f, vel: vel * 0.12)      // and its echo
                }
            }
        }

        // the keys get a warm low-pass and a slow wobble, like a tape that's seen some things
        lowpass(&keys.buf, a: p.warmth)
        lowpass(&mel.buf, a: 0.5)
        lowpass(&bass.buf, a: 0.12)
        lowpass(&drums.buf, a: 0.38)
        let wobbleHz = (3.4 * seconds).rounded() / seconds
        for i in 0..<n {
            let t = Double(i) / sr
            keys.buf[i] *= 0.9 + 0.1 * sin(2 * .pi * wobbleHz * t)
        }

        // a bit of room around everything melodic
        var send = [Double](repeating: 0, count: n)
        for i in 0..<n { send[i] = keys.buf[i] * 0.55 + mel.buf[i] * 0.8 + pad.buf[i] * 0.5 }
        let room = reverb(send)

        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            out[i] = keys.buf[i] * 0.85 + mel.buf[i] * 0.55 + pad.buf[i] * 0.7 + bass.buf[i] * 0.8 + drums.buf[i] * 0.78 + room[i] * 0.5
        }

        // the rain on the window and the record under the needle
        var lp = 0.0, lp2 = 0.0
        for i in 0..<n {
            let w = rng.unit() * 2 - 1
            if p.rain > 0 {
                lp += (w - lp) * 0.35
                lp2 += (lp - lp2) * 0.05
                out[i] += (lp - lp2) * 0.085 * p.rain
            }
        }
        if p.rain > 0 {
            for _ in 0..<Int(seconds * 45) {
                let start = Int(rng.unit() * Double(n)), amp = 0.01 + rng.unit() * 0.03
                for k in 0..<260 { out[(start + k) % n] += (rng.unit() * 2 - 1) * amp * exp(-Double(k) / 45) * p.rain }
            }
        }
        var hiss = 0.0
        for i in 0..<n {
            hiss += ((rng.unit() * 2 - 1) - hiss) * 0.04
            out[i] += hiss * 0.006
        }
        for _ in 0..<Int(seconds * 7) {       // the pops and crackle
            let start = Int(rng.unit() * Double(n)), amp = 0.006 + pow(rng.unit(), 3) * 0.05
            for k in 0..<90 { out[(start + k) % n] += (rng.unit() * 2 - 1) * amp * exp(-Double(k) / 14) }
        }

        // level it out to a comfortable listening volume, and round off any peaks
        let rms = max(0.0001, (out.reduce(0) { $0 + $1 * $1 } / Double(n)).squareRoot())
        let gain = 0.11 / rms
        let samples = out.map { Float(tanh($0 * gain) * 0.92) }
        return Track(samples: samples, beatSeconds: beat / sr)
    }

    // MARK: Instruments

    private struct Bus {
        var buf: [Double]
        let n: Int
        init(_ n: Int) { self.n = n; buf = [Double](repeating: 0, count: n) }
        @inline(__always) mutating func add(_ i: Int, _ v: Double) {
            buf[((i % n) + n) % n] += v
        }
    }

    /// An electric-piano tine: a clear note, a brighter overtone that fades fast, a hint of bell.
    private static func rhodes(_ b: inout Bus, start: Int, hz f: Double, vel: Double, len: Double, decay: Double) {
        let count = Int(len * sr)
        let w = 2 * Double.pi * f / sr
        for k in 0..<count {
            let t = Double(k) / sr
            let attack = 1 - exp(-t * 520)
            let release = min(1, (len - t) / 0.25)
            let env = attack * exp(-t * decay) * release
            let ph = w * Double(k)
            let s = sin(ph) + 0.34 * sin(2 * ph) * exp(-t * 6) + 0.10 * sin(5.04 * ph) * exp(-t * 18)
            b.add(start + k, s * env * vel * 0.085)
        }
    }

    private static func musicBox(_ b: inout Bus, start: Int, hz f: Double, vel: Double) {
        let count = Int(1.8 * sr)
        let w = 2 * Double.pi * f / sr
        for k in 0..<count {
            let t = Double(k) / sr
            let env = (1 - exp(-t * 900)) * exp(-t * 2.6)
            let ph = w * Double(k)
            let s = sin(ph) + 0.4 * sin(2 * ph) * exp(-t * 9) + 0.12 * sin(3 * ph) * exp(-t * 14)
            b.add(start + k, s * env * vel * 0.07)
        }
    }

    private static func padNote(_ b: inout Bus, start: Int, hz f: Double, len: Double, gain: Double) {
        let count = Int(len * sr)
        let w = 2 * Double.pi * f / sr
        for k in 0..<count {
            let t = Double(k) / sr
            let env = min(1, t / 0.9) * min(1, (len - t) / 0.7)
            let ph = w * Double(k)
            b.add(start + k, (sin(ph) + 0.5 * sin(ph * 1.003) + 0.25 * sin(2 * ph)) * env * gain * 0.03)
        }
    }

    private static func subBass(_ b: inout Bus, start: Int, hz f: Double, vel: Double, len: Double) {
        let count = Int(len * sr)
        let w = 2 * Double.pi * f / sr
        for k in 0..<count {
            let t = Double(k) / sr
            let env = (1 - exp(-t * 300)) * exp(-t * 2.4) * min(1, (len - t) / 0.12)
            let ph = w * Double(k)
            b.add(start + k, (sin(ph) + 0.28 * sin(2 * ph)) * env * vel * 0.30)
        }
    }

    private static func kick(_ b: inout Bus, start: Int, vel: Double) {
        let count = Int(0.34 * sr)
        var ph = 0.0
        for k in 0..<count {
            let t = Double(k) / sr
            ph += 2 * Double.pi * (46 + 92 * exp(-t * 26)) / sr
            let click = k < 90 ? (Double(k % 7) / 7 - 0.5) * (1 - Double(k) / 90) * 0.25 : 0
            b.add(start + k, (sin(ph) * exp(-t * 8.5) + click) * vel * 0.62)
        }
    }

    private static func snare(_ b: inout Bus, start: Int, vel: Double, rng: inout RNG) {
        let count = Int(0.28 * sr)
        var lp = 0.0
        for k in 0..<count {
            let t = Double(k) / sr
            let w = rng.unit() * 2 - 1
            lp += (w - lp) * 0.55
            let body = sin(2 * .pi * 185 * t) * exp(-t * 24) * 0.55
            let snap = (w - lp) * exp(-t * 15) * 0.9
            b.add(start + k, (body + snap) * vel * 0.5)
        }
    }

    private static func hat(_ b: inout Bus, start: Int, vel: Double, open: Bool, rng: inout RNG) {
        let count = Int((open ? 0.16 : 0.05) * sr)
        var prev = 0.0
        for k in 0..<count {
            let t = Double(k) / sr
            let w = rng.unit() * 2 - 1
            let hp = w - prev
            prev = w
            b.add(start + k, hp * exp(-t * (open ? 22 : 80)) * vel * 0.3)
        }
    }

    // MARK: Effects

    /// One-pole low-pass, run twice around the loop so its state at the seam matches.
    private static func lowpass(_ x: inout [Double], a: Double) {
        var y = x.last ?? 0
        for pass in 0..<2 {
            for i in 0..<x.count {
                y += a * (x[i] - y)
                if pass == 1 { x[i] = y }
            }
        }
    }

    /// A small Schroeder room: four combs and two all-passes. Run twice around so its tail
    /// carries over the loop seam.
    private static func reverb(_ x: [Double]) -> [Double] {
        let n = x.count
        let combs: [(Int, Double)] = [(1557, 0.80), (1617, 0.79), (1491, 0.81), (1422, 0.78), (1277, 0.77)]
        var out = [Double](repeating: 0, count: n)
        var bufs = combs.map { [Double](repeating: 0, count: $0.0) }
        var pos = [Int](repeating: 0, count: combs.count)
        var damp = [Double](repeating: 0, count: combs.count)
        var apBufs = [[Double](repeating: 0, count: 225), [Double](repeating: 0, count: 556)]
        var apPos = [0, 0]
        for pass in 0..<2 {
            for i in 0..<n {
                var s = 0.0
                for c in 0..<combs.count {
                    let delayed = bufs[c][pos[c]]
                    damp[c] += (delayed - damp[c]) * 0.45
                    bufs[c][pos[c]] = x[i] * 0.2 + damp[c] * combs[c].1
                    pos[c] = (pos[c] + 1) % combs[c].0
                    s += delayed
                }
                for a in 0..<2 {
                    let d = apBufs[a][apPos[a]]
                    let v = s + d * 0.5
                    apBufs[a][apPos[a]] = v
                    s = d - v * 0.5
                    apPos[a] = (apPos[a] + 1) % apBufs[a].count
                }
                if pass == 1 { out[i] = s * 0.3 }
            }
        }
        return out
    }

    /// 16-bit mono WAV bytes, for the `--render-lofi` dev helper.
    static func wav(_ samples: [Float]) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + samples.count * 2)); d.append("WAVEfmt ".data(using: .ascii)!)
        u32(16); u16(1); u16(1); u32(44_100); u32(88_200); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(UInt32(samples.count * 2))
        for s in samples { u16(UInt16(bitPattern: Int16(max(-1, min(1, s)) * 32_000))) }
        return d
    }

    // MARK: Random

    /// A tiny seeded generator, so a station always plays the same song.
    struct RNG: RandomNumberGenerator {
        var s: UInt64
        init(seed: UInt64) { s = seed &* 0x9E3779B97F4A7C15 }
        mutating func next() -> UInt64 {
            s &+= 0x9E3779B97F4A7C15
            var z = s
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        /// 0..<1
        mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    }
}

// Listens to whatever your PC is playing and calls `onBeat` on each beat, so she can bop her head.
// The Mac app does this with ScreenCaptureKit's audio-only capture; here it is Chromium's system-audio
// loopback (Windows needs no permission for it). It's strictly opt-in (Settings > Bop to my music) and only
// looks at loudness: no audio is stored or sent anywhere. The beat finder is the Mac's: a sudden jump above
// the last second or so of loudness.

const FFT = 1024
const WINDOW = 48           // about the last second of readings
const MIN_READINGS = 24

export class BeatListener {
  constructor({ cari, onBeat, onFailure }) {
    this.cari = cari; this.onBeat = onBeat; this.onFailure = onFailure
    this.running = false; this.stream = null; this.ctx = null; this.timer = null
    this.recent = []; this.lastBeat = 0
  }

  async start() {
    if (this.running) return
    this.running = true
    try {
      // the app answers this request with the screen's system audio (main.js); the picture is thrown away
      const stream = await navigator.mediaDevices.getDisplayMedia({ audio: true, video: { width: 2, height: 2, frameRate: 1 } })
      stream.getVideoTracks().forEach((t) => { t.stop(); stream.removeTrack(t) })
      if (!stream.getAudioTracks().length) throw new Error('no audio')
      if (!this.running) { stream.getTracks().forEach((t) => t.stop()); return }
      this.stream = stream
      this.ctx = new AudioContext()
      const src = this.ctx.createMediaStreamSource(stream)
      const an = this.ctx.createAnalyser(); an.fftSize = FFT
      src.connect(an)                          // not connected onward: it must never be heard again
      const buf = new Float32Array(FFT)
      this.recent = []
      this.timer = setInterval(() => { an.getFloatTimeDomainData(buf); this.feed(rms(buf)) }, 23)
    } catch (e) {
      this.running = false
      this.cleanup()
      this.onFailure?.('couldn\'t listen to your music: Windows wouldn\'t share the sound with me')
    }
  }

  stop() { this.running = false; this.cleanup() }

  cleanup() {
    clearInterval(this.timer); this.timer = null
    this.stream?.getTracks().forEach((t) => t.stop()); this.stream = null
    this.ctx?.close().catch(() => {}); this.ctx = null
  }

  feed(energy) {
    this.recent.push(energy)
    if (this.recent.length > WINDOW) this.recent.shift()
    if (this.recent.length < MIN_READINGS) return
    const avg = this.recent.reduce((a, b) => a + b, 0) / this.recent.length
    const now = performance.now() / 1000
    if (avg > 0.004 && energy > avg * 1.45 + 0.004 && now - this.lastBeat > 0.27) {
      this.lastBeat = now
      this.onBeat?.(Math.min(1, (energy - avg) / Math.max(avg, 0.01)))
    }
  }
}

export function rms(samples) {
  let sum = 0
  for (let i = 0; i < samples.length; i++) sum += samples[i] * samples[i]
  return Math.sqrt(sum / samples.length)
}

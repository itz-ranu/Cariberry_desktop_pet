// Her voice and the lo-fi radio. The sounds are the very ones the Mac app synthesises (they were
// rendered from its code), played through the Web Audio API: a short voice for each feeling per
// animal, plus looping study music and nature beds.
import { speciesInfo } from '../shared/data.js'
import { isMusic } from './ambience.js'

const MASTER = 0.45
// how long one beat of each station lasts, so her head-bob lands on the music
const BEAT = { lofi: 0.8108106575963718, rainy: 0.8823529620181406, cafe: 0.7142857142857143, night: 0.9677419926303855 }
const ASSET = location.protocol === 'cari:' ? 'cari://app/assets' : '/assets'
// Drop purr / bell / click (.wav .mp3 .m4a .ogg .flac) into %APPDATA%\Cariberry\Sounds and they replace hers, as on the Mac.
const OWN = location.protocol === 'cari:' ? 'cari://app/userdata/Sounds' : null
const OWN_EXT = ['wav', 'mp3', 'm4a', 'ogg', 'flac']

export class Sound {
  constructor(getEnabled) {
    this.enabled = getEnabled
    this.ctx = new AudioContext()
    this.ctx.suspend()                       // an idle audio device costs power: it only runs while something plays
    this.master = this.ctx.createGain(); this.master.gain.value = MASTER; this.master.connect(this.ctx.destination)
    this.bedGain = this.ctx.createGain(); this.bedGain.connect(this.master)
    this.buffers = new Map(); this.loading = new Map()
    this.bed = null; this.bedKind = null; this.bedStart = 0; this.wanted = null
    /** When her own voice last played, so the beat finder never mistakes a bark for music. */
    this.lastVoiceAt = 0
  }

  load(path) {
    if (this.buffers.has(path)) return Promise.resolve(this.buffers.get(path))
    if (!this.loading.has(path)) {
      this.loading.set(path, fetch(`${ASSET}/${path}.wav`).then((r) => r.arrayBuffer()).then((b) => this.ctx.decodeAudioData(b))
        .then((buf) => { this.buffers.set(path, buf); return buf }).catch(() => null))
    }
    return this.loading.get(path)
  }

  _wake() { clearTimeout(this._sleepTimer); if (this.ctx.state !== 'running') this.ctx.resume() }
  _maybeSleep() {
    clearTimeout(this._sleepTimer)
    this._sleepTimer = setTimeout(() => { if (!this.bed) this.ctx.suspend() }, 2500)
  }

  /** Your own recording of `name`, if you've put one in the Sounds folder (cached, so the folder is only asked once). */
  loadOwn(name) {
    if (!OWN) return Promise.resolve(null)
    const key = `own/${name}`
    if (!this.loading.has(key)) {
      this.loading.set(key, (async () => {
        for (const ext of OWN_EXT) {
          try {
            const r = await fetch(`${OWN}/${name}.${ext}`)
            if (r.ok) return await this.ctx.decodeAudioData(await r.arrayBuffer())
          } catch { /* not that one */ }
        }
        return null
      })())
    }
    return this.loading.get(key)
  }

  async play(name, own = null) {
    if (!this.enabled()) return
    const buf = (own && (await this.loadOwn(own))) || (await this.load(`sounds/${name}`))
    if (!buf || !this.enabled()) return
    this._wake()
    this.lastVoiceAt = performance.now()
    const src = this.ctx.createBufferSource()
    src.buffer = buf; src.connect(this.master); src.onended = () => this._maybeSleep(); src.start()
  }

  // the voices: the same per-species choices as SoundKit.swift
  _k(species) { const p = speciesInfo(species).pitch; return Number.isInteger(p) ? p.toFixed(1) : String(p) }
  bark(species, times = 2) {
    const v = speciesInfo(species).voice
    this.play(v === 'dog' ? `bark_dog${times}_${this._k(species)}` : v === 'cat' ? 'bark_cat' : 'bark_squeak')
  }
  yip(species) { const v = speciesInfo(species).voice; this.play(v === 'dog' ? `yip_dog_${this._k(species)}` : `yip_${v}`) }
  whine(species) { this.play(`whine_${speciesInfo(species).voice}`) }
  munch(species) { this.play(`munch_${speciesInfo(species).voice}`) }
  happy(species) { const v = speciesInfo(species).voice; this.play(v === 'dog' ? `happy_dog_${this._k(species)}` : `happy_${v}`, v === 'cat' ? 'purr' : null) }
  bell() { this.play('bell', 'bell') }
  click() { this.play('ui_click', 'click') }

  // study sound: starts, changes or stops the looping bed. Safe to call as often as you like.
  async ambience(kind, playing, volume) {
    this.bedGain.gain.value = Math.max(0, Math.min(1, volume))
    if (!playing || kind === 'off') {
      this.wanted = null
      this._stopBed()
      this._maybeSleep()
      return
    }
    this.wanted = kind
    if (this.bedKind === kind && this.bed) return
    this._stopBed()
    this._wake()
    const buf = await this.load(`music/${kind}`)
    if (!buf || this.wanted !== kind || this.bed) return
    const src = this.ctx.createBufferSource()
    src.buffer = buf; src.loop = true; src.connect(this.bedGain)
    src.start()
    this.bed = src; this.bedKind = kind; this.bedStart = this.ctx.currentTime
  }
  _stopBed() { try { this.bed?.stop() } catch {} this.bed = null; this.bedKind = null }

  /** Which beat of the lo-fi loop we're on, or null when no music is playing. */
  musicBeat() {
    if (!this.bed || !isMusic(this.bedKind)) return null
    const t = this.ctx.currentTime - this.bedStart - (this.ctx.outputLatency || 0.04)
    return t < 0 ? null : Math.floor(t / BEAT[this.bedKind])
  }
}

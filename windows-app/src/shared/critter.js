// One renderer for every animal, ported line for line from Critter.swift. A species only decides
// its ears, tail, nose and a few face markings; the skeleton, the animation and the expressions
// are shared. Design space is 200 x 168 with the paws on y = 152, facing right; `Design.lift`
// extra rows of headroom sit above that for tall ears and hops.
import {
  Color, rgb, white, black, P, ZERO, col, linG, radG, Path, Ctx, stroke,
  ovalPath, capsulePath, rectPath, roundedRectPath, heartPath, softBlob,
} from './gfx.js'
import { Design, Fur, coatsOf, outfitOf } from './data.js'

const { sin, cos, abs, max, min, pow, PI } = Math
const frac = (v) => v - Math.floor(v)           // Swift's `truncatingRemainder(dividingBy: 1)` for positive v
const mod = (a, b) => a - Math.trunc(a / b) * b  // truncatingRemainder
const clamp01 = (v) => max(0, min(1, v))

export const defaultPose = () => ({
  emotion: 'neutral', phase: 0, gait: 0, walk: 0, run: 0, facing: 1, squash: 0, dangling: false,
  look: { dx: 0, dy: 0 }, sit: 0, sleep: 0, petting: 0, stretch: 0, sniff: 0, groom: 0, scratch: 0,
  dance: 0, wave: 0, bop: 0, collarTier: 0, tapping: false, tapPhase: 0, outfit: null, perched: false,
  prop: 'none', propAmt: 0,
})

/** Eases up to a held peak (the paw on the button), then back down. */
export function tapRaise(phase) {
  if (phase < 0.4) { const t = phase / 0.4; return 1 - (1 - t) * (1 - t) }
  if (phase < 0.6) return 1
  const t = (phase - 0.6) / 0.4
  return max(0, 1 - t * t)
}

const COLLAR = [null, rgb(0.80, 0.52, 0.34), rgb(0.72, 0.75, 0.82), rgb(0.95, 0.78, 0.36), rgb(0.62, 0.72, 0.95), rgb(0.86, 0.55, 0.86)]
export const collarColor = (tier) => COLLAR[min(5, max(1, tier))]

/** The collar she earns by levelling up: a band across the chest with a little tag. */
export function drawCollar(ctx, tier, at, width) {
  if (tier <= 0) return
  const colour = collarColor(tier)
  const band = new Path()
  band.move(at.x - width / 2, at.y - 3)
  band.quad(at.x + width / 2, at.y - 5, at.x, at.y + 7)
  ctx.stroke(band, linG([colour.opacity(0.75), colour], P(at.x - width / 2, at.y), P(at.x + width / 2, at.y)), stroke(7, { cap: 'round' }))
  const tagC = P(at.x + 2, at.y + 9)
  ctx.fill(ovalPath(tagC.x, tagC.y, 11, 11), col(colour))
  ctx.fill(ovalPath(tagC.x - 2, tagC.y - 2, 4.5, 4), col(white.opacity(0.65)))
}

export function starPathOf(r) {
  const p = new Path()
  for (let i = 0; i < 10; i++) {
    const a = (i * PI) / 5 - PI / 2
    const rr = i % 2 === 0 ? r : r * 0.45
    const x = cos(a) * rr, y = sin(a) * rr
    if (i === 0) p.move(x, y); else p.line(x, y)
  }
  return p.close()
}

// ---------------------------------------------------------------- anatomy

const G = {
  bodyC: P(76, 128), bodyW: 64, bodyH: 46,
  headC: P(116, 70), neck: P(110, 116),
  eyeL: P(90, 82), eyeR: P(142, 80), muzzleC: P(118, 100), noseC: P(118, 94),
  hipY: 133, ground: Design.ground, legsX: [46, 60, 84, 98], rear: P(46, 150), tailBase: P(41, 122),
}
const eyeInk = rgb(0.20, 0.17, 0.25)
const nosePink = rgb(0.93, 0.56, 0.64)

const HEAD_W = { cat: 126, dog: 124, bunny: 112, fox: 120, panda: 126, hamster: 134, axolotl: 134, capybara: 130 }
const HEAD_H = { cat: 102, dog: 102, bunny: 98, fox: 94, panda: 104, hamster: 108, axolotl: 94, capybara: 90 }
const IRIS = {
  dog: rgb(0.86, 0.52, 0.30), bunny: rgb(0.95, 0.45, 0.58), fox: rgb(1.0, 0.70, 0.22), panda: rgb(0.50, 0.62, 0.85),
  hamster: rgb(0.78, 0.52, 0.40), axolotl: rgb(0.90, 0.50, 0.80), capybara: rgb(0.70, 0.46, 0.30),
}
const TAILS = {
  cat: { n: 24, len: 3.0, r0: 6.6, r1: 3.8, base: 212, curl: 120, bushy: 0 },
  dog: { n: 18, len: 2.7, r0: 7.0, r1: 5.2, base: 222, curl: 120, bushy: 0.5 },
  fox: { n: 22, len: 3.1, r0: 6.0, r1: 3.5, base: 232, curl: 38, bushy: 10 },
  axolotl: { n: 20, len: 2.05, r0: 6.4, r1: 3.0, base: 214, curl: 34, bushy: 6 },
}

/** A point `t` of the way from one coat tone to another (light, mid, shade, belly, patch). */
function blendCoat(coat, i, j, t) {
  const a = coat.raw[i], b = coat.raw[j]
  return rgb(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)
}

export class Critter {
  constructor(species, coatIndex, pose) {
    this.species = species
    const coats = coatsOf(species)
    this.coat = coats[min(max(coatIndex, 0), coats.length - 1)]
    this.p = pose
    this.outfit = pose.outfit
    this.T = pose.phase
    this.headW = HEAD_W[species]
    this.headH = HEAD_H[species]
    this.rim = this.coat.shade.opacity(0.55)
  }

  /** Each animal gets its own silhouette: chubby-cheeked hamster, flat wide axolotl, loaf-shaped capybara. */
  get headPath() {
    const { x, y } = G.headC, w = this.headW, h = this.headH
    switch (this.species) {
      case 'cat': return softBlob(x, y, w, h, { topW: 0.94, botW: 1.12, square: 0.1, sideY: 0.08 })
      case 'dog': return softBlob(x, y, w, h, { topW: 1.0, botW: 1.04, square: 0.16, sideY: 0.06 })
      case 'hamster': return softBlob(x, y, w, h, { topW: 0.8, botW: 1.2, square: 0.18, sideY: 0.14 })
      case 'axolotl': return softBlob(x, y, w, h, { topW: 1.0, botW: 1.08, square: 0.4, sideY: 0.1 })
      case 'capybara': return softBlob(x, y, w, h, { topW: 1.0, botW: 1.0, square: 0.7, sideY: 0.04 })
      default: return ovalPath(x, y, w, h)
    }
  }
  /** Head gradient: a hamster has a pale face under a coloured cap, everyone else is one tone. */
  get headTones() { return this.species === 'hamster' ? [this.coat.belly, this.coat.light] : [this.coat.light, this.coat.mid] }
  get bodyPath() { return ovalPath(G.bodyC.x, G.bodyC.y, G.bodyW, G.bodyH) }

  // ------------------------------------------------------ emotion-driven values

  get hopAmount() {
    const p = this.p, T = this.T
    if (!(p.sleep < 0.5) || p.dangling) return 0
    let h = 0
    switch (p.emotion) {
      case 'excited': case 'playful': case 'blissful': case 'hyped': h = abs(sin(T * 7)); break
      case 'love': case 'proud': h = abs(sin(T * 3.4)) * 0.4; break
    }
    if (p.dance > 0.01) h = max(h, abs(sin(T * 6)) * p.dance)
    return h
  }
  get walkBob() { const p = this.p; return -abs(sin(p.gait)) * 3.4 * p.walk * (1 + 0.4 * p.run) }
  get breathe() { return sin(this.T * (this.p.sleep > 0.5 ? 1.5 : 2.1)) }

  get tailSpeedAmp() {
    const p = this.p
    if (p.dance > 0.3) return [14, 32]
    switch (p.emotion) {
      case 'love': case 'excited': case 'playful': case 'blissful': case 'hyped': return [15, 34]
      case 'vibing': return [7, 18]
      case 'cozy': return [2.5, 6]
      case 'moody': return [2, 5]
      case 'happy': case 'eating': case 'proud': return [9, 22]
      case 'angry': return [14, 14]
      case 'sleepy': case 'bored': return [1.2, 4]
      case 'sad': case 'worried': return [1.6, 3]
      case 'shy': return [2.4, 7]
      case 'curious': return [5.5, 12]
      default: return [4, 12]
    }
  }

  get earPerk() {
    const p = this.p, T = this.T
    switch (p.emotion) {
      case 'alert': case 'angry': case 'excited': case 'blissful': case 'hyped': return -11 - abs(sin(T * 6)) * 4
      case 'vibing': return sin(T * 4) * 5 + p.bop * 8
      case 'cozy': return 6
      case 'moody': return 16
      case 'playful': case 'proud': return -5
      case 'sad': case 'sleepy': case 'bored': return 22
      case 'hungry': case 'worried': return 9
      case 'curious': return -8
      case 'shy': return 13
      default: return sin(T * 2.4) * 3
    }
  }
  get earTwitch() {
    const ph = frac(this.T / 6.3)
    if (!(ph < 0.045 && this.p.sleep < 0.5)) return 0
    return sin((ph / 0.045) * PI * 2) * 11
  }
  get blink() {
    const T = this.T
    switch (this.p.emotion) {
      case 'sleepy': case 'love': case 'happy': case 'eating': case 'angry': case 'sad': case 'shy':
      case 'proud': case 'bored': case 'blissful': case 'cozy': case 'vibing': return 0
    }
    const period = 3.7
    const n = Math.trunc(T / period)
    const cyc = mod(T, period)
    const lid = (t, len) => (t >= 0 && t < len ? sin((t / len) * PI) : 0)
    let v = lid(cyc, 0.14)
    if (n % 3 === 0) v = max(v, lid(cyc - 0.26, 0.12))
    return v
  }
  get irisColor() {
    const s = this.species
    if (s === 'cat') {
      return this.coat.name === 'Ginger' ? rgb(0.98, 0.66, 0.25)
        : (this.coat.name === 'Cloud' ? rgb(0.42, 0.70, 1.0) : rgb(0.66, 0.52, 0.95))
    }
    return IRIS[s]
  }

  // ------------------------------------------------------ draw

  draw(base) {
    const p = this.p, T = this.T
    const ctx = base.copy()
    ctx.translateBy(0, Design.lift)

    const hop = this.hopAmount
    const sh = 1 - hop * 0.2
    if (this.outfit.rug !== 'none') this.drawRug(ctx, hop)
    else if (p.perched) this.drawCushion(ctx, hop)
    else ctx.fill(ovalPath(94, Design.ground + 4, 100 * sh * (1 + 0.12 * p.sleep), 13 * sh), col(black.opacity(0.12)))

    // facing: eased through zero, so a turn reads as a quick pivot
    const turnWidth = (p.facing < 0 ? -1 : 1) * max(pow(abs(p.facing), 0.6), 0.3)
    ctx.translateBy(0, -3 * (1 - abs(p.facing)))
    ctx.scaleAbout(turnWidth, 1, P(Design.centerX, 0))

    // squash and stretch, anchored on the ground
    let sy = 1 - p.squash * 0.16
    let sx = 1 + p.squash * 0.16
    if (this.hopAmount > 0 || p.emotion === 'excited' || p.emotion === 'playful' || p.emotion === 'blissful') {
      const k = (hop - 0.5) * 0.14
      sy += k; sx -= k * 0.8
    }
    sx *= 1 + 0.04 * p.run
    ctx.scaleAbout(sx, sy, P(Design.centerX, G.ground))
    if (p.bop > 0.01) ctx.scaleAbout(1 + 0.03 * p.bop, 1 - 0.05 * p.bop, P(Design.centerX, G.ground))
    if (p.dance > 0.01) ctx.rotateAbout(sin(T * 3) * 7 * p.dance, P(Design.centerX, G.ground))

    if (p.dangling) {
      ctx.scaleAbout(0.96, 1.07, P(Design.centerX, 24))
      ctx.rotateAbout(sin(T * 2.6) * 7, P(Design.centerX, 24))
    }

    const pitch = -16 * p.sit - 5 * p.sleep + 8 * p.stretch + 6 * p.sniff + 3 * p.run + sin(p.gait * 2 + 0.6) * 1.6 * p.walk
    const drop = 10 * p.sleep
    const air = ctx.copy()
    air.translateBy(0, this.walkBob - hop * 7)

    this.drawAura(air, false)
    this.drawLegs(air, false, pitch, drop)
    if (p.sit > 0.01) this.drawHindFoot(air)

    const torso = air.copy()
    torso.translateBy(0, drop)
    torso.rotateAbout(pitch, G.rear)
    this.drawBodyBack(torso)
    this.drawTail(torso)
    this.drawBody(torso)
    this.drawBodyFront(torso)
    this.drawLegs(torso, true, pitch, drop)
    if (this.outfit.neck === 'none') {
      drawCollar(torso, p.collarTier, P(G.headC.x - 12, G.headC.y + this.headH / 2 - 2), 44)
    } else {
      this.drawNeckItem(torso)
    }
    this.drawHead(torso)
    this.drawWavingPaw(torso)
    if (p.propAmt > 0.01) this.drawProp(air)
    this.drawAura(air, true)
  }

  // ------------------------------------------------------ rug, aura, clothes

  drawRug(ctx, hop) {
    const p = this.p, T = this.T
    const c = ctx.copy()
    const squeeze = 1 - hop * 0.05
    const cx = 100, cy = Design.ground + 5
    c.fill(ovalPath(cx, cy + 8, 150 * squeeze, 14), col(black.opacity(0.10)))
    const vgrad = (a, b) => linG([a, b], P(cx, cy - 14), P(cx, cy + 14))
    switch (this.outfit.rug) {
      case 'rugCoquette': {
        const base = ovalPath(cx, cy, 148, 28)
        c.fill(base, vgrad(rgb(1.0, 0.98, 0.95), rgb(0.99, 0.90, 0.91)))
        for (let i = 0; i < 22; i++) {
          const a = (i / 22) * PI * 2
          c.fill(ovalPath(cx + cos(a) * 74, cy + sin(a) * 14, 7, 5), col(white))
        }
        c.stroke(ovalPath(cx, cy, 126, 20), col(rgb(0.97, 0.66, 0.76)), stroke(1.6, { dash: [4, 3] }))
        c.stroke(base, col(rgb(0.93, 0.78, 0.80)), 1.2)
        for (const sd of [-1, 1]) c.fill(ovalPath(cx + 52 + sd * 5, cy + 3, 9, 6), col(rgb(0.98, 0.58, 0.72)))
        c.fill(ovalPath(cx + 52, cy + 3, 4.5, 4.5), col(rgb(0.88, 0.42, 0.58)))
        break
      }
      case 'rugCottage': {
        const base = ovalPath(cx, cy, 148, 28)
        c.fill(base, vgrad(rgb(0.80, 0.92, 0.72), rgb(0.62, 0.82, 0.58)))
        c.stroke(base, col(rgb(0.46, 0.68, 0.44)), 1.6)
        ;[-52, -32, -12, 8, 28, 50].forEach((dx, i) => {
          const l = c.copy()
          l.translateBy(cx + dx, cy + (i % 2 === 0 ? -3 : 4))
          l.rotateDeg(i * 37 - 60)
          l.fill(ovalPath(0, 0, 11, 5), col(rgb(0.42, 0.66, 0.40).opacity(0.75)))
        })
        for (const [dx, dy] of [[-62, 1], [60, -2], [-20, 7], [30, 8]]) {
          c.fill(ovalPath(cx + dx, cy + dy, 5, 5), col(white))
          c.fill(ovalPath(cx + dx, cy + dy, 2, 2), col(rgb(1.0, 0.84, 0.4)))
        }
        break
      }
      case 'rugY2K': {
        const h = c.copy()
        h.translateBy(cx, cy + 1)
        h.scaleBy(1.7, 0.36)
        const heart = heartPath(ZERO, 78)
        h.fill(heart, linG([rgb(1.0, 0.60, 0.82), rgb(0.98, 0.36, 0.64)], P(0, -39), P(0, 39)))
        h.stroke(heart, col(white.opacity(0.85)), 3.2)
        for (let i = 0; i < 9; i++) {
          const tw = 0.5 + 0.5 * sin(T * 3 + i * 1.7)
          const x = cx + (i - 4) * 14 + (i % 2 === 0 ? 3 : -3)
          c.fill(starPathOf(1.0 + tw * 2.2).translated(x, cy + (i % 3 === 0 ? -4 : 3)), col(white.opacity(0.5 + tw * 0.5)))
        }
        break
      }
      case 'rugCyber': {
        const base = ovalPath(cx, cy, 148, 28)
        c.fill(base, vgrad(rgb(0.24, 0.20, 0.40), rgb(0.12, 0.10, 0.24)))
        const neon = rgb(0.36, 0.96, 0.88)
        c.stroke(base, col(neon.opacity(0.3)), 7)
        c.stroke(base, col(neon), 2)
        const pulse = 0.5 + 0.5 * sin(T * 2)
        c.stroke(ovalPath(cx, cy, 104 + pulse * 6, 17 + pulse), col(rgb(0.82, 0.52, 1.0).opacity(0.55)), 1.6)
        c.stroke(ovalPath(cx, cy, 60, 10), col(neon.opacity(0.35)), 1.2)
        break
      }
    }
  }

  drawAura(ctx, front) {
    const p = this.p, T = this.T
    if (this.outfit.aura === 'none') return
    for (let i = 0; i < 7; i++) {
      const a = T * 0.8 + i * ((PI * 2) / 7)
      const side = sin(a)
      if ((side > 0) !== front) continue
      const x = 100 + cos(a) * 84
      const y = 82 + side * 22 + sin(T * 1.7 + i) * 6 - (i % 3) * 9
      const tw = 0.55 + 0.45 * sin(T * 3 + i * 2.1)
      const c = ctx.copy()
      c.opacity = 0.55 + 0.45 * tw
      c.translateBy(x, y)
      if (this.outfit.aura === 'auraHearts') {
        c.fill(heartPath(ZERO, 9 + tw * 5), col(Fur.heart))
      } else if (this.outfit.aura === 'auraStars') {
        c.rotateDeg(T * 40 + i * 30)
        c.fill(starPathOf(5 + tw * 3), col(rgb(1.0, 0.86, 0.36)))
      } else {
        const sp = new Path()
        const r = 3.5 + tw * 4, k = r * 0.28
        sp.move(0, -r).line(k, -k).line(r, 0).line(k, k).line(0, r).line(-k, k).line(-r, 0).line(-k, -k).close()
        c.fill(sp, col(rgb(1.0, 0.97, 0.7)))
      }
    }
  }

  drawBodyBack(ctx) {
    const p = this.p, T = this.T
    if (this.outfit.body === 'angelWings') {
      const flap = sin(T * 3.4 + p.gait) * 7 * (0.5 + p.walk) + sin(T * 2) * 2
      ;[-12, 6].forEach((tilt, i) => {
        const w = ctx.copy()
        w.translateBy(G.bodyC.x - 10, G.bodyC.y - 20)
        w.rotateDeg(tilt + (i === 0 ? flap : -flap * 0.7))
        ;[54, 49, 43, 36].forEach((len, j) => {
          const f = w.copy()
          f.rotateDeg(-158 + j * 17)
          const feather = ovalPath(len * 0.5, 0, len, 16 - j * 1.5)
          f.fill(feather, linG([white, rgb(0.86, 0.89, 1.0)], ZERO, P(len, 0)))
          f.stroke(feather, col(rgb(0.72, 0.76, 0.95)), 1.2)
        })
      })
    } else if (this.outfit.body === 'cape') {
      const sway = sin(T * 2.4 + p.gait) * 4 + p.walk * sin(p.gait * 2) * 4
      const cape = new Path()
      cape.move(G.neck.x - 6, 113)
      cape.quad(6 + sway, 140, 46, 100 + sway)
      cape.quad(40, 154, 10 + sway, 156)
      cape.quad(G.neck.x + 6, 120, 80, 140)
      cape.close()
      ctx.fill(cape, linG([rgb(0.97, 0.50, 0.66), rgb(0.62, 0.26, 0.48)], P(90, 112), P(14, 154)))
      ctx.stroke(cape, col(rgb(1.0, 0.84, 0.42)), stroke(2.2, { join: 'round' }))
      const fold = new Path()
      fold.move(70, 118).quad(30 + sway, 148, 50, 126)
      ctx.stroke(fold, col(white.opacity(0.22)), stroke(2, { cap: 'round' }))
    }
  }

  drawBodyFront(ctx) {
    const p = this.p
    const kind = this.outfit.body
    if (kind !== 'knitSweater' && kind !== 'hoodie') return
    const c = ctx.copy()
    const flat = 1 - 0.13 * p.sleep
    const swell = 1 + this.breathe * (p.sleep > 0.5 ? 0.035 : 0.018)
    c.scaleAbout(1 + 0.05 * p.sleep, swell * flat, P(G.bodyC.x, G.ground))
    const body = this.bodyPath
    const clipped = c.copy()
    clipped.clipTo(body)
    const top = G.bodyC.y - G.bodyH / 2
    if (kind === 'knitSweater') {
      const wool = rgb(1.0, 0.78, 0.84)
      clipped.fill(rectPath(30, top - 2, 90, 60), linG([rgb(1.0, 0.84, 0.88), wool], P(70, top), P(80, top + 52)))
      for (let i = 0; i < 9; i++) {
        const x = 42 + i * 8
        const st = new Path()
        st.move(x, top + 4).line(x + 3, top + 16).line(x, top + 28).line(x + 3, top + 40)
        clipped.stroke(st, col(rgb(0.92, 0.58, 0.68).opacity(0.55)), stroke(2.2, { cap: 'round', join: 'round' }))
      }
      clipped.fill(rectPath(30, top + 38, 90, 14), col(rgb(0.96, 0.62, 0.74)))
      for (let i = 0; i < 12; i++) clipped.fill(rectPath(36 + i * 7, top + 38, 1.6, 14), col(white.opacity(0.28)))
    } else {
      const fabric = rgb(0.80, 0.76, 0.96)
      clipped.fill(rectPath(30, top - 2, 90, 60), linG([rgb(0.88, 0.85, 1.0), fabric], P(70, top), P(80, top + 52)))
      const pocket = roundedRectPath(56, top + 24, 34, 15, 6)
      clipped.fill(pocket, col(rgb(0.74, 0.70, 0.92)))
      clipped.stroke(pocket, col(rgb(0.62, 0.58, 0.84).opacity(0.7)), 1.1)
      clipped.fill(rectPath(30, top + 42, 90, 10), col(rgb(0.70, 0.66, 0.90)))
    }
    c.stroke(body, col(rgb(0.84, 0.52, 0.64).opacity(kind === 'hoodie' ? 0 : 0.6)), 1.2)
    if (kind === 'hoodie') {
      const hood = ovalPath(G.neck.x - 4, 114, 56, 16)
      c.fill(hood, col(rgb(0.72, 0.68, 0.92)))
      c.stroke(hood, col(rgb(0.60, 0.56, 0.82).opacity(0.7)), 1.1)
      for (const dx of [-4, 5]) {
        const s = new Path()
        s.move(G.neck.x + dx, 118).quad(G.neck.x + dx * 1.6, 134, G.neck.x + dx * 2.2, 126)
        c.stroke(s, col(white.opacity(0.9)), stroke(1.8, { cap: 'round' }))
      }
    }
  }

  drawCushion(ctx, hop) {
    const c = ctx.copy()
    const lift = hop * 3
    c.fill(ovalPath(94, Design.ground + 11, 104 - lift * 4, 10), col(black.opacity(0.10)))
    const r = { x: 36, y: Design.ground - 4 - lift, w: 116, h: 20 }
    const pillow = roundedRectPath(r.x, r.y, r.w, r.h, 10)
    c.fill(pillow, linG([rgb(1.0, 0.88, 0.94), rgb(0.98, 0.72, 0.86)], P(0, r.y), P(0, r.y + r.h)))
    c.stroke(pillow, col(rgb(0.92, 0.55, 0.75).opacity(0.7)), 1.4)
    c.fill(ovalPath(r.x + 30, r.y + 4, 34, 4.5), col(white.opacity(0.55)))
    for (const dx of [-12, 0, 12]) c.fill(ovalPath(r.x + r.w / 2 + dx, r.y + r.h / 2 + 2, 3, 3), col(white.opacity(0.7)))
  }

  // ------------------------------------------------------ props

  drawProp(ctx) {
    const p = this.p
    const c = ctx.copy()
    const k = min(1, p.propAmt)
    c.opacity = k
    c.scaleAbout(0.5 + 0.5 * k, 0.5 + 0.5 * k, P(118, G.ground))
    switch (p.prop) {
      case 'book': this.drawBook(c); break
      case 'boba': this.drawBoba(c); break
      case 'matcha': this.drawMatcha(c); break
      case 'console': this.drawConsole(c); break
    }
  }

  drawBook(c) {
    const T = this.T
    const cx = 122, cy = G.ground - 6
    const ribbon = rgb(0.80, 0.72, 0.95)
    const cover = roundedRectPath(cx - 34, cy - 8, 68, 22, 5)
    c.fill(cover, linG([rgb(0.98, 0.62, 0.78), rgb(0.90, 0.46, 0.66)], P(cx, cy - 8), P(cx, cy + 14)))
    for (const sd of [-1, 1]) {
      const pg = c.copy()
      pg.translateBy(cx + sd * 15, cy + 2)
      pg.rotateDeg(sd * 5)
      const page = roundedRectPath(-15, -10, 30, 18, 3)
      pg.fill(page, col(white))
      pg.stroke(page, col(rgb(0.86, 0.78, 0.95)), 1)
      ;[20, 16, 19].forEach((w, i) => {
        const line = new Path()
        line.move(-10, -6 + i * 5).line(-10 + w, -6 + i * 5)
        pg.stroke(line, col(ribbon), stroke(1.5, { cap: 'round' }))
      })
    }
    const turn = frac(T / 5.5)
    if (turn < 0.1) {
      const pg = c.copy()
      pg.translateBy(cx, cy + 2)
      pg.scaleBy(cos((turn / 0.1) * PI), 1)
      const page = roundedRectPath(0, -11, 29, 18, 3)
      pg.fill(page, col(white))
      pg.stroke(page, col(rgb(0.86, 0.78, 0.95)), 1)
    }
    c.fill(rectPath(cx - 1.2, cy - 8, 2.4, 19), col(rgb(0.86, 0.42, 0.62).opacity(0.8)))
    c.fill(rectPath(cx + 10, cy + 8, 4, 11), col(rgb(1.0, 0.86, 0.45)))
  }

  drawMatcha(c) {
    const T = this.T
    const cx = 142, bottom = G.ground - 1
    ;[-5, 1, 7].forEach((dx, i) => {
      const s = new Path()
      const t = T * 1.6 + i * 1.3
      s.move(cx + dx, bottom - 20).quad(cx + dx + sin(t) * 3, bottom - 36, cx + dx + 4 * cos(t), bottom - 28)
      c.stroke(s, col(white.opacity(0.7)), stroke(2, { cap: 'round' }))
    })
    const bowl = new Path()
    bowl.move(cx - 17, bottom - 20).line(cx + 17, bottom - 20).quad(cx - 17, bottom - 20, cx, bottom + 12)
    c.fill(bowl, linG([rgb(1.0, 0.96, 0.90), rgb(0.92, 0.82, 0.72)], P(cx, bottom - 20), P(cx, bottom + 4)))
    c.stroke(bowl, col(rgb(0.80, 0.64, 0.54)), 1.2)
    c.fill(ovalPath(cx, bottom - 20, 34, 8), col(rgb(0.62, 0.80, 0.48)))
    c.stroke(ovalPath(cx, bottom - 20, 34, 8), col(rgb(0.50, 0.66, 0.38)), 1)
    c.fill(ovalPath(cx - 5, bottom - 21, 12, 3), col(white.opacity(0.35)))
    c.fill(heartPath(P(cx, bottom - 8), 8), col(Fur.heart.opacity(0.85)))
  }

  drawConsole(c) {
    const T = this.T
    const cx = 124, cy = G.ground - 7
    const g = c.copy()
    g.translateBy(cx, cy)
    g.rotateDeg(-4)
    const shell = roundedRectPath(-22, -10, 44, 22, 7)
    g.fill(shell, linG([rgb(1.0, 0.78, 0.88), rgb(0.94, 0.58, 0.78)], P(0, -10), P(0, 12)))
    g.stroke(shell, col(rgb(0.82, 0.44, 0.64)), 1.2)
    const screen = roundedRectPath(-11, -7, 22, 15, 3)
    g.fill(screen, col(rgb(0.16, 0.14, 0.28)))
    const glow = 0.6 + 0.4 * sin(T * 4)
    g.fill(heartPath(P(0, 0), 8 + glow * 2), col(rgb(0.55, 0.95, 0.9).opacity(0.9)))
    g.fill(ovalPath(-17, 0, 6, 6), col(rgb(0.98, 0.88, 0.5)))
    g.fill(ovalPath(17, -2, 3.4, 3.4), col(rgb(0.6, 0.9, 1.0)))
    g.fill(ovalPath(17, 4, 3.4, 3.4), col(rgb(1.0, 0.7, 0.8)))
  }

  drawBoba(c) {
    const T = this.T
    const cx = 150, bottom = G.ground - 1
    const wobble = sin(T * 3) * 0.6
    const straw = new Path()
    straw.move(cx + 2, bottom - 28).line(cx - 6 + wobble, bottom - 52)
    c.stroke(straw, col(rgb(0.97, 0.62, 0.78)), stroke(4.6, { cap: 'round' }))
    c.stroke(straw, col(white.opacity(0.7)), stroke(4.6, { dash: [3, 6] }))
    const cup = new Path()
    cup.move(cx - 13, bottom - 30).line(cx + 13, bottom - 30).line(cx + 9.5, bottom).quad(cx - 9.5, bottom, cx, bottom + 4).close()
    c.fill(cup, linG([rgb(1.0, 0.92, 0.88), rgb(0.96, 0.80, 0.74)], P(cx, bottom - 30), P(cx, bottom)))
    c.stroke(cup, col(rgb(0.88, 0.62, 0.62).opacity(0.8)), 1.3)
    for (const [dx, dy] of [[-5, -3], [1, -4], [6, -2.5], [-1, -8], [4.5, -9]]) {
      c.fill(ovalPath(cx + dx, bottom + dy, 5.2, 5.2), col(rgb(0.34, 0.22, 0.24)))
      c.fill(ovalPath(cx + dx - 1, bottom + dy - 1, 1.6, 1.6), col(white.opacity(0.5)))
    }
    c.fill(ovalPath(cx, bottom - 30, 29, 7), col(white.opacity(0.85)))
    c.stroke(ovalPath(cx, bottom - 30, 29, 7), col(rgb(0.88, 0.62, 0.62).opacity(0.7)), 1.2)
    c.fill(heartPath(P(cx, bottom - 17), 8), col(Fur.heart.opacity(0.9)))
  }

  // ------------------------------------------------------ tail

  drawTail(ctx) {
    const p = this.p, T = this.T, species = this.species, coat = this.coat
    const c = ctx.copy()
    c.translateBy(G.tailBase.x, G.tailBase.y)
    const [speed, amp] = this.tailSpeedAmp
    const boost = 1 + p.petting * 0.9
    const hang = (p.sleep > 0.4 || p.emotion === 'sad' || p.emotion === 'sleepy' || p.emotion === 'worried') ? 1 : 0
    const lift = 38 * p.stretch + 30 * p.sniff
    const s = TAILS[species]
    if (!s) { this.drawPom(c, speed, amp, boost); return }

    // forward kinematics: every segment turns a little more than the last
    const curl = hang > 0 ? -30 : s.curl
    const len = s.len * (hang > 0 ? 0.62 : 1)
    const pos = { x: 0, y: 0 }
    let heading = (hang > 0 ? 168 : s.base) + lift
    const dots = []
    for (let i = 0; i <= s.n; i++) {
      const u = i / s.n
      heading += curl / s.n
      const wave = sin(T * speed * boost - u * 3.2) * amp * (0.2 + 0.9 * u) * (1 + p.petting * 0.4) * (hang > 0 ? 0.3 : 1)
      const a = ((heading + wave) * PI) / 180
      pos.x += cos(a) * len
      pos.y += sin(a) * len
      let r = s.r0 + (s.r1 - s.r0) * u
      if (s.bushy > 0) r += s.bushy * sin(min(1, u * 0.82) * PI)
      let colr = blendCoat(coat, 2, 0, u * 0.85)
      if (species === 'fox') colr = u > 0.74 ? coat.belly : blendCoat(coat, 2, 1, 0.5 + u * 0.3)
      else if (species === 'cat' && u > 0.8) colr = coat.shade                 // a darker tip, like a dipped brush
      else if (species === 'axolotl') colr = blendCoat(coat, 1, 4, 0.15 + u * 0.55)   // fading to a bright fin
      dots.push([pos.x, pos.y, r, colr])
    }
    for (const d of dots) c.fill(ovalPath(d[0], d[1], d[2] * 2 + 2.6, d[2] * 2 + 2.6), col(this.rim))
    for (const d of dots) c.fill(ovalPath(d[0], d[1], d[2] * 2, d[2] * 2), col(d[3]))
  }

  drawPom(c, speed, amp, boost) {
    const T = this.T, species = this.species, coat = this.coat
    const r = species === 'bunny' ? 11 : (species === 'panda' ? 9 : (species === 'capybara' ? 5 : 6.5))
    const j = sin(T * speed * boost) * amp * 0.12
    const g = c.copy()
    g.translateBy(-1, -3)
    g.rotateDeg(j * 3)
    const pom = ovalPath(0, j * 0.3, r * 2, r * 2)
    g.fill(pom, radG([coat.light, species === 'panda' ? coat.light : coat.mid], P(-r * 0.3, -r * 0.3), 1, r * 1.4))
    g.stroke(pom, col(this.rim), 1.3)
  }

  // ------------------------------------------------------ legs

  drawLegs(ctx, front, pitch, drop) {
    const p = this.p, T = this.T
    const ids = front ? [2, 3] : [0, 1]
    for (const i of ids) {
      const far = i === 0 || i === 2
      const x = G.legsX[i]
      const sw = p.gait + (i % 2 === 0 ? 0 : PI) + (front ? 0 : PI)
      let angle = sin(sw) * 30 * p.walk * (1 + 0.3 * p.run)
      let lift = max(0, -cos(sw)) * 6 * p.walk
      let length = G.ground - G.hipY - 3

      if (front) {
        const th = (pitch * PI) / 180
        const rx = x - G.rear.x, ry = G.hipY - G.rear.y
        const hipY = G.rear.y + rx * sin(th) + ry * cos(th) + drop
        length = max(10, G.ground - 3 - hipY)
        angle -= pitch * (1 - p.stretch)
        if (p.stretch > 0) angle += 44 * p.stretch
      }
      if (p.dance > 0.01) {
        const beat = sin(T * 6 + (i % 2 === 0 ? 0 : PI))
        angle += beat * 30 * p.dance
        lift += max(0, beat) * 7 * p.dance
      }
      if (p.dangling) { angle = sin(T * 3 + i) * 12 + (i < 2 ? 8 : -8); lift = 0 }
      if (p.tapping && front) {
        const r = tapRaise(p.tapPhase)
        angle = i === 3 ? -95 * r : 10 * r
        length = G.ground - G.hipY - 3
      }
      if (p.scratch > 0 && i === 1) {
        angle = (-92 + sin(T * 22) * 9) * p.scratch + angle * (1 - p.scratch)
        lift = 0
      }
      const tuck = 1 - 0.62 * p.sleep
      let opacity = 1
      if (!front) opacity = 1 - p.sit
      if (p.scratch > 0 && i === 1) opacity = 1
      if (front && i === 3) opacity = 1 - p.wave
      if (!(opacity > 0.01)) continue

      const c = ctx.copy()
      c.opacity = opacity
      c.translateBy(x, G.hipY - 4 - lift)
      c.rotateDeg(angle)
      this.drawLeg(c, length * tuck + 4, far, !far)
    }
  }

  drawLeg(c, length, far, beans) {
    const species = this.species, coat = this.coat, rim = this.rim
    const w = species === 'hamster' ? 16 : 18
    const limb = capsulePath(0, length / 2, w, length)
    let limbColor
    if (species === 'panda') limbColor = coat.patch
    else if (species === 'fox') limbColor = far ? coat.shade : coat.patch
    else limbColor = far ? coat.shade.opacity(0.92) : coat.mid
    c.fill(limb, col(limbColor))
    c.stroke(limb, col(rim), 1.2)

    let pawColor
    if (species === 'panda') pawColor = far ? coat.patch : coat.patch.opacity(0.92)
    else if (species === 'fox') pawColor = coat.patch
    else pawColor = far ? coat.mid : coat.light
    const paw = ovalPath(1, length - 3, far ? 21 : 24, 15)
    c.fill(paw, col(pawColor))
    c.stroke(paw, col(rim), 1.1)
    if (beans) {
      const by = length - 5
      const pad = Fur.blushAccent.opacity(species === 'panda' ? 0.75 : 0.62)
      c.fill(ovalPath(1, by + 2.5, 8, 6.4), col(pad))
      for (const dx of [-6.4, 0, 6.4]) c.fill(ovalPath(1 + dx, by - 3.4, 4.2, 3.9), col(pad))
    }
  }

  drawHindFoot(ctx) {
    const p = this.p, coat = this.coat
    const c = ctx.copy()
    c.opacity = p.sit
    const foot = ovalPath(G.rear.x + 34, G.ground - 6, 32, 13)
    c.fill(foot, col(this.species === 'panda' || this.species === 'fox' ? coat.patch : coat.light))
    c.stroke(foot, col(this.rim), 1.1)
  }

  // ------------------------------------------------------ body

  drawBody(ctx) {
    const p = this.p, coat = this.coat, species = this.species
    const c = ctx.copy()
    const flat = 1 - 0.13 * p.sleep
    const swell = 1 + this.breathe * (p.sleep > 0.5 ? 0.035 : 0.018)
    c.scaleAbout(1 + 0.05 * p.sleep, swell * flat, P(G.bodyC.x, G.ground))

    const body = this.bodyPath
    c.fill(body, radG([coat.light, coat.mid], P(G.bodyC.x - 8, G.bodyC.y - G.bodyH * 0.45), 2, G.bodyW * 1.05))

    const clipped = c.copy()
    clipped.clipTo(body)
    clipped.fill(ovalPath(G.bodyC.x + 6, G.bodyC.y + G.bodyH * 0.34, G.bodyW * 0.72, G.bodyH * 0.36), col(coat.shade.opacity(0.2)))
    clipped.fill(ovalPath(G.bodyC.x + 12, G.bodyC.y + 12, G.bodyW * 0.55, G.bodyH * 0.55),
      col(coat.belly.opacity(species === 'dog' || species === 'cat' ? 0.55 : 0.8)))
    if (species === 'panda') clipped.fill(ovalPath(G.bodyC.x + 20, G.bodyC.y, 22, 70), col(coat.patch))
    if (coat.stripes) {
      for (const [dx, len] of [[-16, 12], [-4, 15], [8, 13]]) {
        const x = G.bodyC.x + dx
        const s = new Path()
        s.move(x, G.bodyC.y - G.bodyH / 2 - 1).quad(x + 2, G.bodyC.y - G.bodyH / 2 + len, x - 3, G.bodyC.y - G.bodyH / 2 + len * 0.5)
        clipped.stroke(s, col(coat.patch.opacity(0.55)), stroke(3.2, { cap: 'round' }))
      }
    }
    clipped.fill(ovalPath(G.bodyC.x - 8, G.bodyC.y - G.bodyH * 0.3, 26, 9), col(white.opacity(0.35)))
    c.stroke(body, col(this.rim), 1.4)

    if (p.sit > 0.02) {
      const h = c.copy()
      h.opacity = min(1, p.sit * 1.5)
      const thigh = ovalPath(G.rear.x + 8, 136, 38 * p.sit + 8, 32 * p.sit + 6)
      h.fill(thigh, radG([coat.light, coat.mid], P(G.rear.x + 4, 126), 1, 28))
      h.stroke(thigh, col(this.rim), 1.2)
    }
  }

  // ------------------------------------------------------ head

  get headTilt() {
    const p = this.p, T = this.T
    let t
    switch (p.emotion) {
      case 'love': t = sin(T * 1.8) * 6 - 4; break
      case 'alert': t = -7; break
      case 'sad': case 'worried': t = 6; break
      case 'sleepy': t = 9 + sin(T * 1.1) * 3; break
      case 'playful': t = sin(T * 5) * 7; break
      case 'angry': t = sin(T * 12) * 2.5; break
      case 'curious': t = 16 + sin(T * 1.4) * 3; break
      case 'shy': t = 10; break
      case 'bored': t = -3; break
      case 'blissful': t = sin(T * 1.2) * 3; break
      case 'vibing': t = sin(T * 3.2) * 8 + p.bop * 4; break
      case 'cozy': t = 7 + sin(T * 1.1) * 2; break
      case 'moody': t = -5; break
      default: t = sin(T * 1.6) * 2
    }
    t += p.look.dx * 3.5
    t += 16 * p.stretch + 20 * p.sniff + sin(T * 5) * 3 * p.sniff
    t += 14 * p.sleep
    t += (p.groom > 0 ? 14 + sin(frac(T * 2.2) * PI) * 10 : 0) * p.groom
    t -= 10 * p.scratch
    t += sin(T * 6) * 9 * p.dance + 5 * p.wave
    if (p.prop === 'book' || p.prop === 'console') t += 11 * p.propAmt
    if (p.prop === 'boba' || p.prop === 'matcha') t += 6 * this.sip
    if (p.tapping) t -= 16 * tapRaise(p.tapPhase)
    return t
  }
  get sip() {
    const p = this.p
    return (p.prop === 'boba' || p.prop === 'matcha') ? p.propAmt * pow(max(0, sin(this.T * 0.8)), 0.6) : 0
  }

  drawHead(ctx) {
    const p = this.p, T = this.T, coat = this.coat, headW = this.headW, headH = this.headH
    const c = ctx.copy()
    const sip = this.sip
    let dx = p.look.dx * 2.5, dy = p.look.dy * 1.5
    dy += sin(p.gait - 0.7) * 1.8 * p.walk
    dy -= p.petting * 3
    dx += sin(T * 0.7) * 0.9
    dy += 5 * p.bop
    dx += 7 * p.sit
    dx -= 2 * p.sleep; dy += 30 * p.sleep
    dx -= 2 * p.stretch; dy += 8 * p.stretch
    dx += 0 * p.sniff; dy += 9 * p.sniff
    dx += 6 * p.run; dy += 2 * p.run
    if (p.tapping) dx += 6 * tapRaise(p.tapPhase)
    if (p.prop === 'book' || p.prop === 'console') { dy += 7 * p.propAmt; dx -= 1 * p.propAmt }
    if (p.prop === 'boba' || p.prop === 'matcha') { dx += 8 * sip; dy += 4 * sip }
    if (p.emotion === 'eating') {
      const dip = 0.5 + 0.5 * sin(T * 7)
      dx += 2 + 3 * dip; dy += 20 + 10 * dip
    }
    if (p.emotion === 'angry') dx += 4 * abs(sin(T * 12))
    c.translateBy(dx, dy)
    let tilt = this.headTilt
    if (p.emotion === 'eating') tilt += 12
    c.rotateAbout(tilt, G.neck)

    this.drawEars(c)
    this.drawCheekFluff(c)

    const head = this.headPath
    c.fill(head, radG(this.headTones, P(G.headC.x - 8, G.headC.y - headH * 0.5), 2, headW * 0.78))
    const clipped = c.copy()
    clipped.clipTo(head)
    this.drawMarks(clipped)
    const gloss = clipped.copy()
    gloss.translateBy(G.headC.x - headW * 0.2, G.headC.y - headH * 0.34)
    gloss.rotateDeg(-22)
    gloss.fill(ovalPath(0, 0, headW * 0.4, headH * 0.17), col(white.opacity(0.42)))
    clipped.fill(ovalPath(G.headC.x, G.headC.y + headH * 0.5, headW * 0.8, headH * 0.22), col(white.opacity(0.16)))
    c.stroke(head, col(this.rim), 1.5)

    this.drawFoxRuff(c)
    this.drawMuzzle(c)
    this.drawBlush(c)
    this.drawWhiskers(c)
    this.drawMouthAndNose(c)
    this.drawEyes(c)
    this.drawGroomingPaw(c)
    this.drawHeadAccessory(c)
  }

  drawWavingPaw(ctx) {
    const p = this.p, T = this.T, species = this.species, coat = this.coat
    if (!(p.wave > 0.02)) return
    const c = ctx.copy()
    c.opacity = min(1, p.wave * 2)
    c.translateBy(G.legsX[3] + 5, G.hipY - 6)
    c.rotateDeg((-108 + sin(T * 11) * 16) * p.wave)
    const limbColor = (species === 'panda' || species === 'fox') ? coat.patch : coat.mid
    const limb = capsulePath(0, 13, 17, 28)
    c.fill(limb, col(limbColor))
    c.stroke(limb, col(this.rim), 1.2)
    const paw = ovalPath(1, 26, 23, 15)
    c.fill(paw, col(species === 'panda' || species === 'fox' ? coat.patch : coat.light))
    c.stroke(paw, col(this.rim), 1.1)
    const pad = Fur.blushAccent.opacity(0.65)
    c.fill(ovalPath(1, 28, 7, 5.6), col(pad))
    for (const dx of [-5.5, 0, 5.5]) c.fill(ovalPath(1 + dx, 22.5, 3.6, 3.4), col(pad))
  }

  /** Two fluffy points on each cheek: the kitten's whole silhouette. Drawn before the head. */
  drawCheekFluff(c) {
    if (this.species !== 'cat') return
    const coat = this.coat
    for (const sd of [-1, 1]) {
      const cx = G.headC.x + sd * this.headW * 0.5
      const y0 = G.headC.y + this.headH * 0.1
      for (const [dy, out, len] of [[0, 3, 9], [10, 1.5, 8]]) {
        const t = new Path()
        t.move(cx - sd * 8, y0 + dy - 5).quad(cx + sd * (out + 5), y0 + dy + len, cx + sd * (out + 6), y0 + dy + 1).line(cx - sd * 8, y0 + dy + 9).close()
        c.fill(t, col(coat.mid))
        c.stroke(t, col(this.rim), stroke(1.2, { join: 'round' }))
      }
    }
  }

  // ------------------------------------------------------ ears

  drawEars(ctx) {
    const p = this.p, T = this.T, species = this.species, coat = this.coat
    let f
    switch (species) {
      case 'dog': f = [0.80, -0.50]; break
      case 'bunny': f = [0.34, -0.78]; break
      case 'panda': f = [0.70, -0.72]; break
      case 'hamster': f = [0.66, -0.70]; break
      case 'axolotl': f = [0.78, -0.08]; break
      case 'capybara': f = [0.64, -0.78]; break
      case 'cat': f = [0.60, -0.76]; break
      default: f = [0.58, -0.78]
    }
    const hw = this.headW / 2, hh = this.headH / 2
    const anchors = [[P(G.headC.x - f[0] * hw, G.headC.y + f[1] * hh + 2), true], [P(G.headC.x + f[0] * hw, G.headC.y + f[1] * hh), false]]
    for (const [anchor, mirrored] of anchors) {
      const c = ctx.copy()
      c.translateBy(anchor.x, anchor.y)
      if (mirrored) c.scaleBy(-1, 1)
      let angle = this.earPerk + (mirrored ? 0 : this.earTwitch)
      angle += sin(p.gait * 2 - 1.1) * 6 * p.walk + sin(T * 12) * 5 * p.dance
      angle += sin(T * 9 + (mirrored ? 0.7 : 0)) * 4 * (p.emotion === 'excited' ? 1 : 0)
      if (p.emotion === 'curious' && !mirrored) angle -= 14
      if (p.dangling) angle -= 34
      if (p.sleep > 0.5) angle = 16
      switch (species) {
        case 'cat': this.earKitten(c, angle); break
        case 'fox': this.earPointed(c, angle, 1.3, coat.patch); break
        case 'dog': this.earFloppy(c, angle); break
        case 'bunny': this.earLong(c, angle, mirrored); break
        case 'panda': this.earRound(c, angle, 15, coat.patch, null); break
        case 'hamster': this.earRound(c, angle, 14, coat.patch, Fur.blushAccent.opacity(0.75)); break
        case 'capybara': this.earRound(c, angle, 10, coat.shade, coat.patch.opacity(0.75)); break
        case 'axolotl': this.gills(c); break
      }
    }
  }

  earPointed(ctx, angle, scale, tip) {
    const coat = this.coat
    const c = ctx.copy()
    c.rotateDeg(angle)
    c.scaleBy(scale, scale * (this.species === 'fox' ? 1.1 : 1))
    const ear = new Path()
    ear.move(-15, 7).quad(1, -30, -12, -15).quad(18, 9, 14, -14).quad(-15, 7, 1, 16).close()
    c.fill(ear, linG([coat.mid, coat.shade], ZERO, P(16, 34)))
    if (tip) {
      const t = c.copy()
      t.clipTo(ear)
      t.fill(rectPath(-30, -40, 60, 22), col(tip))
    }
    c.stroke(ear, col(this.rim), 1.2 / scale)
    const inner = new Path()
    inner.move(-7, 3).quad(1, -19, -5, -10).quad(9, 5, 6, -7).quad(-7, 3, 1, 9).close()
    c.fill(inner, col(tip ? coat.belly.opacity(0.9) : Fur.blushAccent.opacity(0.55)))
  }

  /** A kitten's ear: wide at the base, a rounded tip, and a pink inside with a little fluff. */
  earKitten(ctx, angle) {
    const coat = this.coat
    const c = ctx.copy()
    c.rotateDeg(angle)
    c.scaleBy(1.12, 1.18)
    const ear = new Path()
    ear.move(-17, 9).curve(-5, -25, -19, -6, -13, -20).quad(9, -24, 2, -33).curve(19, 9, 17, -17, 21, -3).quad(-17, 9, 1, 17).close()
    c.fill(ear, linG([coat.mid, coat.shade], P(0, -30), P(6, 20)))
    c.stroke(ear, col(this.rim), stroke(1.2 / 1.15, { join: 'round' }))
    const inner = new Path()
    inner.move(-9, 5).curve(-2, -17, -11, -5, -7, -13).quad(6, -16, 2, -22).curve(11, 5, 10, -10, 12, -2).quad(-9, 5, 1, 10).close()
    c.fill(inner, linG([Fur.blushAccent.opacity(0.9), Fur.blushAccent.opacity(0.45)], P(0, -18), P(0, 8)))
    for (const dx of [-2.5, 2.5]) {
      const w = new Path()
      w.move(dx, 6).quad(dx * 1.6, -6, dx * 2.4, 0)
      c.stroke(w, col(white.opacity(0.7)), stroke(1.4, { cap: 'round' }))
    }
  }

  /** A puppy's ear: a soft triangle that folds over and hangs, with a crease where it bends. */
  earFloppy(ctx, angle) {
    const coat = this.coat
    const c = ctx.copy()
    c.rotateDeg(angle * 1.4 + 6)
    const ear = new Path()
    ear.move(-9, -8).curve(21, 4, 3, -17, 17, -9).curve(17, 42, 26, 16, 26, 34).quad(4, 38, 10, 50).curve(-9, -8, -3, 24, -10, 8).close()
    c.fill(ear, linG([coat.patch, coat.patch.opacity(0.82)], P(0, -10), P(14, 46)))
    c.stroke(ear, col(this.rim), stroke(1.2, { join: 'round' }))
    const crease = new Path()
    crease.move(-4, -8).quad(19, 6, 9, 2)
    c.stroke(crease, col(black.opacity(0.12)), stroke(1.6, { cap: 'round' }))
    c.fill(ovalPath(13, 26, 8, 20), col(white.opacity(0.18)))
  }

  earLong(ctx, angle) {
    const p = this.p, coat = this.coat
    const c = ctx.copy()
    const droop = (p.emotion === 'sad' || p.emotion === 'sleepy' || p.emotion === 'bored' || p.sleep > 0.5) ? 38 : 0
    c.rotateDeg(angle * 1.3 + 7 + droop)
    const ear = ovalPath(0, -26, 23, 62)
    c.fill(ear, linG([coat.mid, coat.light], P(0, 4), P(0, -58)))
    c.stroke(ear, col(this.rim), 1.2)
    c.fill(ovalPath(0, -25, 11, 46), col(Fur.blushAccent.opacity(0.6)))
  }

  /** The axolotl's three fluffy gill fronds a side, swaying like they're underwater. */
  gills(ctx) {
    const p = this.p, T = this.T, coat = this.coat
    ;[-86, -56, -24].forEach((base, i) => {
      const c = ctx.copy()
      const sway = sin(T * 2.6 + i * 0.9) * 8 + p.walk * sin(p.gait * 2 + i) * 5
      const ang = ((base + sway - (p.sleep > 0.5 ? -14 : 0)) * PI) / 180
      const len = 27 - i * 2.5
      const tip = P(cos(ang) * len, sin(ang) * len)
      const mid = P(tip.x * 0.5, tip.y * 0.5 - 3)
      const stalk = new Path()
      stalk.move(-6, i * 6 - 4).quad(tip.x, tip.y, mid.x, mid.y)
      c.stroke(stalk, col(coat.patch.opacity(0.5)), stroke(8.4, { cap: 'round' }))
      c.stroke(stalk, col(coat.patch), stroke(6, { cap: 'round' }))
      ;[-34, 0, 34].forEach((spread, k) => {
        const a = ang + (spread * PI) / 180 + sin(T * 3.1 + k + i) * 0.12
        const end = P(tip.x + cos(a) * 8, tip.y + sin(a) * 8)
        const fil = new Path()
        fil.move(tip.x, tip.y).line(end.x, end.y)
        c.stroke(fil, col(coat.patch.opacity(0.55)), stroke(6.4, { cap: 'round' }))
        c.stroke(fil, col(coat.patch), stroke(4.4, { cap: 'round' }))
        c.fill(ovalPath(end.x - 0.8, end.y - 0.9, 2.4, 2.2), col(white.opacity(0.55)))
      })
      c.fill(ovalPath(tip.x, tip.y, 11, 11), col(coat.patch))
      c.fill(ovalPath(tip.x - 2, tip.y - 2.2, 3.6, 3.2), col(white.opacity(0.55)))
    })
  }

  earRound(ctx, angle, r, color, inner) {
    const c = ctx.copy()
    c.rotateDeg(angle * 0.5)
    const ear = ovalPath(0, -r * 0.35, r * 2, r * 2)
    c.fill(ear, col(color))
    c.stroke(ear, col(this.rim), 1.2)
    if (inner) c.fill(ovalPath(0, -r * 0.3, r * 1.1, r * 1.1), col(inner))
  }

  // ------------------------------------------------------ face

  drawMarks(c) {
    const coat = this.coat, headW = this.headW, headH = this.headH
    switch (this.species) {
      case 'panda':
        for (const [e, rot] of [[G.eyeL, 22], [G.eyeR, -22]]) {
          const g = c.copy()
          g.translateBy(e.x, e.y + 2)
          g.rotateDeg(rot)
          g.fill(ovalPath(0, 0, 26, 33), col(coat.patch))
        }
        break
      case 'dog':
        // a pale blaze down the forehead, and a patch that wraps one ear
        c.fill(ovalPath(G.headC.x + 4, G.headC.y - 14, 19, 58),
          linG([coat.belly.opacity(0.35), coat.belly.opacity(0.95)], P(0, G.headC.y - 42), P(0, G.headC.y + 8)))
        c.fill(ovalPath(G.eyeR.x + 16, G.headC.y - 24, 54, 48), col(coat.patch.opacity(0.92)))
        break
      case 'hamster': {
        // a coloured cap over a pale face, with a dark stripe down the middle
        const hw = headW / 2, cx = G.headC.x, cy = G.headC.y
        const cap = new Path()
        cap.move(cx - hw - 8, cy - headH).line(cx + hw + 8, cy - headH).line(cx + hw + 8, cy + 6)
          .quad(cx, cy - 20, cx + hw * 0.5, cy - 22).quad(cx - hw - 8, cy + 6, cx - hw * 0.5, cy - 22).close()
        c.fill(cap, linG([coat.patch, coat.patch.opacity(0.78)], P(0, cy - 50), P(0, cy)))
        c.fill(capsulePath(cx, cy - 34, 10, 38), col(coat.shade.opacity(0.4)))
        break
      }
      case 'axolotl':
        // freckles across the cheeks
        for (const [dx, dy, r] of [[-44, 16, 1.5], [-37, 24, 1.2], [-48, 26, 1.3], [-30, 31, 1.1], [44, 16, 1.5], [37, 24, 1.2], [48, 26, 1.3], [30, 31, 1.1]]) {
          c.fill(ovalPath(G.headC.x + dx, G.headC.y + dy, r * 2, r * 2), col(coat.shade.opacity(0.7)))
        }
        c.fill(ovalPath(G.headC.x, G.headC.y - headH * 0.5, headW * 0.9, 34), col(coat.shade.opacity(0.16)))
        break
      case 'capybara':
        // a darker crown, and coarse little flecks of hair
        c.fill(ovalPath(G.headC.x, G.headC.y - headH * 0.46, headW * 0.9, 44), col(coat.shade.opacity(0.22)))
        for (const [dx, dy] of [[-34, -30], [-20, -37], [-6, -33], [10, -38], [26, -32], [40, -25], [-46, -16], [49, -10]]) {
          const h = new Path()
          h.move(G.headC.x + dx, G.headC.y + dy).line(G.headC.x + dx + 2.5, G.headC.y + dy + 6)
          c.stroke(h, col(coat.shade.opacity(0.5)), stroke(1.5, { cap: 'round' }))
        }
        break
      case 'fox':
        c.fill(ovalPath(G.muzzleC.x, G.headC.y + headH * 0.44, headW * 0.98, headH * 0.6), col(coat.belly))
        break
      case 'cat':
        // the tabby "M": strong on a ginger, a whisper on the pale coats
        for (const [dx, len] of [[-9, 14], [0, 19], [9, 14]]) {
          const s = new Path()
          s.move(G.headC.x + 2 + dx, G.headC.y - headH / 2).line(G.headC.x + 2 + dx * 0.8, G.headC.y - headH / 2 + len)
          c.stroke(s, col((coat.stripes ? coat.patch : coat.shade).opacity(coat.stripes ? 0.55 : 0.34)), stroke(3.2, { cap: 'round' }))
        }
        break
    }
  }

  drawFoxRuff(c) {
    if (this.species !== 'fox') return
    const coat = this.coat
    const k = this.headH / 90
    for (const sd of [-1, 1]) {
      const cx = G.headC.x + sd * this.headW * 0.47
      const y0 = G.headC.y
      const t = new Path()
      t.move(cx - sd * 7, y0 + 11 * k).line(cx + sd * 11, y0 + 27 * k).line(cx + sd * 1, y0 + 29 * k)
        .line(cx + sd * 9, y0 + 41 * k).line(cx - sd * 12, y0 + 37 * k).close()
      c.fill(t, col(coat.belly))
      c.stroke(t, col(this.rim), stroke(1.2, { join: 'round' }))
    }
  }

  drawMuzzle(c) {
    let w, h
    switch (this.species) {
      case 'dog': [w, h] = [52, 35]; break
      case 'fox': [w, h] = [36, 26]; break
      case 'bunny': [w, h] = [40, 30]; break
      default: [w, h] = [38, 27]
    }
    if (this.species === 'cat') {
      // two puffy whisker pads
      for (const sd of [-1, 1]) c.fill(ovalPath(G.muzzleC.x + sd * 9, G.muzzleC.y + 1, 22, 17), col(this.coat.belly.opacity(0.9)))
      return
    }
    if (this.species === 'capybara') {
      // the capybara's whole personality is a big, calm, boxy snout
      const coat = this.coat
      const r = { x: G.muzzleC.x - 31, y: G.muzzleC.y - 15, w: 62, h: 28 }
      const snout = roundedRectPath(r.x, r.y, r.w, r.h, 13)
      c.fill(snout, linG([coat.belly, coat.belly.opacity(0.7)], P(0, r.y), P(0, r.y + r.h)))
      c.stroke(snout, col(coat.shade.opacity(0.35)), 1)
      return
    }
    const alpha = (this.species === 'panda' || this.species === 'fox') ? 0 : (this.species === 'dog' ? 0.9 : 0.55)
    if (alpha > 0) c.fill(ovalPath(G.muzzleC.x, G.muzzleC.y, w, h), col(this.coat.belly.opacity(alpha)))
  }

  drawBlush(c) {
    const p = this.p
    const shy = ['love', 'shy', 'blissful', 'proud', 'cozy'].includes(p.emotion)
    const colr = Fur.blushAccent.opacity(shy ? 0.75 : 0.5)
    const wide = this.species === 'hamster' ? 28 : (this.species === 'axolotl' ? 26 : 22)
    const spots = [P(G.eyeL.x - 12, G.eyeL.y + 19), P(G.eyeR.x + 14, G.eyeR.y + 21)]
    for (const sp of spots) {
      c.fill(ovalPath(sp.x, sp.y, wide, 13), col(colr))
      if (shy || p.emotion === 'happy') {
        for (let i = -1; i <= 1; i++) {
          const t = new Path()
          t.move(sp.x + i * 5 - 2, sp.y + 3).line(sp.x + i * 5 + 1, sp.y - 3)
          c.stroke(t, col(Fur.heart.opacity(0.55)), stroke(1.3, { cap: 'round' }))
        }
      }
    }
  }

  drawWhiskers(c) {
    const sp = this.species
    if (!(sp === 'cat' || sp === 'fox' || sp === 'hamster')) return
    const len = sp === 'cat' ? 17 : 13
    const twitch = sin(this.T * 1.4) * 1.3
    const m = G.muzzleC
    for (const side of [-1, 1]) {
      for (const dy of [-2, 5]) {
        const w = new Path()
        w.move(m.x + side * 14, m.y + dy).quad(m.x + side * (14 + len), m.y + dy - 3 + twitch * side, m.x + side * (14 + len * 0.5), m.y + dy - 1)
        c.stroke(w, col(Fur.ink.opacity(0.3)), stroke(1.4, { cap: 'round' }))
      }
    }
  }

  // ------------------------------------------------------ nose and mouth

  nosePath() {
    const nx = G.noseC.x, ny = G.noseC.y
    let n = new Path()
    switch (this.species) {
      case 'dog': case 'panda': {
        const w = this.species === 'dog' ? 7.5 : 8
        n.move(nx - w, ny - 4).quad(nx + w, ny - 4, nx, ny - 8).quad(nx, ny + 5, nx + w, ny + 3).quad(nx - w, ny - 4, nx - w, ny + 3)
        break
      }
      case 'fox':
        n.move(nx - 6, ny - 3).quad(nx + 6, ny - 3, nx, ny - 6).quad(nx, ny + 4, nx + 5, ny + 2).quad(nx - 6, ny - 3, nx - 5, ny + 2)
        break
      case 'cat':
        n.move(nx - 5, ny - 3).quad(nx + 5, ny - 3, nx, ny - 6).quad(nx, ny + 4, nx + 4, ny + 1).quad(nx - 5, ny - 3, nx - 4, ny + 1)
        break
      case 'bunny':
        n.move(nx - 4.5, ny - 3).quad(nx + 4.5, ny - 3, nx, ny - 5.5).quad(nx, ny + 3.5, nx + 4.5, ny + 1).quad(nx - 4.5, ny - 3, nx - 4.5, ny + 1)
        break
      case 'hamster': n = ovalPath(nx, ny, 7, 5); break
      case 'axolotl': n = ovalPath(nx, ny, 5, 3.4); break
      case 'capybara': n = roundedRectPath(nx - 14, ny - 5, 28, 12, 6); break
    }
    n.close()
    return n
  }

  get noseColor() {
    if (this.species === 'capybara') return rgb(0.36, 0.23, 0.22)
    return ['cat', 'bunny', 'hamster', 'axolotl'].includes(this.species) ? nosePink : Fur.ink
  }
  get mouthHalfWidth() {
    return { dog: 11, cat: 10, panda: 10, fox: 9, bunny: 8, hamster: 7, axolotl: 12, capybara: 8 }[this.species]
  }

  omegaMouth(c, lift) {
    if (this.species === 'axolotl') {
      // a wide, forever smile with a dimple at each end
      const y0 = G.noseC.y + 6
      const m = new Path()
      m.move(G.noseC.x - 22, y0 - 3 - lift * 0.6).quad(G.noseC.x + 22, y0 - 3 - lift * 0.6, G.noseC.x, y0 + 10 + lift * 0.5)
      c.stroke(m, col(Fur.ink), stroke(2.2, { cap: 'round' }))
      for (const sd of [-1, 1]) {
        const d = new Path()
        d.move(G.noseC.x + sd * 24.5, y0 - 8 - lift * 0.6).line(G.noseC.x + sd * 22, y0 - 2.5 - lift * 0.6)
        c.stroke(d, col(Fur.ink.opacity(0.8)), stroke(1.8, { cap: 'round' }))
      }
      return
    }
    if (this.species === 'capybara') {
      // a tiny, perfectly calm mouth
      const m = new Path()
      m.move(G.noseC.x - 7, G.noseC.y + 12 - lift * 0.4).quad(G.noseC.x + 7, G.noseC.y + 12 - lift * 0.4, G.noseC.x, G.noseC.y + 16 + lift * 0.4)
      c.stroke(m, col(Fur.ink.opacity(0.85)), stroke(2, { cap: 'round' }))
      return
    }
    const top = G.noseC.y + 3
    const junction = top + 6
    const mw = this.mouthHalfWidth
    const stem = new Path()
    stem.move(G.noseC.x, top).line(G.noseC.x, junction)
    c.stroke(stem, col(Fur.ink.opacity(0.75)), stroke(2.0, { cap: 'round' }))
    const m = new Path()
    m.move(G.noseC.x - mw, junction - lift)
      .quad(G.noseC.x, junction, G.noseC.x - mw / 2, junction + 4)
      .quad(G.noseC.x + mw, junction - lift, G.noseC.x + mw / 2, junction + 4)
    c.stroke(m, col(Fur.ink), stroke(2.2, { cap: 'round' }))
  }

  drawMouthAndNose(c) {
    const p = this.p, T = this.T
    const n = G.noseC, mz = G.muzzleC
    if (p.stretch > 0.4) {
      c.fill(ovalPath(mz.x, mz.y + 4, 11, 9), col(Fur.ink.opacity(0.85)))
      c.fill(this.nosePath(), col(this.noseColor))
      return
    }
    const calm = p.emotion === 'happy' || p.emotion === 'neutral' || p.emotion === 'curious'
    const blepPhase = mod(T, 11)
    const blep = (calm && p.sleep < 0.3 && p.walk < 0.3 && blepPhase < 1.1) ? sin((blepPhase / 1.1) * PI) : 0
    const tongueBlep = () => c.fill(ovalPath(n.x + 5, n.y + 13 + blep * 1.5, 6.5 * blep + 1, 6 * blep + 1), col(Fur.tongue))

    switch (p.emotion) {
      case 'angry': {
        const open = 8 + abs(sin(T * 12)) * 8
        c.fill(new Path().ellipse(mz.x - 11, mz.y - 2, 22, open), col(Fur.ink.opacity(0.85)))
        c.fill(new Path().ellipse(mz.x - 6, mz.y + open * 0.3, 12, open * 0.5), col(Fur.tongue))
        break
      }
      case 'moody': {
        const m = new Path()
        m.move(n.x - 7, n.y + 12).quad(n.x + 7, n.y + 12, n.x, n.y + 7.5)
        c.stroke(m, col(Fur.ink), stroke(2.0, { cap: 'round' }))
        break
      }
      case 'happy': case 'excited': case 'playful': case 'love': case 'alert': case 'blissful':
      case 'proud': case 'hyped': case 'vibing': case 'cozy':
        if (p.emotion === 'excited' || p.emotion === 'playful' || p.emotion === 'love' || p.emotion === 'hyped') {
          const loll = 1 + sin(T * 6) * 0.12
          c.fill(ovalPath(n.x, n.y + 14, 9.5, 10 * loll), col(Fur.tongue))
        } else if (this.species === 'dog' && p.emotion !== 'cozy' && p.emotion !== 'proud') {
          c.fill(ovalPath(n.x, n.y + 14.5, 9, 9.5), col(Fur.tongue))
          const seam = new Path()
          seam.move(n.x, n.y + 11).line(n.x, n.y + 16)
          c.stroke(seam, col(black.opacity(0.12)), 1)
        } else if (blep > 0.1) {
          tongueBlep()
        }
        this.omegaMouth(c, 4)
        this.bunnyTeeth(c)
        break
      case 'curious':
        c.stroke(ovalPath(n.x, n.y + 11, 6, 7), col(Fur.ink), 2.0)
        break
      case 'shy': this.omegaMouth(c, 0); break
      case 'worried': this.omegaMouth(c, -3); break
      case 'bored': {
        const m = new Path()
        m.move(n.x - 8, n.y + 10).line(n.x + 8, n.y + 10)
        c.stroke(m, col(Fur.ink), stroke(2.0, { cap: 'round' }))
        break
      }
      case 'eating': case 'hungry': {
        const chomp = p.emotion === 'eating' ? abs(sin(T * 14)) * 6 : 2
        c.fill(new Path().ellipse(mz.x - 9, mz.y - 1, 18, 4 + chomp), col(Fur.ink.opacity(0.85)))
        c.fill(capsulePath(mz.x + 4, mz.y + 5, 9, 10), col(Fur.tongue))
        break
      }
      case 'sad': {
        const m = new Path()
        m.move(n.x - 8, n.y + 13).quad(n.x + 8, n.y + 13, n.x, n.y + 6)
        c.stroke(m, col(Fur.ink), stroke(2.2, { cap: 'round' }))
        break
      }
      case 'sleepy':
        c.fill(ovalPath(mz.x, mz.y + 3, 9, 7), col(Fur.ink.opacity(0.85)))
        break
      default:
        if (blep > 0.1) tongueBlep()
        this.omegaMouth(c, 1)
    }
    c.fill(this.nosePath(), col(this.noseColor))
    c.fill(ovalPath(n.x - 2, n.y - 2, 3.2, 2.2), col(white.opacity(0.7)))
  }

  bunnyTeeth(c) {
    if (this.species !== 'bunny' && this.species !== 'hamster') return
    const r = this.species === 'hamster' ? { x: G.noseC.x - 3.2, y: G.noseC.y + 9, w: 6.4, h: 5 }
      : { x: G.noseC.x - 4.5, y: G.noseC.y + 8.5, w: 9, h: 7 }
    const tooth = roundedRectPath(r.x, r.y, r.w, r.h, 2)
    c.fill(tooth, col(white))
    c.stroke(tooth, col(Fur.ink.opacity(0.35)), 1)
    const line = new Path()
    line.move(G.noseC.x, r.y + 1).line(G.noseC.x, r.y + r.h - 1)
    c.stroke(line, col(Fur.ink.opacity(0.3)), 0.9)
  }

  // ------------------------------------------------------ eyes

  drawEyes(c) {
    const p = this.p, T = this.T
    const drift = ((p.emotion === 'neutral' || p.emotion === 'happy') && p.walk < 0.3)
      ? { dx: (sin(T * 0.9) + sin(T * 1.7)) * 0.14, dy: sin(T * 1.3) * 0.08 } : { dx: 0, dy: 0 }
    const lookX = (p.look.dx + drift.dx) * 3.2
    const lookY = (p.look.dy + drift.dy + ((p.prop === 'book' || p.prop === 'console') ? 0.7 * p.propAmt : 0)) * 2.6
    const size = { hamster: [20, 23], axolotl: [18, 20.5], capybara: [17.5, 20.5] }[this.species] || [22, 25.5]
    ;[G.eyeL, G.eyeR].forEach((e, i) => {
      const far = i === 0
      const ctr = P(e.x + lookX, e.y + lookY)
      this.drawEye(c, ctr, far ? size[0] - 1.5 : size[0], far ? size[1] - 1.5 : size[1], far)
    })
    this.drawBrows(c)
  }

  drawEye(c, ctr, w, h, far) {
    const p = this.p, T = this.T
    const st = stroke(3.2, { cap: 'round' })
    switch (p.emotion) {
      case 'love': {
        const pulse = 1 + sin(T * 6) * 0.10
        c.fill(heartPath(ctr, w * 1.35 * pulse), col(Fur.heart))
        c.fill(ovalPath(ctr.x - w * 0.22, ctr.y - w * 0.2, w * 0.26, w * 0.2), col(white.opacity(0.75)))
        break
      }
      case 'happy': case 'eating': case 'proud': case 'vibing': {
        const a = new Path()
        a.move(ctr.x - w * 0.55, ctr.y + 2).quad(ctr.x + w * 0.55, ctr.y + 2, ctr.x, ctr.y - h * 0.55)
        c.stroke(a, col(eyeInk), st)
        break
      }
      case 'sleepy': case 'cozy': {
        const a = new Path()
        a.move(ctr.x - w * 0.55, ctr.y).quad(ctr.x + w * 0.55, ctr.y, ctr.x, ctr.y + h * 0.42)
        c.stroke(a, col(eyeInk), stroke(3.0, { cap: 'round' }))
        break
      }
      case 'blissful': {
        const pulse = 1 + sin(T * 5) * 0.14
        const star = new Path()
        const r1 = w * 0.64 * pulse, r2 = w * 0.23 * pulse
        for (let i = 0; i < 8; i++) {
          const ang = (i * PI) / 4 - PI / 2
          const r = i % 2 === 0 ? r1 : r2
          const x = ctr.x + cos(ang) * r, y = ctr.y + sin(ang) * r * (h / w)
          if (i === 0) star.move(x, y); else star.line(x, y)
        }
        star.close()
        c.fill(star, col(Fur.heart))
        break
      }
      case 'shy': {
        const a = new Path()
        a.move(ctr.x - w * 0.5, ctr.y - 2).quad(ctr.x + w * 0.5, ctr.y - 2, ctr.x, ctr.y + h * 0.4)
        c.stroke(a, col(eyeInk), stroke(2.6, { cap: 'round' }))
        break
      }
      case 'bored': case 'moody': {
        c.fill(ovalPath(ctr.x, ctr.y + h * 0.14, w * 0.65, h * 0.33), col(eyeInk))
        const lid = new Path()
        lid.move(ctr.x - w * 0.5, ctr.y - h * 0.08).line(ctr.x + w * 0.5, ctr.y - h * 0.08)
        c.stroke(lid, col(eyeInk), stroke(2.2, { cap: 'round' }))
        break
      }
      case 'angry':
        c.fill(ovalPath(ctr.x, ctr.y + 2, w * 0.9, h * 0.55), col(eyeInk))
        break
      case 'dizzy': {
        const s = new Path()
        for (let t = 0; t <= 3.2 * PI + 1e-9; t += 0.24) {
          const r = t * 1.05
          const x = ctr.x + cos(t + T * 8) * r, y = ctr.y + sin(t + T * 8) * r
          if (t === 0) s.move(x, y); else s.line(x, y)
        }
        c.stroke(s, col(eyeInk), stroke(2.0, { cap: 'round' }))
        break
      }
      default: {
        const k = 1 - this.blink
        if (k < 0.16) {
          const a = new Path()
          a.move(ctr.x - w * 0.5, ctr.y).line(ctr.x + w * 0.5, ctr.y)
          c.stroke(a, col(eyeInk), stroke(2.8, { cap: 'round' }))
          return
        }
        const big = (p.emotion === 'alert' || p.emotion === 'excited' || p.emotion === 'curious' || p.emotion === 'hyped') ? 1.1 : 1.0
        const ew = w * big, eh = h * k * big
        const eye = ovalPath(ctr.x, ctr.y, ew, eh)
        c.fill(eye, linG([eyeInk, rgb(0.30, 0.22, 0.34)], P(ctr.x, ctr.y - eh / 2), P(ctr.x, ctr.y + eh / 2)))
        const iris = c.copy()
        iris.clipTo(eye)
        const ic = this.irisColor
        iris.fill(ovalPath(ctr.x, ctr.y + eh * 0.2, ew * 0.95, eh * 0.7),
          radG([ic.opacity(0.95), ic.opacity(0)], P(ctr.x, ctr.y + eh * 0.32), 1, ew * 0.58))
        if (this.species === 'capybara' && big === 1.0) {
          // heavy lids: she is unbothered
          const lid = c.copy()
          lid.clipTo(eye)
          const lidH = eh * 0.4
          lid.fill(rectPath(ctr.x - ew, ctr.y - eh / 2 - 2, ew * 2, lidH + 2), col(this.coat.mid))
          const ln = new Path()
          ln.move(ctr.x - ew * 0.36, ctr.y - eh / 2 + lidH).line(ctr.x + ew * 0.36, ctr.y - eh / 2 + lidH)
          c.stroke(ln, col(eyeInk), stroke(1.8, { cap: 'round' }))
        }
        const thrill = (p.emotion === 'excited' || p.emotion === 'alert' || p.emotion === 'hyped') ? 1 + sin(T * 8) * 0.12 : 1
        c.fill(ovalPath(ctr.x - ew * 0.18, ctr.y - eh * 0.22, ew * 0.44 * thrill, eh * 0.38 * thrill), col(white.opacity(0.97)))
        c.fill(ovalPath(ctr.x + ew * 0.2, ctr.y + eh * 0.22, ew * 0.19, eh * 0.16), col(white.opacity(0.75)))
        c.fill(ovalPath(ctr.x - ew * 0.27, ctr.y + eh * 0.08, ew * 0.08, eh * 0.07), col(white.opacity(0.7)))
        if (p.emotion === 'sad') {
          const t = mod(T, 2.6) / 2.6
          const ty = ctr.y + eh * 0.5 + t * 18
          c.fill(ovalPath(ctr.x + (far ? -5 : 6), ty, 4.5, 7), col(rgb(0.55, 0.78, 1.0).opacity(0.85 * (1 - t))))
        }
      }
    }
  }

  drawBrows(c) {
    const p = this.p
    if (this.species === 'dog' && !['angry', 'sad', 'hungry', 'worried', 'alert', 'moody', 'curious'].includes(p.emotion)) {
      // the two little tan dots above a puppy's eyes: the cutest marking there is
      for (const e of [G.eyeL, G.eyeR]) c.fill(ovalPath(e.x + p.look.dx * 1.5, e.y - 22, 8, 6), col(this.coat.patch.opacity(0.85)))
    }
    const brow = (e, mirrored, angle, lift) => {
      const g = c.copy()
      g.translateBy(e.x + p.look.dx * 2, e.y - 18 + lift)
      if (mirrored) g.scaleBy(-1, 1)
      g.rotateDeg(angle)
      const b = new Path()
      b.move(-5, 0).line(5, 0)
      g.stroke(b, col(Fur.ink.opacity(0.8)), stroke(2.4, { cap: 'round' }))
    }
    const both = (a, l) => { brow(G.eyeL, true, a, l); brow(G.eyeR, false, a, l) }
    switch (p.emotion) {
      case 'angry': both(-26, 3); break
      case 'sad': case 'hungry': both(20, -1); break
      case 'worried': both(28, -3); break
      case 'alert': both(-6, -4); break
      case 'moody': both(-13, 2); break
      case 'curious': brow(G.eyeL, true, 4, -2); brow(G.eyeR, false, -14, -7); break
    }
  }

  // ------------------------------------------------------ accessories

  drawHeadAccessory(ctx) {
    this.drawHeadItem(ctx, this.outfit.head)
    this.drawHeadItem(ctx, this.outfit.hair)
    this.drawFaceItem(ctx, this.outfit.face)
  }

  drawHeadItem(ctx, item) {
    const p = this.p, T = this.T
    const hw = this.headW / 2, hh = this.headH / 2
    switch (item) {
      case 'bow': {
        const c = ctx.copy()
        c.translateBy(G.headC.x + hw * 0.52, G.headC.y - hh * 0.62)
        c.rotateDeg(16 + sin(T * 2) * 2)
        const pink = rgb(0.98, 0.56, 0.72), deep = rgb(0.88, 0.38, 0.58)
        for (const sd of [-1, 1]) {
          const loop = ovalPath(sd * 11, 0, 20, 15)
          c.fill(loop, col(pink))
          c.stroke(loop, col(deep), 1.2)
          c.fill(ovalPath(sd * 12, -2.5, 8, 4), col(white.opacity(0.45)))
        }
        c.fill(ovalPath(0, 0, 9, 9), col(deep))
        c.fill(ovalPath(-1, -1.5, 3.4, 2.6), col(white.opacity(0.5)))
        break
      }
      case 'flower': {
        const c = ctx.copy()
        c.translateBy(G.headC.x - hw * 0.5, G.headC.y - hh * 0.55)
        c.rotateDeg(-14 + sin(T * 1.6) * 3)
        for (let i = 0; i < 5; i++) {
          const pe = c.copy()
          pe.rotateDeg(i * 72)
          const petal = ovalPath(0, -8, 9.5, 12)
          pe.fill(petal, col(rgb(1.0, 0.80, 0.88)))
          pe.stroke(petal, col(rgb(0.93, 0.55, 0.70).opacity(0.7)), 1)
        }
        c.fill(ovalPath(0, 0, 9, 9), col(rgb(1.0, 0.84, 0.32)))
        c.fill(ovalPath(-1.5, -1.5, 3, 3), col(white.opacity(0.6)))
        break
      }
      case 'crown': {
        const c = ctx.copy()
        c.translateBy(G.headC.x + 2, G.headC.y - hh + 5)
        c.rotateDeg(6)
        const crown = new Path()
        crown.move(-16, 2).line(-17, -15).line(-8, -7).line(0, -19).line(8, -7).line(17, -15).line(16, 2).close()
        c.fill(crown, linG([rgb(1.0, 0.90, 0.45), rgb(0.95, 0.70, 0.22)], P(0, -19), P(0, 2)))
        c.stroke(crown, col(rgb(0.80, 0.55, 0.15)), stroke(1.2, { join: 'round' }))
        for (const [x, y, cc] of [[0, -6, rgb(0.95, 0.4, 0.55)], [-9, -2, rgb(0.5, 0.7, 1)], [9, -2, rgb(0.5, 0.85, 0.6)]]) {
          c.fill(ovalPath(x, y, 4.4, 4.4), col(cc))
        }
        break
      }
      case 'headphones': {
        const band = rgb(0.98, 0.66, 0.82), cup = rgb(0.96, 0.52, 0.72)
        const arc = new Path()
        arc.arc(G.headC.x, G.headC.y + 4, hw * 0.96, 188, 352, false)
        ctx.stroke(arc, col(cup.opacity(0.55)), stroke(8.6, { cap: 'round' }))
        ctx.stroke(arc, col(band), stroke(6, { cap: 'round' }))
        for (const sd of [-1, 1]) {
          const r = { x: G.headC.x + sd * hw * 0.96 - 8, y: G.headC.y - 6, w: 16, h: 26 }
          const cupPath = roundedRectPath(r.x, r.y, r.w, r.h, 8)
          ctx.fill(cupPath, col(cup))
          ctx.stroke(cupPath, col(white.opacity(0.55)), 1.6)
          ctx.fill(ovalPath(r.x + r.w / 2, r.y + r.h / 2, 7, 12), col(white.opacity(0.4)))
        }
        break
      }
      case 'yuzu': {
        const c = ctx.copy()
        c.translateBy(G.headC.x + 4, G.headC.y - hh + 1 + sin(T * 1.8) * 0.8)
        c.rotateDeg(sin(T * 1.3) * 3 + p.look.dx * 3)
        const fruit = ovalPath(0, -6, 22, 19)
        c.fill(fruit, radG([rgb(1.0, 0.88, 0.40), rgb(1.0, 0.68, 0.20)], P(-4, -10), 1, 14))
        c.stroke(fruit, col(rgb(0.88, 0.52, 0.10).opacity(0.6)), 1.1)
        c.fill(ovalPath(-4.5, -10, 6, 3.6), col(white.opacity(0.6)))
        c.fill(ovalPath(5, -4, 1.6, 1.6), col(rgb(0.9, 0.55, 0.1).opacity(0.5)))
        const leaf = new Path()
        leaf.move(0, -15).quad(11, -21, 5, -22).quad(0, -15, 8, -13)
        c.fill(leaf, col(rgb(0.50, 0.78, 0.40)))
        break
      }
      case 'beret': {
        const c = ctx.copy()
        c.translateBy(G.headC.x + hw * 0.14, G.headC.y - hh + 7)
        c.rotateDeg(-13)
        const dome = ovalPath(0, -6, 54, 25)
        c.fill(dome, linG([rgb(1.0, 0.72, 0.78), rgb(0.92, 0.48, 0.62)], P(0, -18), P(0, 6)))
        c.stroke(dome, col(rgb(0.80, 0.36, 0.52).opacity(0.7)), 1.2)
        c.fill(ovalPath(-10, -13, 18, 5), col(white.opacity(0.4)))
        c.fill(ovalPath(2, -19, 6, 6), col(rgb(0.86, 0.40, 0.56)))
        break
      }
      case 'starClip': {
        const c = ctx.copy()
        c.translateBy(G.headC.x - hw * 0.5, G.headC.y - hh * 0.32)
        c.rotateDeg(-12 + sin(T * 2.4) * 4)
        const star = starPathOf(10)
        c.fill(star, linG([rgb(1.0, 0.94, 0.55), rgb(1.0, 0.76, 0.25)], P(0, -10), P(0, 10)))
        c.stroke(star, col(rgb(0.88, 0.60, 0.12)), stroke(1, { join: 'round' }))
        c.fill(ovalPath(-2, -3, 3.4, 3.4), col(white.opacity(0.7)))
        break
      }
      case 'partyHat': {
        const c = ctx.copy()
        c.translateBy(G.headC.x + hw * 0.12, G.headC.y - hh + 6)
        c.rotateDeg(13 + sin(T * 3) * 1.5)
        const cone = new Path()
        cone.move(-15, 3).line(0, -36).line(15, 3).close()
        c.fill(cone, linG([rgb(0.72, 0.62, 1.0), rgb(1.0, 0.62, 0.80)], P(-15, 0), P(15, -20)))
        c.stroke(cone, col(rgb(0.62, 0.46, 0.86).opacity(0.7)), stroke(1.2, { join: 'round' }))
        for (const [x, y] of [[-5, -5], [4, -12], [-1, -20], [6, -2]]) c.fill(ovalPath(x, y, 3.4, 3.4), col(white.opacity(0.85)))
        c.fill(ovalPath(0, -37, 9, 9), col(rgb(1.0, 0.90, 0.45)))
        break
      }
      case 'halo': {
        const bob = sin(T * 2) * 2
        const ring = ovalPath(G.headC.x + 2, G.headC.y - hh - 9 + bob, 42, 11)
        ctx.stroke(ring, col(rgb(1.0, 0.88, 0.4).opacity(0.35)), 9)
        ctx.stroke(ring, col(rgb(1.0, 0.86, 0.35)), 4.2)
        ctx.stroke(ring, col(white.opacity(0.55)), stroke(1.4, { dash: [5, 14] }))
        break
      }
    }
  }

  drawFaceItem(ctx, item) {
    const p = this.p
    switch (item) {
      case 'glasses': {
        const frame = rgb(0.40, 0.30, 0.52)
        for (const e of [G.eyeL, G.eyeR]) {
          const lens = ovalPath(e.x + p.look.dx * 1.2, e.y, 33, 33)
          ctx.fill(lens, col(white.opacity(0.14)))
          ctx.stroke(lens, col(frame), 2.6)
          const glint = new Path()
          glint.arc(e.x - 2, e.y, 11.5, 205, 250, false)
          ctx.stroke(glint, col(white.opacity(0.8)), stroke(2, { cap: 'round' }))
        }
        this.bridge(ctx, frame)
        break
      }
      case 'sunglasses': {
        const frame = rgb(0.22, 0.18, 0.30)
        for (const e of [G.eyeL, G.eyeR]) {
          const lens = roundedRectPath(e.x - 17, e.y - 11, 34, 25, 9)
          ctx.fill(lens, linG([rgb(0.30, 0.24, 0.42), rgb(0.14, 0.11, 0.22)], P(e.x, e.y - 11), P(e.x, e.y + 14)))
          ctx.stroke(lens, col(frame), 2.2)
          const glint = new Path()
          glint.move(e.x - 11, e.y - 3).line(e.x - 4, e.y - 8)
          ctx.stroke(glint, col(white.opacity(0.7)), stroke(2.2, { cap: 'round' }))
        }
        this.bridge(ctx, frame)
        break
      }
      case 'heartGlasses': {
        const frame = rgb(0.93, 0.42, 0.64)
        for (const e of [G.eyeL, G.eyeR]) {
          const heart = heartPath(P(e.x + p.look.dx * 1.2, e.y + 1), 40)
          ctx.fill(heart, col(rgb(1.0, 0.62, 0.80).opacity(0.5)))
          ctx.stroke(heart, col(frame), stroke(2.6, { join: 'round' }))
          ctx.fill(ovalPath(e.x - 8, e.y - 6, 7, 4), col(white.opacity(0.7)))
        }
        this.bridge(ctx, frame)
        break
      }
      case 'lashes': {
        for (const [e, sd] of [[G.eyeL, -1], [G.eyeR, 1]]) {
          ;[-62, -38, -14].forEach((_, i) => {
            const base = P(e.x + sd * 8, e.y - 9 + i * 2.5)
            const l = new Path()
            l.move(base.x, base.y).quad(base.x + sd * (13 - i), base.y - 7 + i * 2, base.x + sd * 8, base.y - 9 + i)
            ctx.stroke(l, col(Fur.ink.opacity(0.9)), stroke(2.2, { cap: 'round' }))
          })
        }
        break
      }
    }
  }

  bridge(ctx, color) {
    const b = new Path()
    b.move(G.eyeL.x + 16, G.eyeL.y - 2).quad(G.eyeR.x - 16, G.eyeR.y - 2, (G.eyeL.x + G.eyeR.x) / 2, G.eyeL.y - 8)
    ctx.stroke(b, col(color), 2.4)
  }

  drawNeckItem(ctx) {
    const p = this.p, T = this.T
    const y0 = G.headC.y + this.headH / 2 - 7
    const nx = G.neck.x
    switch (this.outfit.neck) {
      case 'scarf': {
        const red = rgb(0.93, 0.45, 0.50)
        const band = new Path()
        band.move(nx - 34, y0 + 2).quad(nx + 36, y0 - 1, nx + 2, y0 + 20)
        ctx.stroke(band, col(red.opacity(0.5)), stroke(14.5, { cap: 'round' }))
        ctx.stroke(band, col(red), stroke(12, { cap: 'round' }))
        ctx.stroke(band, col(white.opacity(0.55)), stroke(12, { dash: [3.5, 9] }))
        const swing = sin(T * 2.4 + p.gait * 0.5) * 4 + p.walk * sin(p.gait) * 5
        const tail = ctx.copy()
        tail.translateBy(nx + 22, y0 + 8)
        tail.rotateDeg(swing)
        const end = capsulePath(0, 12, 13, 28)
        tail.fill(end, col(red))
        tail.stroke(end, col(red.opacity(0.5)), 1.3)
        for (const y of [8, 17]) tail.fill(rectPath(-6.5, y, 13, 3), col(white.opacity(0.55)))
        break
      }
      case 'bandana': {
        const pink = rgb(0.98, 0.58, 0.70)
        const tri = new Path()
        tri.move(nx - 30, y0 - 1).quad(nx + 32, y0 - 3, nx + 1, y0 + 7).line(nx + 2 + sin(T * 2.2) * 1.5, y0 + 30).close()
        ctx.fill(tri, linG([pink, rgb(0.92, 0.44, 0.62)], P(nx, y0), P(nx, y0 + 30)))
        ctx.stroke(tri, col(rgb(0.82, 0.34, 0.54).opacity(0.7)), stroke(1.2, { join: 'round' }))
        for (const [dx, dy] of [[-14, 4], [-2, 12], [10, 3], [3, 21], [-9, 16]]) ctx.fill(ovalPath(nx + dx, y0 + dy, 3.6, 3.6), col(white.opacity(0.85)))
        break
      }
      case 'pearls': {
        for (let i = 0; i <= 10; i++) {
          const t = i / 10, mt = 1 - t
          const x = mt * mt * (nx - 30) + 2 * mt * t * (nx + 1) + t * t * (nx + 32)
          const y = mt * mt * (y0 + 1) + 2 * mt * t * (y0 + 24) + t * t * (y0 - 2)
          ctx.fill(ovalPath(x, y, 8.2, 8.2), radG([white, rgb(0.93, 0.90, 0.97)], P(x - 1.5, y - 1.5), 0.5, 5.5))
          ctx.stroke(ovalPath(x, y, 8.2, 8.2), col(rgb(0.82, 0.78, 0.9)), 0.7)
        }
        break
      }
      case 'bell': {
        const band = new Path()
        band.move(nx - 30, y0 + 1).quad(nx + 32, y0 - 2, nx + 1, y0 + 20)
        ctx.stroke(band, col(rgb(0.93, 0.45, 0.62)), stroke(6, { cap: 'round' }))
        ctx.stroke(band, col(white.opacity(0.35)), stroke(6, { dash: [2, 7] }))
        const bell = ctx.copy()
        bell.translateBy(nx + 3, y0 + 15)
        bell.rotateDeg(sin(T * 3 + p.gait) * 6 * (0.3 + p.walk))
        bell.fill(ovalPath(0, 5, 13, 13), radG([rgb(1.0, 0.92, 0.5), rgb(0.95, 0.72, 0.22)], P(-2, 2), 1, 9))
        bell.stroke(ovalPath(0, 5, 13, 13), col(rgb(0.82, 0.58, 0.14)), 1)
        bell.fill(rectPath(-4.5, 6.5, 9, 1.6), col(rgb(0.7, 0.48, 0.1)))
        bell.fill(ovalPath(0, 10, 3, 3), col(rgb(0.7, 0.48, 0.1)))
        break
      }
      case 'bowtie': {
        const c = ctx.copy()
        c.translateBy(nx + 2, y0 + 11)
        const cc = rgb(0.95, 0.48, 0.66), deep = rgb(0.82, 0.34, 0.54)
        for (const sd of [-1, 1]) {
          const wing = new Path()
          wing.move(0, 0).line(sd * 15, -9).quad(sd * 15, 9, sd * 19, 0).close()
          c.fill(wing, col(cc))
          c.stroke(wing, col(deep), stroke(1.1, { join: 'round' }))
        }
        c.fill(ovalPath(0, 0, 8, 10), col(deep))
        c.fill(ovalPath(-1, -2, 3, 2.4), col(white.opacity(0.5)))
        break
      }
    }
  }

  drawGroomingPaw(ctx) {
    const p = this.p, T = this.T, coat = this.coat, headW = this.headW, headH = this.headH
    if (!(p.groom > 0.02)) return
    const cycle = mod(T * 2.2, 1.0)
    const lift = sin(cycle * PI)
    const rest = P(G.headC.x - headW * 0.12, G.headC.y + headH * 0.58)
    const top = P(G.headC.x - headW * 0.30, G.headC.y - headH * 0.02)
    const x = rest.x + (top.x - rest.x) * lift
    const y = rest.y + (top.y - rest.y) * lift + (1 - p.groom) * 34
    const c = ctx.copy()
    c.opacity = min(1, p.groom * 2)
    c.translateBy(x, y)
    c.rotateDeg(-25 - lift * 20)
    const arm = capsulePath(0, 8, 12, 22)
    c.fill(arm, linG([coat.mid, coat.shade], P(0, -3), P(0, 16)))
    c.stroke(arm, col(this.rim), 1.1)
    const mitt = ovalPath(0, -5, 14, 12)
    c.fill(mitt, col(this.species === 'panda' || this.species === 'fox' ? coat.patch : coat.light))
    c.stroke(mitt, col(this.rim), 1.1)
  }
}

/** Draws one animal onto a Canvas2D context at `scale`. */
export function drawCritter(g2d, species, coatIndex, pose, scale = 1) {
  const ctx = new Ctx(g2d)
  ctx.scaleBy(scale, scale)
  new Critter(species, coatIndex, { ...defaultPose(), ...pose, outfit: outfitOf(pose.outfit) }).draw(ctx)
}

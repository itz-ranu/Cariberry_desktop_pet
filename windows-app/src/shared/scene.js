// Everything around her that isn't her: her food, the decor she's bought, the weather in her
// corner and the floating hearts. Ported from FoodView.swift and SceneView.swift.
import { rgb, white, black, P, ZERO, col, linG, radG, Path, Ctx, stroke, ovalPath, capsulePath, rectPath, roundedRectPath, heartPath } from './gfx.js'
import { Design, Fur } from './data.js'
import { starPathOf } from './critter.js'

const { sin, cos, abs, max, min, PI } = Math
const Dish = { light: rgb(0.95, 0.96, 1.0), mid: rgb(0.85, 0.89, 0.99), shade: rgb(0.70, 0.77, 0.95) }

export const fishPath = (cx, cy, w, h) => {
  const p = new Path()
  p.move(cx - w * 0.5, cy).quad(cx + w * 0.32, cy - h * 0.5, cx - w * 0.15, cy - h * 0.62)
    .quad(cx + w * 0.32, cy + h * 0.5, cx + w * 0.5, cy).quad(cx - w * 0.5, cy, cx - w * 0.15, cy + h * 0.62).close()
  p.move(cx - w * 0.46, cy).line(cx - w * 0.72, cy - h * 0.34).line(cx - w * 0.72, cy + h * 0.34).close()
  return p
}

// ---------------------------------------------------------------- food

export function drawFood(ctxIn, species, fullness) {
  const ctx = ctxIn.copy()
  ctx.translateBy(0, Design.lift)
  const cx = 150, cy = Design.ground - 4
  if (species === 'cat') drawSaucer(ctx, cx, cy + 2, fullness)
  else drawBowl(ctx, species, fullness, cx, cy)
}

function drawBowl(ctx, species, fullness, cx, cy) {
  const fill = max(0.05, fullness)
  switch (species) {
    case 'dog': {
      const bits = [[-11, -3, 6.5], [0, -7, 7], [11, -4, 6], [-6, -9, 5.5], [7, -10, 5], [-1, -12, 5]]
      bits.slice(0, max(1, Math.trunc(fill * bits.length))).forEach((b, i) => {
        const shade = i % 2 === 0 ? rgb(0.72, 0.55, 0.36) : rgb(0.82, 0.65, 0.44)
        ctx.fill(ovalPath(cx + b[0], cy - 8 + b[1] * fill, b[2], b[2] * 0.82), col(shade))
      })
      if (fullness > 0.7) drawBone(ctx, cx, cy - 15)
      break
    }
    case 'bunny':
      [[-8, -24], [4, -6], [14, 14]].slice(0, max(1, Math.ceil(fill * 3))).forEach(([dx, rot]) => {
        const c = ctx.copy()
        c.translateBy(cx + dx, cy - 4)
        c.rotateDeg(rot)
        const carrot = new Path()
        carrot.move(-5, -4).line(5, -4).quad(0, 17, 4, 8).quad(-5, -4, -4, 8)
        c.fill(carrot, linG([rgb(1.0, 0.66, 0.34), rgb(0.95, 0.50, 0.24)], P(0, -4), P(0, 17)))
        for (const y of [2, 8]) {
          const line = new Path(); line.move(-2.5, y).line(1, y)
          c.stroke(line, col(white.opacity(0.4)), stroke(1, { cap: 'round' }))
        }
        for (const a of [-26, 0, 26]) {
          const leaf = c.copy()
          leaf.translateBy(0, -4); leaf.rotateDeg(a)
          leaf.fill(ovalPath(0, -6, 4.5, 11), col(rgb(0.55, 0.78, 0.48)))
        }
      })
      break
    case 'fox': {
      const berries = [[-11, -3], [-2, -6], [9, -3], [-6, -10], [4, -11]]
      for (const b of berries.slice(0, max(1, Math.ceil(fill * berries.length)))) {
        ctx.fill(ovalPath(cx + b[0], cy - 6 + b[1], 10, 10), col(rgb(0.88, 0.28, 0.40)))
        ctx.fill(ovalPath(cx + b[0] - 2, cy - 8 + b[1], 3.4, 2.6), col(white.opacity(0.7)))
      }
      break
    }
    case 'hamster': {
      const seeds = [[-10, -2, -20], [0, -4, 15], [10, -2, 40], [-5, -8, 60], [5, -9, -30], [-12, -7, 10]]
      for (const s of seeds.slice(0, max(1, Math.ceil(fill * seeds.length)))) {
        const c = ctx.copy()
        c.translateBy(cx + s[0], cy - 6 + s[1])
        c.rotateDeg(s[2])
        c.fill(ovalPath(0, 0, 11, 6.5), col(rgb(0.36, 0.31, 0.30)))
        c.fill(ovalPath(0, 0, 3, 5.5), col(white.opacity(0.5)))
      }
      break
    }
    case 'panda':
      for (const [dx, h, lean] of [[-8, 28, -10], [2, 34, 2], [12, 26, 12]]) {
        const c = ctx.copy()
        c.translateBy(cx + dx, cy - 3)
        c.rotateDeg(lean)
        c.fill(capsulePath(0, -h / 2, 6, h), linG([rgb(0.62, 0.82, 0.50), rgb(0.45, 0.68, 0.40)], P(-3, 0), P(3, 0)))
        for (let y = -8; y > -h; y -= 9) c.fill(capsulePath(0, y, 7.5, 2.2), col(rgb(0.36, 0.55, 0.34)))
      }
      break
    case 'axolotl':
      [[-9, -3, -20], [3, -6, 10], [12, -3, 35]].slice(0, max(1, Math.ceil(fill * 3))).forEach(([dx, dy, rot]) => {
        const c = ctx.copy()
        c.translateBy(cx + dx, cy - 4 + dy)
        c.rotateDeg(rot)
        const shrimp = new Path()
        shrimp.arc(0, 0, 7, 200, 20, false)
        c.stroke(shrimp, col(rgb(1.0, 0.62, 0.62)), stroke(6, { cap: 'round' }))
        c.fill(ovalPath(6, 1, 2.2, 2.2), col(Fur.ink))
      })
      break
    case 'capybara': {
      const slice = new Path()
      slice.move(cx - 15, cy - 4).line(cx + 15, cy - 4).quad(cx - 15, cy - 4, cx, cy - 4 - 30 * max(0.3, fill))
      ctx.fill(slice, col(rgb(1.0, 0.46, 0.52)))
      for (const [dx, dy] of [[-6, -8], [3, -12], [8, -7]]) ctx.fill(ovalPath(cx + dx, cy + dy, 2.2, 3.4), col(Fur.ink.opacity(0.8)))
      break
    }
  }
  const bowl = new Path()
  bowl.move(cx - 24, cy).line(cx + 24, cy).quad(cx - 24, cy, cx, cy + 28)
  ctx.fill(bowl, linG([Dish.mid, Dish.shade], P(cx - 24, cy), P(cx + 24, cy + 22)))
  ctx.fill(capsulePath(cx, cy - 1, 52, 9), col(Dish.light))
  ctx.fill(heartPath(P(cx, cy + 11), 11), col(white.opacity(0.85)))
}

function drawBone(ctx, cx, cy) {
  const bone = new Path()
  bone.move(cx - 9, cy - 2).line(cx + 9, cy - 2)
  ctx.stroke(bone, col(Dish.light), stroke(4, { cap: 'round' }))
  for (const end of [cx - 9, cx + 9]) {
    ctx.fill(ovalPath(end, cy - 5, 5, 5), col(Dish.light))
    ctx.fill(ovalPath(end, cy + 1, 5, 5), col(Dish.light))
  }
}

function drawSaucer(ctx, cx, cy, fullness) {
  const saucer = new Path()
  saucer.move(cx - 26, cy).line(cx + 26, cy).quad(cx - 26, cy, cx, cy + 16)
  ctx.fill(saucer, linG([Dish.mid, Dish.shade], P(cx - 26, cy), P(cx + 26, cy + 12)))
  ctx.fill(capsulePath(cx, cy - 1, 56, 7), col(Dish.light))
  if (!(fullness > 0.04)) return
  const scale = 0.5 + 0.5 * fullness
  const f = ctx.copy()
  f.opacity = min(1, fullness * 1.6)
  f.translateBy(cx, cy - 8)
  f.scaleBy(scale, scale)
  f.fill(fishPath(0, 0, 34, 16), col(rgb(0.62, 0.73, 0.88)))
  f.fill(ovalPath(6, -2, 3, 3), col(Fur.ink.opacity(0.7)))
}

// ---------------------------------------------------------------- decor (bought in the Sanctuary)

export function drawDecor(ctxIn, items, scale, origin) {
  const c = ctxIn.copy()
  c.translateBy(origin.x, origin.y + Design.lift * scale)
  c.scaleBy(scale, scale)
  const ground = Design.ground
  if (items.has('fairyLights')) drawLights(c, ground)
  if (items.has('plant')) drawPlant(c, -34, ground)
  if (items.has('books')) drawBooks(c, -80, ground)
  if (items.has('teddy')) drawTeddy(c, 214, ground)
  if (items.has('lamp')) drawLamp(c, 252, ground)
  if (items.has('duck')) drawDuck(c, 190, ground)
  if (items.has('bobaCup')) drawBoba(c, -52, ground)
  if (items.has('cocoa')) drawCocoa(c, 232, ground)
}

function drawDuck(c, x, ground) {
  const yellow = rgb(1.0, 0.88, 0.40), shade = rgb(0.96, 0.74, 0.28)
  c.fill(ovalPath(x, ground - 7, 26, 15), col(shade))
  c.fill(ovalPath(x, ground - 8, 25, 14), col(yellow))
  c.fill(ovalPath(x + 7, ground - 18, 15, 14), col(yellow))
  c.fill(ovalPath(x + 15, ground - 16, 8, 4.5), col(rgb(1.0, 0.62, 0.36)))
  c.fill(ovalPath(x + 8, ground - 20, 2.6, 2.8), col(Fur.ink))
  c.fill(ovalPath(x - 3, ground - 9, 11, 7), col(shade.opacity(0.6)))
  c.fill(ovalPath(x - 6, ground - 12, 5, 2.4), col(white.opacity(0.7)))
}

function drawBoba(c, x, ground) {
  const cup = new Path()
  cup.move(x - 10, ground - 30).line(x + 10, ground - 30).line(x + 7.5, ground).line(x - 7.5, ground).close()
  c.fill(cup, linG([rgb(0.98, 0.86, 0.80), rgb(0.88, 0.68, 0.62)], P(x, ground - 30), P(x, ground)))
  c.fill(roundedRectPath(x - 11, ground - 33, 22, 4, 2), col(white.opacity(0.9)))
  c.stroke(rectPath(x + 1, ground - 46, 2.4, 14), col(rgb(0.98, 0.58, 0.72)), 2.4)
  for (const [dx, dy] of [[-4, -4], [0, -2], [4, -4.5], [-1, -7], [3, -8]]) c.fill(ovalPath(x + dx, ground + dy, 4.2, 4.2), col(rgb(0.34, 0.22, 0.24)))
  c.fill(heartPath(P(x, ground - 19), 6), col(white.opacity(0.85)))
}

function drawCocoa(c, x, ground) {
  const mug = roundedRectPath(x - 11, ground - 20, 22, 20, 6)
  c.stroke(new Path().ellipse(x + 7, ground - 16, 11, 11), col(rgb(0.86, 0.58, 0.66)), 3)
  c.fill(mug, linG([rgb(1.0, 0.78, 0.84), rgb(0.94, 0.60, 0.70)], P(x, ground - 20), P(x, ground)))
  c.fill(ovalPath(x, ground - 19, 19, 5), col(rgb(0.46, 0.28, 0.24)))
  c.fill(ovalPath(x - 3, ground - 20, 6, 2.6), col(white.opacity(0.9)))
  c.fill(ovalPath(x + 3, ground - 19.5, 5, 2.4), col(white.opacity(0.9)))
  c.fill(heartPath(P(x - 1, ground - 9), 6), col(white.opacity(0.85)))
  ;[-3, 3].forEach((dx, i) => {
    const s = new Path()
    s.move(x + dx, ground - 24).quad(x + dx, ground - 38, x + dx + (i === 0 ? 5 : -5), ground - 31)
    c.stroke(s, col(white.opacity(0.7)), stroke(1.8, { cap: 'round' }))
  })
}

function drawPlant(c, x, ground) {
  for (const [dx, rot, h] of [[-5, -28, 26], [0, 0, 32], [5, 28, 26]]) {
    const l = c.copy()
    l.translateBy(x + dx, ground - 16)
    l.rotateDeg(rot)
    const leaf = ovalPath(0, -h / 2, 11, h)
    l.fill(leaf, linG([rgb(0.62, 0.84, 0.56), rgb(0.40, 0.66, 0.44)], P(0, -h), ZERO))
    l.stroke(leaf, col(rgb(0.34, 0.56, 0.38).opacity(0.6)), 1)
  }
  const pot = new Path()
  pot.move(x - 12, ground - 17).line(x + 12, ground - 17).line(x + 9, ground + 2).line(x - 9, ground + 2).close()
  c.fill(pot, linG([rgb(1.0, 0.78, 0.68), rgb(0.92, 0.58, 0.5)], P(x, ground - 17), P(x, ground + 2)))
  c.fill(roundedRectPath(x - 13, ground - 19, 26, 5, 2.5), col(rgb(0.96, 0.66, 0.58)))
  c.fill(heartPath(P(x, ground - 7), 7), col(white.opacity(0.8)))
}

function drawBooks(c, x, ground) {
  const colours = [[rgb(0.98, 0.70, 0.80), 30, 9], [rgb(0.72, 0.80, 0.98), 26, 8], [rgb(0.98, 0.90, 0.62), 28, 8]]
  let y = ground + 1
  colours.forEach((b, i) => {
    y -= b[2]
    const r = { x: x - b[1] / 2 + (i === 1 ? 2 : -1), y, w: b[1], h: b[2] }
    c.fill(roundedRectPath(r.x, r.y, r.w, r.h, 2), col(b[0]))
    c.stroke(roundedRectPath(r.x, r.y, r.w, r.h, 2), col(black.opacity(0.15)), 1)
    c.fill(rectPath(r.x + 3, r.y + 2, 4, b[2] - 4), col(white.opacity(0.55)))
  })
}

function drawTeddy(c, x, ground) {
  const fur = rgb(0.86, 0.68, 0.52), shade = rgb(0.72, 0.54, 0.40)
  c.fill(ovalPath(x, ground - 9, 24, 22), col(fur))
  c.fill(ovalPath(x, ground - 8, 13, 13), col(rgb(0.97, 0.88, 0.78)))
  for (const dx of [-8, 8]) c.fill(ovalPath(x + dx, ground - 1, 10, 9), col(shade))
  c.fill(ovalPath(x, ground - 28, 22, 20), col(fur))
  for (const dx of [-9, 9]) { c.fill(ovalPath(x + dx, ground - 37, 9, 9), col(fur)); c.fill(ovalPath(x + dx, ground - 37, 4.5, 4.5), col(rgb(0.96, 0.74, 0.76))) }
  c.fill(ovalPath(x - 4.5, ground - 29, 3, 3.6), col(Fur.ink)); c.fill(ovalPath(x + 4.5, ground - 29, 3, 3.6), col(Fur.ink))
  c.fill(ovalPath(x, ground - 24, 7, 5), col(rgb(0.97, 0.88, 0.78)))
  c.fill(ovalPath(x, ground - 25, 3, 2.4), col(Fur.ink))
  for (const sd of [-1, 1]) c.fill(ovalPath(x + sd * 5, ground - 18, 7, 5), col(rgb(0.98, 0.58, 0.72)))
  c.fill(ovalPath(x, ground - 18, 3.5, 3.5), col(rgb(0.88, 0.42, 0.58)))
}

function drawLamp(c, x, ground) {
  c.fill(ovalPath(x, ground - 28, 80, 70), radG([rgb(1.0, 0.90, 0.6).opacity(0.45), rgb(1.0, 0.90, 0.6).opacity(0)], P(x, ground - 30), 2, 40))
  c.fill(ovalPath(x, ground - 1, 22, 7), col(rgb(0.96, 0.76, 0.82)))
  c.fill(rectPath(x - 2, ground - 34, 4, 33), col(rgb(0.88, 0.66, 0.74)))
  const shade = new Path()
  shade.move(x - 9, ground - 32).line(x + 9, ground - 32).line(x + 15, ground - 50).line(x - 15, ground - 50).close()
  c.fill(shade, linG([rgb(1.0, 0.96, 0.82), rgb(1.0, 0.82, 0.62)], P(x, ground - 50), P(x, ground - 32)))
  c.stroke(shade, col(rgb(0.86, 0.62, 0.5).opacity(0.7)), stroke(1.2, { join: 'round' }))
}

function drawLights(c, ground) {
  const string = new Path()
  string.move(-90, 14).quad(290, 14, 100, 52)
  c.stroke(string, col(rgb(0.62, 0.52, 0.5).opacity(0.7)), 1.4)
  const cols = [rgb(1.0, 0.78, 0.84), rgb(1.0, 0.94, 0.64), rgb(0.76, 0.92, 1.0), rgb(0.84, 0.80, 1.0)]
  for (let i = 0; i <= 15; i++) {
    const t = i / 15, mt = 1 - t
    const px = mt * mt * -90 + 2 * mt * t * 100 + t * t * 290
    const py = mt * mt * 14 + 2 * mt * t * 52 + t * t * 14
    const cc = cols[i % cols.length]
    c.fill(ovalPath(px, py + 5, 15, 15), col(cc.opacity(0.28)))
    c.fill(ovalPath(px, py + 5, 7, 8), col(cc))
    c.fill(ovalPath(px - 1.5, py + 3, 2.4, 2.4), col(white.opacity(0.8)))
  }
}

// ---------------------------------------------------------------- weather in her corner

/** Petals, leaves, rain or stars drifting through her corner. `t` is seconds. */
export function drawAmbient(g2d, kind, t, size) {
  const c = new Ctx(g2d)
  for (let i = 0; i < 12; i++) {
    const f = i
    const seed = (f * 0.6180339) % 1
    const speed = (kind === 'rainDrops' ? 120 : (kind === 'starSparkles' ? 0 : 22)) + seed * 14
    const travel = size.h + 30
    let y = ((t * speed + seed * travel * 3) % travel) - 15
    let x = seed * (size.w + 40) - 20
    if (kind === 'sakura' || kind === 'leaves') x += sin(t * 0.9 + f * 1.7) * 16
    else if (kind === 'starSparkles') y = ((seed * 7.3) % 1) * size.h * 0.8
    const g = c.copy()
    g.translateBy(x, y)
    switch (kind) {
      case 'sakura':
        g.rotate(t * 0.8 + f)
        g.fill(ovalPath(0, 0, 9, 6), col(rgb(1.0, 0.76, 0.84).opacity(0.9)))
        g.fill(ovalPath(-1, -1, 4, 2.5), col(white.opacity(0.6)))
        break
      case 'leaves': {
        g.rotate(t * 0.7 + f * 2)
        const cols = [rgb(0.96, 0.62, 0.30), rgb(0.88, 0.42, 0.26), rgb(0.98, 0.78, 0.36)]
        g.fill(ovalPath(0, 0, 11, 6), col(cols[i % 3].opacity(0.92)))
        const v = new Path(); v.move(-5, 0).line(5, 0)
        g.stroke(v, col(white.opacity(0.4)), 0.8)
        break
      }
      case 'rainDrops': {
        const d = new Path(); d.move(0, 0).line(-2, 9)
        g.stroke(d, col(rgb(0.62, 0.78, 1.0).opacity(0.75)), stroke(1.6, { cap: 'round' }))
        break
      }
      case 'starSparkles': {
        const twinkle = 0.45 + 0.55 * abs(sin(t * 1.6 + f * 2.1))
        const star = new Path()
        for (let k = 0; k < 8; k++) {
          const r = k % 2 === 0 ? 6 : 1.8, a = (k * PI) / 4
          const px = cos(a) * r, py = sin(a) * r
          if (k === 0) star.move(px, py); else star.line(px, py)
        }
        star.close()
        g.fill(star, col(rgb(1.0, 0.94, 0.62).opacity(twinkle)))
        break
      }
    }
  }
}

// ---------------------------------------------------------------- floating particles (hearts, zzz, confetti...)

const GLYPH = { zzz: '💤', sparkle: '✨', anger: '💢', star: '⭐️', note: '🎵', sweat: '💦' }

export function drawParticles(g2d, particles, palette) {
  const c0 = new Ctx(g2d)
  for (const p of particles) {
    const fade = min(1, (p.life / max(0.001, p.maxLife)) * 1.6)
    const c = c0.copy()
    c.opacity = fade
    c.translateBy(p.x, p.y)
    c.rotate(p.rot)
    switch (p.kind) {
      case 'heart':
        c.fill(heartPath(ZERO, p.size), col(Fur.heart))
        c.fill(ovalPath(-p.size * 0.16, -p.size * 0.16, p.size * 0.18, p.size * 0.14), col(white.opacity(0.8)))
        break
      case 'crumb':
        c.fill(ovalPath(0, 0, p.size, p.size * 0.85), col(rgb(0.55, 0.34, 0.19)))
        break
      case 'anger': {
        const r = p.size * 0.5
        for (let a = 0; a < PI * 2 - 1e-6; a += PI / 2) {
          const spike = new Path()
          spike.move(cos(a) * r * 0.35, sin(a) * r * 0.35).line(cos(a) * r, sin(a) * r)
          c.stroke(spike, col(Fur.alertAccent.opacity(0.85)), stroke(p.size * 0.16, { cap: 'round' }))
        }
        break
      }
      case 'zzz':
        c.opacity = fade
        c.text('z', 0, 0, p.size * 1.15, palette.lilac, 'heavy')
        break
      case 'confetti': {
        const col2 = palette.confetti[p.id % palette.confetti.length]
        c.scaleBy(1, 0.4 + 0.6 * abs(cos(p.rot * 1.3)))
        c.fill(roundedRectPath(-p.size / 2, -p.size / 4, p.size, p.size / 2, 1.5), col(col2))
        break
      }
      case 'bubble':
        c.stroke(ovalPath(0, 0, p.size, p.size), col(Dish.shade.opacity(0.6)), 1.2)
        c.fill(ovalPath(0, 0, p.size, p.size), col(white.opacity(0.28)))
        c.fill(ovalPath(-p.size * 0.22, -p.size * 0.22, p.size * 0.26, p.size * 0.2), col(white.opacity(0.85)))
        break
      default:
        c.text(GLYPH[p.kind] || '•', 0, 0, p.size)
    }
  }
}

// A tiny stand-in for SwiftUI's Canvas / GraphicsContext, so the pet's drawing code (ported
// from Critter.swift) reads almost line for line like the original.
//
// The one thing that matters: a SwiftUI GraphicsContext is a *value*. `var c = ctx` copies its
// transform, clip and opacity, and changing the copy never touches the original. Canvas2D has a
// single mutable state, so `Ctx` keeps its own transform/clip/opacity and replays them around
// every draw call. `copy()` is the `var c = ctx`.

export class Color {
  constructor(r, g, b, a = 1) { this.r = r; this.g = g; this.b = b; this.a = a }
  opacity(o) { return new Color(this.r, this.g, this.b, this.a * o) }
  css() {
    const h = (v) => Math.round(Math.max(0, Math.min(1, v)) * 255)
    return `rgba(${h(this.r)},${h(this.g)},${h(this.b)},${this.a})`
  }
  mix(o, t) { return new Color(this.r + (o.r - this.r) * t, this.g + (o.g - this.g) * t, this.b + (o.b - this.b) * t, this.a + (o.a - this.a) * t) }
}
export const rgb = (r, g, b, a = 1) => new Color(r, g, b, a)
export const white = rgb(1, 1, 1)
export const black = rgb(0, 0, 0)
export const clear = rgb(0, 0, 0, 0)
export const P = (x, y) => ({ x, y })
export const ZERO = P(0, 0)

// shadings
export const col = (c) => ({ kind: 'color', color: c })
export const linG = (colors, start, end) => ({ kind: 'linear', colors, start, end })
export const radG = (colors, center, r0, r1) => ({ kind: 'radial', colors, center, r0, r1 })

const deg = (d) => (d * Math.PI) / 180

/** A path recorded as operations, replayed into a Path2D when it's drawn. */
export class Path {
  constructor() { this.ops = []; this._p2d = null }
  move(x, y) { this.ops.push(['M', x, y]); return this }
  line(x, y) { this.ops.push(['L', x, y]); return this }
  quad(x, y, cx, cy) { this.ops.push(['Q', cx, cy, x, y]); return this }
  curve(x, y, c1x, c1y, c2x, c2y) { this.ops.push(['C', c1x, c1y, c2x, c2y, x, y]); return this }
  /** angles in degrees; `clockwise` follows SwiftUI's convention (y runs down). */
  arc(cx, cy, r, startDeg, endDeg, clockwise) { this.ops.push(['A', cx, cy, r, deg(startDeg), deg(endDeg), clockwise]); return this }
  close() { this.ops.push(['Z']); return this }
  ellipse(x, y, w, h) { this.ops.push(['E', x, y, w, h]); return this }
  rect(x, y, w, h) { this.ops.push(['R', x, y, w, h]); return this }
  roundedRect(x, y, w, h, r) { this.ops.push(['RR', x, y, w, h, r]); return this }

  /** A copy with a translation applied (the only `applying` the art uses). */
  translated(tx, ty) {
    const p = new Path()
    p.ops = this.ops.map((o) => {
      const [k, ...a] = o
      switch (k) {
        case 'M': case 'L': return [k, a[0] + tx, a[1] + ty]
        case 'Q': return [k, a[0] + tx, a[1] + ty, a[2] + tx, a[3] + ty]
        case 'C': return [k, a[0] + tx, a[1] + ty, a[2] + tx, a[3] + ty, a[4] + tx, a[5] + ty]
        case 'A': return [k, a[0] + tx, a[1] + ty, ...a.slice(2)]
        case 'E': case 'R': case 'RR': return [k, a[0] + tx, a[1] + ty, ...a.slice(2)]
        default: return o
      }
    })
    return p
  }

  toPath2D() {
    if (this._p2d) return this._p2d
    const p = new Path2D()
    for (const [k, ...a] of this.ops) {
      switch (k) {
        case 'M': p.moveTo(a[0], a[1]); break
        case 'L': p.lineTo(a[0], a[1]); break
        case 'Q': p.quadraticCurveTo(a[0], a[1], a[2], a[3]); break
        case 'C': p.bezierCurveTo(a[0], a[1], a[2], a[3], a[4], a[5]); break
        // SwiftUI's clockwise:false sweeps the way angles increase on screen (y down), which is
        // Canvas2D's anticlockwise=false, so the flag passes straight through.
        case 'A': p.arc(a[0], a[1], a[2], a[3], a[4], a[5]); break
        case 'Z': p.closePath(); break
        case 'E': p.ellipse(a[0] + a[2] / 2, a[1] + a[3] / 2, Math.abs(a[2]) / 2, Math.abs(a[3]) / 2, 0, 0, Math.PI * 2); break
        case 'R': p.rect(a[0], a[1], a[2], a[3]); break
        case 'RR': p.roundRect(a[0], a[1], a[2], a[3], a[4]); break
      }
    }
    this._p2d = p
    return p
  }
}

/** A shape between an ellipse and a rounded box. `square` 0..1 pushes it toward the box, `topW`/`botW`
 *  fatten or slim the upper and lower halves (an egg, or chubby cheeks), `sideY` drops the widest line. */
export function softBlob(cx, cy, w, h, o = {}) {
  const { topW = 1, botW = 1, square = 0, sideY = 0 } = o
  const k = 0.5523 + 0.2 * square
  const hw = w / 2, hh = h / 2, oy = sideY * h
  const top = P(cx, cy - hh), bot = P(cx, cy + hh), right = P(cx + hw, cy + oy), left = P(cx - hw, cy + oy)
  return new Path().move(top.x, top.y)
    .curve(right.x, right.y, cx + k * hw * topW, top.y, right.x, right.y - k * (right.y - top.y))
    .curve(bot.x, bot.y, right.x, right.y + k * (bot.y - right.y), cx + k * hw * botW, bot.y)
    .curve(left.x, left.y, cx - k * hw * botW, bot.y, left.x, left.y + k * (bot.y - left.y))
    .curve(top.x, top.y, left.x, left.y - k * (left.y - top.y), cx - k * hw * topW, top.y)
    .close()
}

export const ovalPath = (cx, cy, w, h) => new Path().ellipse(cx - w / 2, cy - h / 2, w, h)
export const capsulePath = (cx, cy, w, h) => new Path().roundedRect(cx - w / 2, cy - h / 2, w, h, Math.min(w, h) / 2)
export const rectPath = (x, y, w, h) => new Path().rect(x, y, w, h)
export const roundedRectPath = (x, y, w, h, r) => new Path().roundedRect(x, y, w, h, r)

export function heartPath(center, size) {
  const p = new Path()
  const s = size / 2, x = center.x, y = center.y
  p.move(x, y + s * 0.95)
  p.curve(x - s, y - s * 0.25, x - s * 0.55, y + s * 0.45, x - s, y + s * 0.25)
  p.arc(x - s * 0.5, y - s * 0.3, s * 0.52, 180, 0, false)
  p.arc(x + s * 0.5, y - s * 0.3, s * 0.52, 180, 0, false)
  p.curve(x, y + s * 0.95, x + s, y + s * 0.25, x + s * 0.55, y + s * 0.45)
  p.close()
  return p
}

export const stroke = (lineWidth, o = {}) => ({ lineWidth, cap: o.cap || 'butt', join: o.join || 'miter', dash: o.dash || null })

/** The drawing surface. `copy()` is Swift's `var c = ctx`. */
export class Ctx {
  constructor(g2d) {
    this.g = g2d
    this.base = g2d.getTransform()   // whatever the caller had set (device scale, a translate)
    this.m = [1, 0, 0, 1, 0, 0]   // a, b, c, d, e, f
    this.clips = []               // [{path, m}]
    this.opacity = 1
  }
  copy() {
    const c = new Ctx(this.g)
    c.base = this.base; c.m = this.m.slice(); c.clips = this.clips.slice(); c.opacity = this.opacity
    return c
  }
  _mul(n) {
    const [a, b, c, d, e, f] = this.m, [na, nb, nc, nd, ne, nf] = n
    this.m = [a * na + c * nb, b * na + d * nb, a * nc + c * nd, b * nc + d * nd, a * ne + c * nf + e, b * ne + d * nf + f]
  }
  translateBy(x, y) { this._mul([1, 0, 0, 1, x, y]) }
  scaleBy(x, y) { this._mul([x, 0, 0, y, 0, 0]) }
  rotate(radians) { const c = Math.cos(radians), s = Math.sin(radians); this._mul([c, s, -s, c, 0, 0]) }
  rotateDeg(d) { this.rotate(deg(d)) }
  /** Rotates about a pivot instead of the origin: the one transform every limb needs. */
  rotateAbout(degrees, p) { this.translateBy(p.x, p.y); this.rotateDeg(degrees); this.translateBy(-p.x, -p.y) }
  /** Scales about a pivot: squash-and-stretch anchors on the ground. */
  scaleAbout(x, y, p) { this.translateBy(p.x, p.y); this.scaleBy(x, y); this.translateBy(-p.x, -p.y) }
  clipTo(path) { this.clips.push({ path, m: this.m.slice() }) }

  _begin() {
    const g = this.g
    g.save()
    for (const cl of this.clips) { g.setTransform(this.base); g.transform(...cl.m); g.clip(cl.path.toPath2D()) }
    g.setTransform(this.base); g.transform(...this.m)
    g.globalAlpha = this.opacity
  }
  _style(sh) {
    const g = this.g
    if (sh.kind === 'color') return sh.color.css()
    let gr
    if (sh.kind === 'linear') gr = g.createLinearGradient(sh.start.x, sh.start.y, sh.end.x, sh.end.y)
    else gr = g.createRadialGradient(sh.center.x, sh.center.y, sh.r0, sh.center.x, sh.center.y, sh.r1)
    const n = sh.colors.length
    sh.colors.forEach((c, i) => gr.addColorStop(n === 1 ? 0 : i / (n - 1), c.css()))
    return gr
  }
  fill(path, shading) {
    this._begin()
    this.g.fillStyle = this._style(shading)
    this.g.fill(path.toPath2D())
    this.g.restore()
  }
  /** Centred text (a particle's emoji or letter). */
  text(str, x, y, size, color, weight = 'normal') {
    this._begin()
    const g = this.g
    g.font = `${weight === 'heavy' ? '800' : 'normal'} ${size}px ui-rounded, 'Segoe UI Emoji', 'Apple Color Emoji', 'Segoe UI', system-ui, sans-serif`
    g.textAlign = 'center'; g.textBaseline = 'middle'
    g.fillStyle = color ? color.css() : '#000'
    g.fillText(str, x, y)
    g.restore()
  }
  stroke(path, shading, style) {
    const st = typeof style === 'number' ? stroke(style) : style
    this._begin()
    const g = this.g
    g.strokeStyle = this._style(shading)
    g.lineWidth = st.lineWidth; g.lineCap = st.cap; g.lineJoin = st.join
    g.setLineDash(st.dash || [])
    g.stroke(path.toPath2D())
    g.restore()
  }
}

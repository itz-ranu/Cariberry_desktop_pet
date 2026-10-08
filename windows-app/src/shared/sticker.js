// The white die-cut border around her, like a sticker, so a pastel pet reads on any wallpaper.
// The Mac app stacks four hard white shadows (x, -x, y, -y) and then a soft black one; because each
// SwiftUI .shadow shadows what came before it, that is a square dilation of her silhouette.
// Here: draw her once, make a white silhouette, stamp it at the nine offsets, drop-shadow the
// result once, and put her on top.

const mk = (w, h) => { const c = document.createElement('canvas'); c.width = w; c.height = h; return c }
const reset = (g, c) => { g.setTransform(1, 0, 0, 1, 0, 0); g.globalCompositeOperation = 'source-over'; g.clearRect(0, 0, c.width, c.height) }

export class Sticker {
  /** `cssW` x `cssH` is the drawing area in CSS pixels; `dpr` the canvas's pixel ratio. */
  constructor(cssW, cssH, dpr) {
    this.dpr = dpr; this.w = Math.ceil(cssW * dpr); this.h = Math.ceil(cssH * dpr)
    this.pet = mk(this.w, this.h); this.sil = mk(this.w, this.h); this.dil = mk(this.w, this.h)
  }

  /** `paint(g)` draws her on a context already scaled by `dpr`. `width` is the outline in CSS pixels. */
  draw(target, paint, width) {
    const { pet, sil, dil, dpr } = this
    const pg = pet.getContext('2d'); reset(pg, pet); pg.setTransform(dpr, 0, 0, dpr, 0, 0); paint(pg)
    const sg = sil.getContext('2d'); reset(sg, sil)
    sg.drawImage(pet, 0, 0)
    sg.globalCompositeOperation = 'source-in'; sg.fillStyle = '#fff'; sg.fillRect(0, 0, sil.width, sil.height)
    // widen it sideways (into `dil`), then up and down (back into `sil`): six stamps that add up to the same
    // square as nine, because a square is separable
    const d = width * dpr
    const dg = dil.getContext('2d'); reset(dg, dil)
    dg.drawImage(sil, -d, 0); dg.drawImage(sil, 0, 0); dg.drawImage(sil, d, 0)
    reset(sg, sil)
    sg.drawImage(dil, 0, -d); sg.drawImage(dil, 0, 0); sg.drawImage(dil, 0, d)
    target.save()
    target.setTransform(1, 0, 0, 1, 0, 0)
    target.shadowColor = 'rgba(0,0,0,0.18)'; target.shadowBlur = 4 * dpr; target.shadowOffsetY = 3 * dpr
    target.drawImage(sil, 0, 0)
    target.shadowColor = 'transparent'; target.shadowBlur = 0; target.shadowOffsetY = 0
    target.drawImage(pet, 0, 0)
    target.restore()
  }
}

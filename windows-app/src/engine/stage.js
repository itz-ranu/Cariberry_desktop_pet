// The window is bigger than the pet so speech bubbles and particles have room. Ported from
// the Stage enum in Pet.swift. Scene coordinates run y-down from the window's top-left.
import { Design } from '../shared/data.js'

export const STAGE = { w: 270, h: 236 }
export const SCALES = [0.42, 0.52, 0.68]
export const SIZE_NAMES = ['Small', 'Medium', 'Large']

export const Stage = {
  scale: SCALES[1],
  setScale(s) { this.scale = s },
  get origin() { return { x: (STAGE.w - Design.width * this.scale) / 2, y: STAGE.h - Design.height * this.scale } },
  /** A point in the pet's art space, in scene coordinates. */
  p(x, y) { const o = this.origin; return { x: o.x + x * this.scale, y: o.y + (y + Design.lift) * this.scale } },
  get head() { return this.p(122, 50) },
  get aura() { return this.p(124, -14) },
  get body() { return this.p(86, 110) },
  get mouth() { return this.p(150, 84) },
  /** How far the paws sit above the bottom edge of the window. */
  get pawInset() { return STAGE.h - (this.origin.y + (Design.ground + Design.lift) * this.scale) },
  /** The part of the window that swallows clicks (y-down, window coordinates). */
  get hitRect() {
    const pad = 8, o = this.origin, s = this.scale
    const left = o.x + 30 * s - pad, right = o.x + 178 * s + pad
    const top = o.y + 2 * s - pad, bottom = o.y + (Design.ground + Design.lift) * s + pad
    return { x: left, y: top, w: right - left, h: bottom - top }
  },
}

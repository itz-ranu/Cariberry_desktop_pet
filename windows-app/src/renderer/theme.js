// The look of every window: soft milky pastel worlds, one per aesthetic (the Mac app's AppTheme).
// Sets CSS variables on a document; ui.css only ever talks in these.
import { themeInfo } from '../shared/data.js'

const num = (v) => Math.round(v * 255)
const css = (c, a = 1) => `rgba(${num(c[0])},${num(c[1])},${num(c[2])},${a})`
const GLASS_STEPS = [35, 40, 50, 55, 60, 70, 75, 80, 88, 90]

export function applyTheme(id, doc = document) {
  const t = themeInfo(id)
  const r = doc.documentElement.style
  const ink = t.dark ? [0.96, 0.92, 0.84] : [0.32, 0.26, 0.39]
  const surface = t.dark ? [0.92, 0.80, 0.66] : [1, 1, 1]
  r.setProperty('--accent', css(t.accent))
  r.setProperty('--second', css(t.second))
  r.setProperty('--hot1', css(t.hot[0]))
  r.setProperty('--hot2', css(t.hot[1]))
  r.setProperty('--hot', `linear-gradient(135deg, ${css(t.hot[0])}, ${css(t.hot[1])})`)
  r.setProperty('--hot-shadow', css(t.accent, 0.6))
  r.setProperty('--bg', css(t.top))
  r.setProperty('--bg2', css(t.bottom))
  r.setProperty('--page', `linear-gradient(180deg, ${css(t.top)}, ${css(t.bottom)})`)
  r.setProperty('--ink', css(ink))
  r.setProperty('--ink-soft', css(ink, 0.58))
  r.setProperty('--card', css(surface, t.dark ? 0.09 : 0.8))
  r.setProperty('--track', css(ink, 0.09))
  // UI.glass(x): white on the light themes, warm parchment-dark on the dark one
  for (const n of GLASS_STEPS) r.setProperty(`--glass-${n}`, css(surface, t.dark ? (n / 100) * 0.14 : n / 100))
  r.setProperty('--sage', 'rgb(168,224,199)')
  r.setProperty('--butter', 'rgb(255,224,163)')
  r.setProperty('--peach', 'rgb(255,199,173)')
  r.setProperty('--sky', 'rgb(179,217,255)')
  r.setProperty('--alert', 'rgb(232,102,115)')
  doc.documentElement.dataset.dark = t.dark ? '1' : '0'
  // (no `color-scheme` here: it would make Chromium paint an opaque canvas behind the page, and the windows are transparent)
  return t
}

export const emotionAccent = (e) => ({
  angry: 'var(--alert)', love: 'var(--second)', proud: 'var(--second)', blissful: 'var(--second)', hyped: 'var(--second)',
  cozy: 'var(--peach)', moody: 'var(--butter)', sleepy: 'var(--accent)', hungry: 'var(--butter)', worried: 'var(--butter)', shy: 'var(--second)',
}[e] || 'var(--accent)')

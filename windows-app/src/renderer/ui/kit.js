// Small building blocks shared by the control panel, the stats window and the cards: the Mac app's
// SwiftUI helpers (card, pill, bar, ring, ChipStyle, PressStyle...) as components of our own small UI engine (mini.js).
import { html, render, useState, useEffect, useRef, useMemo, useCallback } from './mini.js'
import { ICONS } from './icons.js'
import { drawCritter } from '../../shared/critter.js'
import { outfitOf } from '../../shared/data.js'
import { Sticker } from '../../shared/sticker.js'

export { html, render, useState, useEffect, useRef, useMemo, useCallback }

const clamp01 = (v) => Math.min(1, Math.max(0, v))
export const pct = (v) => Math.round(clamp01(v) * 100)

export const Icon = ({ name, size = 16, fill = false, sw = 2, style, class: cls = '' }) => html`
  <svg class="icon ${fill ? 'filled' : ''} ${cls}" width=${size} height=${size} viewBox="0 0 24 24" stroke-width=${sw} style=${style}
    aria-hidden="true" dangerouslySetInnerHTML=${{ __html: ICONS[name] || '' }} />`

export const Label = ({ children, class: cls = '' }) => html`<div class="label ${cls}">${children}</div>`

export const Card = ({ children, class: cls = '', style, big }) => html`<div class="card ${big ? 'big' : ''} ${cls}" style=${style}>${children}</div>`

/** A tinted capsule. `tint` is any CSS colour. */
export const Pill = ({ tint, children, small }) => html`
  <span class="pill ${small ? 's' : ''}" style=${{ background: `color-mix(in srgb, ${tint} ${small ? 55 : 50}%, transparent)` }}>${children}</span>`

export const Chip = ({ onClick, tint, disabled, children, title, class: cls = '' }) => html`
  <button class="chip ${cls}" style=${tint ? { '--tint': tint } : null} onClick=${onClick} disabled=${disabled} title=${title}>${children}</button>`

export const Bar = ({ value, colors = ['var(--accent)', 'var(--second)'], height = 8 }) => html`
  <div class="bar" style=${{ '--h': `${height}px` }}>
    <i style=${{ width: `${clamp01(value) * 100}%`, background: `linear-gradient(90deg, ${colors.join(', ')})` }} />
  </div>`

let ringIds = 0
/** A circular progress ring with whatever you like in the middle. */
export const Ring = ({ progress, size, line, colors = ['var(--hot1)', 'var(--hot2)'], children }) => {
  const id = useRef(`ring${++ringIds}`).current
  const r = (size - line) / 2, c = 2 * Math.PI * r
  const p = Math.max(0.001, clamp01(progress))
  return html`
    <div class="ring" style=${{ width: `${size}px`, height: `${size}px` }}>
      <svg width=${size} height=${size} viewBox="0 0 ${size} ${size}">
        <defs><linearGradient id=${id} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" style=${{ stopColor: colors[0] }} /><stop offset="1" style=${{ stopColor: colors[1] || colors[0] }} />
        </linearGradient></defs>
        <circle cx=${size / 2} cy=${size / 2} r=${r} fill="none" style=${{ stroke: 'var(--track)' }} stroke-width=${line} />
        <circle class="arc" cx=${size / 2} cy=${size / 2} r=${r} fill="none" stroke=${`url(#${id})`} stroke-width=${line} stroke-linecap="round"
          stroke-dasharray=${c} stroke-dashoffset=${c * (1 - p)} />
      </svg>
      ${children}
    </div>`
}

export const Switch = ({ on, onChange, mini, label, disabled }) => html`
  <button class="switch ${on ? 'on' : ''} ${mini ? 'mini' : ''}" role="switch" aria-checked=${!!on} aria-label=${label} disabled=${disabled}
    onClick=${() => onChange(!on)} />`

export const IconBadge = ({ name }) => html`<div class="iconbadge"><${Icon} name=${name} size=${14} /></div>`

export const ToggleRow = ({ icon, title, subtitle, on, onChange, enabled = true }) => html`
  <div class="hs g10" style=${{ opacity: enabled ? 1 : 0.45, pointerEvents: enabled ? 'auto' : 'none' }}>
    <${IconBadge} name=${icon} />
    <div class="vs g2 grow">
      <div class="b700 t13">${title}</div>
      ${subtitle && html`<div class="note s clamp2" style="font-weight:600">${subtitle}</div>`}
    </div>
    <${Switch} on=${on} onChange=${onChange} label=${title} />
  </div>`

export const Notice = ({ text, action, onAction }) => html`
  <div class="notice"><span class="note s grow clamp2" style="font-weight:600">${text}</span><${Chip} onClick=${onAction}>${action}<//></div>`

export const Seg = ({ options, value, onChange }) => html`
  <div class="seg">${options.map(([v, label]) => html`<button class=${v === value ? 'on' : ''} onClick=${() => onChange(v)}>${label}</button>`)}</div>`

/** A dropdown that lives inside the page (a native <select> opens its own window, which would make the panel think it lost focus). */
export const Select = ({ value, options, onChange, width, label, align = 'left' }) => {
  const [open, setOpen] = useState(false)
  const [pos, setPos] = useState(null)
  const btn = useRef(null)
  const cur = options.find(([v]) => v === value) || options[0]
  const toggle = () => {
    if (open) return setOpen(false)
    const r = btn.current.getBoundingClientRect()
    const h = Math.min(options.length * 30 + 8, 260)
    const below = window.innerHeight - r.bottom
    setPos({ left: align === 'right' ? r.right : r.left, minWidth: r.width, top: below >= h + 8 ? r.bottom + 4 : undefined, bottom: below >= h + 8 ? undefined : window.innerHeight - r.top + 4, maxHeight: h, right: align === 'right' })
    setOpen(true)
  }
  useEffect(() => {
    if (!open) return
    const close = (e) => { if (!e.target.closest?.('.dd-pop') && e.target !== btn.current) setOpen(false) }
    const esc = (e) => { if (e.key === 'Escape') { e.stopPropagation(); setOpen(false) } }
    window.addEventListener('pointerdown', close, true); window.addEventListener('keydown', esc, true); window.addEventListener('blur', () => setOpen(false))
    return () => { window.removeEventListener('pointerdown', close, true); window.removeEventListener('keydown', esc, true) }
  }, [open])
  return html`
    <button ref=${btn} class="select dd" style=${{ width: width ? `${width}px` : undefined }} aria-label=${label} aria-haspopup="listbox" aria-expanded=${open} onClick=${toggle}>${cur ? cur[1] : ''}</button>
    ${open && html`<div class="dd-pop" role="listbox" style=${{ position: 'fixed', top: pos.top, bottom: pos.bottom, left: pos.right ? undefined : pos.left, right: pos.right ? window.innerWidth - pos.left : undefined, minWidth: pos.minWidth, maxHeight: pos.maxHeight }}>
      ${options.map(([v, l]) => html`<button role="option" aria-selected=${v === value} class=${v === value ? 'on' : ''} onClick=${() => { setOpen(false); onChange(v) }}>${l}</button>`)}</div>`}`
}

/** Four little bars that bounce while music plays and lie flat when it doesn't. */
export const Equalizer = ({ playing, reduceMotion }) => {
  const [t, setT] = useState(0)
  useEffect(() => {
    if (!playing || reduceMotion) return
    const id = setInterval(() => setT(performance.now() / 1000), 140)
    return () => clearInterval(id)
  }, [playing, reduceMotion])
  return html`<div class="eq ${playing ? 'playing' : ''}" aria-hidden="true">${[0, 1, 2, 3].map((i) => {
    const wave = 0.5 + 0.5 * Math.sin(t * (4.2 + i * 1.3) + i * 1.9)
    const h = playing ? (reduceMotion ? 0.6 : 0.25 + 0.75 * wave) : 0.12
    return html`<i style=${{ height: `${Math.max(4, 30 * h)}px` }} />`
  })}</div>`
}

// ---------------------------------------------------------------- the pet, drawn small

const dpr = () => Math.min(3, window.devicePixelRatio || 1)

/** Draws one animal into a canvas. `ox`/`oy` shift the art inside it (the Mac header's .offset()).
 *  `animate` redraws about 11 times a second with a moving phase, only while the page is visible. */
export const CritterCanvas = ({ species, coat = 0, pose = {}, scale = 0.42, w = 70, h = 70, ox = 0, oy = 0, animate = false, circle = false, sticker = 0, style }) => {
  const ref = useRef(null)
  const poseRef = useRef(pose)
  poseRef.current = pose
  const key = `${species}|${coat}|${JSON.stringify(pose.outfit || null)}|${pose.emotion}|${pose.sit}|${pose.sleep}|${pose.collarTier}|${scale}`
  useEffect(() => {
    const canvas = ref.current
    if (!canvas) return
    const ratio = dpr()
    canvas.width = Math.ceil(w * ratio); canvas.height = Math.ceil(h * ratio)
    const g = canvas.getContext('2d')
    const stamp = sticker ? new Sticker(w, h, ratio) : null
    const paint = (phase) => {
      g.setTransform(1, 0, 0, 1, 0, 0); g.clearRect(0, 0, canvas.width, canvas.height)
      const p = poseRef.current
      const pose = { emotion: 'happy', phase, ...p, outfit: outfitOf(p.outfit) }
      if (stamp) {
        stamp.draw(g, (pg) => { pg.translate(ox, oy); drawCritter(pg, species, coat, pose, scale) }, sticker)
        return
      }
      g.setTransform(ratio, 0, 0, ratio, ox * ratio, oy * ratio)
      drawCritter(g, species, coat, pose, scale)
    }
    paint(pose.phase ?? 0.4)
    if (!animate || window.matchMedia('(prefers-reduced-motion: reduce)').matches) return
    const id = setInterval(() => { if (document.visibilityState === 'visible') paint(performance.now() / 1000) }, 90)
    return () => clearInterval(id)
  }, [key, w, h, ox, oy, animate, sticker])
  return html`<canvas ref=${ref} style=${{ width: `${w}px`, height: `${h}px`, borderRadius: circle ? '50%' : 0, display: 'block', ...style }} />`
}

/** Where to put the 200 x 194 art so it sits centred in a w x h frame, then nudged by (dx, dy): SwiftUI's frame + offset. */
export const centered = (w, h, scale, dx = 0, dy = 0) => ({ ox: (w - 200 * scale) / 2 + dx, oy: (h - 194 * scale) / 2 + dy })

// ---------------------------------------------------------------- talking to the engine

/** The page's bridge to the app (preload.cjs). */
export const cari = window.cari
/** Asks the pet page (where the engine runs) to do something; resolves with its answer. */
export const rpc = (name, ...args) => cari.invoke('rpc', name, ...args)

/** Live engine state, refreshed every `ms` while the page is visible and straight after every action. */
export function useEngine(ms = 2000) {
  const [state, setState] = useState(null)
  const [catalog, setCatalog] = useState(null)
  const alive = useRef(true)
  const pull = useCallback(async () => {
    const s = await rpc('state')
    if (alive.current && s) setState({ ...s, __at: Date.now() })
    return s
  }, [])
  useEffect(() => {
    alive.current = true
    rpc('catalog').then((c) => alive.current && setCatalog(c))
    pull()
    const id = setInterval(() => { if (document.visibilityState === 'visible') pull() }, ms)
    const onVis = () => document.visibilityState === 'visible' && pull()
    document.addEventListener('visibilitychange', onVis)
    return () => { alive.current = false; clearInterval(id); document.removeEventListener('visibilitychange', onVis) }
  }, [])
  /** Calls an engine method (or any handler) and adopts the fresh state it returns. */
  const call = useCallback(async (name, ...args) => {
    const out = await rpc(name, ...args)
    if (out && typeof out === 'object' && out.vitals) { setState({ ...out, __at: Date.now() }); return out }
    pull()
    return out
  }, [pull])
  return { state, catalog, call, pull, setState }
}

export const reduceMotion = () => window.matchMedia('(prefers-reduced-motion: reduce)').matches
export const timeText = (minutes) => {
  const m = Math.round(minutes)
  if (m >= 60) return m % 60 === 0 ? `${m / 60}h` : `${Math.floor(m / 60)}h ${m % 60}m`
  return `${m}m`
}
export const clockHour = (hour) => { const h = hour % 24, h12 = h % 12 === 0 ? 12 : h % 12; return `${h12}${h < 12 ? 'am' : 'pm'}` }
/** CSS colour for a coat tone, [r,g,b] in 0...1. */
export const rgbCss = (c, a = 1) => `rgba(${Math.round(c[0] * 255)},${Math.round(c[1] * 255)},${Math.round(c[2] * 255)},${a})`

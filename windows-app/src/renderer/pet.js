// The pet window's page: she is drawn here, and the engine (runtime.js) runs here too, so drawing and
// logic never cross a process boundary. This file is the window around her: pixels, the mouse, where
// the window sits on the screen, and the little face in the tray.
import { Stage, STAGE } from '../engine/stage.js'
import * as Dlg from '../engine/dialogue.js'
import { Ctx } from '../shared/gfx.js'
import { Critter, drawCritter } from '../shared/critter.js'
import { drawFood, drawDecor, drawAmbient, drawParticles } from '../shared/scene.js'
import { decorIsAmbient, themeInfo } from '../shared/data.js'
import { Sticker } from '../shared/sticker.js'
import { applyTheme, emotionAccent } from './theme.js'
import { boot } from './runtime.js'

const cari = window.cari
const $ = (id) => document.getElementById(id)
const rt = await boot({ cari })
const { pet, prefs, sound, host } = rt
window.__rt = rt

applyTheme(prefs.get('theme'))
cari.on('theme', (id) => applyTheme(id))
cari.on('screens', (s) => rt.setScreens(s))
rt.onSizeChanged = () => { lastSent = null }

// ------------------------------------------------------------------ the canvas

const canvas = $('stage')
const g = canvas.getContext('2d')
let dpr = 1, sticker = null
function sizeCanvas() {
  dpr = Math.min(3, window.devicePixelRatio || 1)
  canvas.width = Math.ceil(STAGE.w * dpr); canvas.height = Math.ceil(STAGE.h * dpr)
  sticker = new Sticker(STAGE.w, STAGE.h, dpr)
}
sizeCanvas()

const perf = (window.__perf = { frames: 0, drawMs: 0, ticks: 0, pause: false })      // for measuring how hard she works
function draw() {
  const t0 = performance.now()
  g.setTransform(1, 0, 0, 1, 0, 0)
  g.clearRect(0, 0, canvas.width, canvas.height)
  g.setTransform(dpr, 0, 0, dpr, 0, 0)
  const c = new Ctx(g)
  const s = Stage.scale, o = Stage.origin
  if (pet.decorOn.size) {
    drawDecor(c, pet.decorOn, s, o)
    const kind = [...pet.decorOn].find((d) => decorIsAmbient(d))
    if (kind) drawAmbient(g, kind, host.reduceMotion() ? 3 : performance.now() / 1000, { w: STAGE.w, h: STAGE.h })
  }
  // her, with the sticker outline
  const pose = pet.pose
  sticker.draw(g, (pg) => {
    const pc = new Ctx(pg)
    pc.translateBy(o.x, o.y); pc.scaleBy(s, s)
    new Critter(pet.species, pet.coatIndex, pose).draw(pc)
  }, Math.max(1.4, s * 3.6))
  g.setTransform(dpr, 0, 0, dpr, 0, 0)
  if (pet.bowl > 0) {
    const fc = new Ctx(g)
    fc.translateBy(o.x, o.y)
    fc.scaleAbout(pet.facing < 0 ? -s : s, s, { x: 100, y: 0 })
    drawFood(fc, pet.species, pet.bowl)
  }
  if (pet.particles.length) {
    const t = themeInfo(prefs.get('theme'))
    const rgb = (v) => ({ css: () => `rgb(${v.map((x) => Math.round(x * 255)).join(',')})` })
    drawParticles(g, pet.particles, { lilac: rgb(t.accent), confetti: [t.second, t.accent, [1, 0.88, 0.64], [0.66, 0.88, 0.78], [0.7, 0.85, 1], [1, 0.78, 0.68]].map(rgb) })
  }
  updateOverlay()
  perf.frames++; perf.drawMs += performance.now() - t0
}

// ------------------------------------------------------------------ the speech bubble and the close button

const bubble = $('bubble'), bubbleText = $('bubbleText'), bubbleZone = $('bubbleZone'), closeEl = $('close')
let shownText = null
function updateOverlay() {
  const text = pet.bubbleText
  if (text !== shownText) {
    shownText = text
    if (text) {
      bubbleText.textContent = text
      bubble.style.display = 'flex'
      bubble.style.animation = 'none'; void bubble.offsetWidth; bubble.style.animation = ''
      bubble.style.setProperty('--bubble-accent', emotionAccent(pet.emotion))
    } else bubble.style.display = 'none'
  }
  bubbleZone.style.height = `${Math.max(40, Stage.p(0, -18).y)}px`
  if (pet.closeButtonAt) {
    closeEl.style.display = 'block'
    closeEl.style.left = `${pet.closeButtonAt.x}px`; closeEl.style.top = `${pet.closeButtonAt.y}px`
    closeEl.classList.toggle('pressed', pet.closeButtonPressed)
  } else closeEl.style.display = 'none'
}

// ------------------------------------------------------------------ where the window sits

let lastSent = null
function syncWindow(force = false) {
  const primaryH = rt.screens().primaryH
  const x = pet.position.x - STAGE.w / 2
  const y = primaryH - pet.position.y + Stage.pawInset - STAGE.h
  if (!force && lastSent && Math.abs(x - lastSent.x) < 0.25 && Math.abs(y - lastSent.y) < 0.25) return
  lastSent = { x, y }
  cari.send('pet:bounds', { x, y, w: STAGE.w, h: STAGE.h, hit: Stage.hitRect })
}

// ------------------------------------------------------------------ the frame loop

// One wake-up per frame, no more: she asks for 12 frames a second when resting and up to 30 when moving, and the
// timer is set for exactly the next one. The cursor is sampled at the same pace (main.js), and faster only while carried.
let last = performance.now() / 1000
let lastRate = 0
function frame() {
  const t = performance.now() / 1000
  const want = pet.desiredFrameInterval
  updateLook()
  pet.tick(Math.min(0.25, t - last))
  last = t
  perf.ticks++
  if (!document.hidden && !perf.pause) draw()
  syncWindow()
  const rate = carrying ? 16 : Math.round(want * 1000)
  if (rate !== lastRate) { lastRate = rate; cari.send('cursor:rate', rate) }
  setTimeout(frame, Math.max(4, want * 1000 - (performance.now() / 1000 - t) * 1000))
}

// ------------------------------------------------------------------ the cursor: her eyes, being carried, "come here"

const cursorUp = { x: 0, y: 0 }
rt.cursorUp = cursorUp
let carrying = false, grab = { x: 0, y: 0 }
const trail = []                        // recent cursor samples while carried, for the throw
cari.on('cursor', (p) => {
  cursorUp.x = p.x; cursorUp.y = rt.screens().primaryH - p.y
  pet.cursor = cursorUp
  if (carrying) {
    pet.carry({ x: cursorUp.x - grab.x, y: cursorUp.y - grab.y })
    trail.push({ t: performance.now(), x: cursorUp.x, y: cursorUp.y })
    while (trail.length > 6) trail.shift()
  }
})

function updateLook() {
  if (pet.act === 'tap') return          // she's looking at the button she's about to press
  const head = Stage.head
  const originX = pet.position.x - STAGE.w / 2
  const originYUp = pet.position.y - Stage.pawInset
  const headScreen = { x: originX + head.x, y: originYUp + (STAGE.h - head.y) }
  const dx = Math.max(-1, Math.min(1, (cursorUp.x - headScreen.x) / 260))
  const dy = Math.max(-1, Math.min(1, (headScreen.y - cursorUp.y) / 220))
  if (Math.abs(dx - pet.look.dx) > 0.04 || Math.abs(dy - pet.look.dy) > 0.04) pet.look = { dx, dy }
  pet.nearCursor = Math.hypot(cursorUp.x - headScreen.x, cursorUp.y - headScreen.y) < 130
  // turn to face the human's cursor while loafing
  if (pet.act === 'idle' || pet.act === 'sit') {
    if (Math.abs(cursorUp.x - headScreen.x) > 90) pet.facing = cursorUp.x > headScreen.x ? 1 : -1
  }
}

// ------------------------------------------------------------------ the mouse

// The window lets clicks through everywhere except her (main.js sets it so and forwards mouse moves),
// and this flips it off while the pointer is over her.
let pressed = false, pressOrigin = null, lastPoint = null, scrubBudget = 0, ignoring = true
const setIgnore = (v) => { if (v !== ignoring) { ignoring = v; cari.send('pet:ignore', v) } }
const inHit = (x, y) => { const r = Stage.hitRect; return x >= r.x && x <= r.x + r.w && y >= r.y && y <= r.y + r.h }

window.addEventListener('mousemove', (e) => {
  if (pressed) {
    const d = Math.hypot(e.clientX - lastPoint.x, e.clientY - lastPoint.y)
    if (!carrying && Math.hypot(e.clientX - pressOrigin.x, e.clientY - pressOrigin.y) > 46) {
      carrying = true; trail.length = 0
      document.body.style.cursor = 'grabbing'
      cari.send('pet:carrying', true)
    }
    if (carrying) {
      if (pet.act !== 'carried') pet.beginCarry()
    } else {
      scrubBudget += d
      if (scrubBudget > 18) { scrubBudget = 0; pet.petMe() }
    }
    lastPoint = { x: e.clientX, y: e.clientY }
    return
  }
  const inside = inHit(e.clientX, e.clientY)
  setIgnore(!inside)
  document.body.style.cursor = inside ? 'grab' : ''
})
window.addEventListener('mousedown', (e) => {
  if (!inHit(e.clientX, e.clientY)) return
  if (e.button === 2) { cari.invoke('open', 'panel', { tab: 'home', at: 'pet' }); return }
  if (e.button !== 0) return
  pressed = true; carrying = false; scrubBudget = 0
  pressOrigin = lastPoint = { x: e.clientX, y: e.clientY }
  grab = { x: e.clientX - STAGE.w / 2, y: (STAGE.h - e.clientY) - Stage.pawInset }
})
window.addEventListener('mouseup', (e) => {
  if (!pressed) return
  pressed = false
  document.body.style.cursor = 'grab'
  if (carrying) {
    // let go with the speed your hand had, so a flick throws her
    const a = trail[0], b = trail[trail.length - 1]
    const dt = a && b ? Math.max(0.008, (b.t - a.t) / 1000) : 1
    pet.drop(a && b && b !== a ? { x: (b.x - a.x) / dt, y: (b.y - a.y) / dt } : { x: 0, y: 0 })
    cari.send('pet:carrying', false)
  } else pet.petMe()
  carrying = false
  setIgnore(!inHit(e.clientX, e.clientY))
})
window.addEventListener('contextmenu', (e) => e.preventDefault())
// if the page loses the mouse mid-press (a menu popped up, say), drop her gently instead of leaving her in the air
window.addEventListener('blur', () => { if (carrying) { carrying = false; pressed = false; pet.drop({ x: 0, y: 0 }); cari.send('pet:carrying', false) } })

// ------------------------------------------------------------------ the tray: her face, and the timer on hover

const faceCanvas = document.createElement('canvas')
faceCanvas.width = 64; faceCanvas.height = 64
let lastFaceKey = '', lastTip = ''
function updateTray() {
  const o = pet.outfit
  const key = `${pet.species}-${pet.coatIndex}-${pet.emotion}-${o.head}${o.face}`
  if (key !== lastFaceKey) {
    lastFaceKey = key
    // a neutral face reads as blank at this size, so it borrows a smile
    const mood = pet.emotion === 'neutral' || pet.emotion === 'alert' ? 'happy' : pet.emotion
    const s = 0.155 * 3.2
    const fg = faceCanvas.getContext('2d')
    fg.setTransform(1, 0, 0, 1, 0, 0); fg.clearRect(0, 0, 64, 64)
    fg.setTransform(1, 0, 0, 1, 3.2 * (10 - 116 * 0.155), 3.2 * (11 - 96 * 0.155))
    drawCritter(fg, pet.species, pet.coatIndex, { emotion: mood, phase: 0.4, outfit: { head: o.head, face: o.face } }, s)
    cari.send('tray:icon', faceCanvas.toDataURL('image/png'))
  }
  let tip = `${pet.name}: click for everything`
  const left = pet.timerRemaining
  if (left !== null) {
    const m = Math.floor(left / 60), sec = Math.floor(left % 60)
    tip = `${pet.name}: ${pet.onBreak ? '☕ break ' : 'focus '}${m}:${String(sec).padStart(2, '0')}`
  } else if (pet.lastVerdict === 'work' && pet.focusSeconds > 60) tip = `${pet.name}: ${Math.floor(pet.focusSeconds / 60)}m focused`
  else if (pet.lastVerdict === 'distraction' && pet.distractSeconds > 15) tip = `${pet.name}: 👀 I see you`
  if (tip !== lastTip) { lastTip = tip; cari.send('tray:tip', tip) }
  // moved to a screen with a different scale: redraw her crisp
  if (Math.min(3, window.devicePixelRatio || 1) !== dpr) sizeCanvas()
}
setInterval(updateTray, 1000)

// ------------------------------------------------------------------ go

rt.start()
cari.send('pet:level', prefs.get('aboveFullscreen'))
cari.send('monitor:config', { browserAwareness: !!prefs.get('browserAwareness'), focusCoaching: !!prefs.get('focusCoaching') })
syncWindow(true)
updateTray()
frame()

// entrance: she greets you with the time of day
setTimeout(() => {
  pet.say(Dlg.greeting(pet.species, pet.name), 'excited', 5)
  pet.wave()
  pet.emit('sparkle', 8, Stage.head, 50)
  sound.happy(pet.species)
}, 700)
setTimeout(() => pet.say('made with 💗 by Ranu', null, 2.6), 5800)

// the panel and cards ask her to do things through here (main.js relays them)
cari.on('rpc', async (id, name, args) => {
  let out = null
  try { out = await rt.handlers[name]?.(...args) } catch (e) { console.error('rpc', name, e) }
  cari.send('rpc:result', id, out === undefined ? null : out)
})

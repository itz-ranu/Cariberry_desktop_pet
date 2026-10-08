// The control panel: four tabs along the bottom (Home, Focus, Closet, Settings), everything a tap away.
// Opens from the tray icon or by right-clicking her. The same layout as the Mac app's PanelView.swift.
import { html, render, useState, useEffect, useRef, useEngine, Icon, Bar, CritterCanvas, centered, cari } from '../ui/kit.js'
import { applyTheme } from '../theme.js'
import { Home } from './home.js'
import { Focus } from './focus.js'
import { Closet } from './closet.js'
import { Settings } from './settings.js'

const TABS = [['home', 'Home', 'heart'], ['focus', 'Focus', 'timer'], ['closet', 'Closet', 'sparkles'], ['settings', 'Settings', 'gear']]
const VIEWS = { home: Home, focus: Focus, closet: Closet, settings: Settings }
// older links (a card's "Settings" button, the first-run welcome) still land somewhere sensible
const ALIAS = { wardrobe: 'closet', guard: 'settings' }
const tabOf = (t) => { const id = ALIAS[t] || t; return VIEWS[id] ? id : 'home' }

function greeting() {
  const h = new Date().getHours()
  if (h >= 5 && h < 12) return 'good morning ☀️'
  if (h >= 12 && h < 17) return 'hi bestie 🌷'
  if (h >= 17 && h < 22) return 'good evening 🌙'
  return 'night owl hours 🦉'
}

function Header({ s, call }) {
  const sound = s.prefs.sounds
  return html`
    <div class="hdr">
      <div class="hs g12">
        <div class="avatar">
          <${CritterCanvas} animate=${true} species=${s.species} coat=${s.coatIndex} pose=${{ emotion: s.emotion, outfit: s.outfit, collarTier: s.collarTier, sleep: s.act === 'sleep' ? 1 : 0 }}
            scale=${0.34} w=${56} h=${56} circle=${true} ...${centered(56, 56, 0.34, -2, -6)} />
        </div>
        <div class="vs g3 grow">
          <div class="name ell">${s.name}</div>
          <div class="sub ell">${greeting()} · ${s.emotionLabel}</div>
        </div>
        <button class="press circle-btn hot" title=${`Chat with ${s.name}`} aria-label="Open chat" onClick=${() => cari.invoke('open', 'chat')}><${Icon} name="chat" size=${15} sw=${2.4} /></button>
        <button class="press circle-btn ${sound ? 'glass' : 'hot'}" title=${sound ? 'Mute her voice (music keeps playing)' : 'Her voice is off. Tap to turn it back on'} aria-label=${sound ? 'Mute her voice' : 'Unmute her voice'}
          onClick=${() => call('do', 'toggleMute')}><${Icon} name=${sound ? 'speaker' : 'speakerOff'} size=${15} sw=${2.4} /></button>
      </div>
      <div class="hs g8" title=${`${s.levelTitle}`}>
        <div class="stats"><span>Lv ${s.level}</span>${s.streakDays > 0 && html`<span>🔥 ${s.streakDays}</span>`}<span>🍓 ${s.berries}</span></div>
        <div class="grow xp"><${Bar} value=${s.levelProgress} colors=${['var(--accent)', 'var(--second)']} height=${4} /></div>
      </div>
    </div>`
}

function TabBar({ tab, setTab }) {
  return html`
    <div class="tabbar" role="tablist">${TABS.map(([id, title, icon]) => html`
      <button class=${tab === id ? 'on' : ''} role="tab" aria-selected=${tab === id} onClick=${() => setTab(id)}>
        <${Icon} name=${icon} size=${18} sw=${2.3} fill=${tab === id && icon === 'heart'} /><span>${title}</span>
      </button>`)}</div>`
}

function App() {
  const q = new URLSearchParams(location.search)
  const { state: s, catalog: cat, call, pull } = useEngine(2000)
  const [tab, setTab] = useState(tabOf(q.get('tab') || 'home'))
  const [welcome, setWelcome] = useState(q.get('welcome') === '1')
  const scroller = useRef(null)
  useEffect(() => cari.on('panel:show', (o) => { setTab(tabOf(o?.tab || 'home')); setWelcome(!!o?.welcome); pull() }), [])
  useEffect(() => { if (s) applyTheme(s.prefs.theme) }, [s?.prefs.theme])
  useEffect(() => { if (scroller.current) scroller.current.scrollTop = 0 }, [tab])
  useEffect(() => {
    const onKey = (e) => e.key === 'Escape' && cari.send('panel:close')
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])
  const View = VIEWS[tab]
  return html`
    <div class="panel page">
      ${s && cat && html`
        <${Header} s=${s} call=${call} />
        <div class="scroller scroll" ref=${scroller}><div class="content"><${View} s=${s} cat=${cat} call=${call} setTab=${setTab} welcome=${welcome} /></div></div>
        <${TabBar} tab=${tab} setTab=${setTab} />`}
    </div>`
}

render(html`<${App} />`, document.getElementById('app'))

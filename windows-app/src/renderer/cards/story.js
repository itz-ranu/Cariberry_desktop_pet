// The two shareable pictures: a 9:16 "study card" for stories (a polaroid of her holding today's sign) and a
// plain card for any day in the stats window. They are drawn as web pages and photographed by the app
// (main.js renders them at 3x for a 1080 x 1920 image). Ported from StoryCard.swift and ShareCard in StatsView.swift.
import { html, CritterCanvas, timeText } from '../ui/kit.js'
import { coatsOf } from '../../shared/data.js'
import { qrDataUrl } from '../ui/qr.js'

const INK = 'rgb(87, 61, 92)'
const REPO = 'https://github.com/itz-ranu/Cariberry'
const SPARKLES = [['✨', 40, 70, 14], ['🌸', 310, 120, 16], ['⭐️', 24, 300, 12], ['💗', 330, 360, 13], ['✨', 16, 520, 15], ['🌸', 346, 560, 12], ['⭐️', 180, 40, 11], ['💗', 12, 430, 12], ['✨', 336, 250, 10]]
const RUG = { rugCoquette: 'rgb(255,199,219)', rugCottage: 'rgb(189,230,179)', rugY2K: 'rgb(255,168,204)', rugCyber: 'rgb(184,179,255)' }

let qrUri = null
const qr = () => qrUri || (qrUri = qrDataUrl(REPO, 8, 0))

const Stat = ({ emoji, value, label }) => html`
  <div class="statbox"><div style="font-size:16px;line-height:1.2">${emoji}</div><div style="font-size:17px;font-weight:900">${value}</div>
    <div class="ell" style="font-size:9px;font-weight:700;opacity:.6;max-width:100%">${label}</div></div>`

export function StoryCard({ d }) {
  const progress = Math.min(1, d.focusMinutes / Math.max(1, d.goalMinutes))
  const coats = coatsOf(d.species)
  const coat = coats[Math.min(Math.max(0, d.coat), coats.length - 1)]
  const paw = `rgb(${[coat.mid.r, coat.mid.g, coat.mid.b].map((x) => Math.round(x * 255)).join(',')})`
  const tasks = d.doneTasks.slice(0, 2)
  return html`
    <div class="story">
      <div class="c1" /><div class="c2" />
      ${SPARKLES.map(([e, x, y, s]) => html`<span class="sp" style=${{ left: `${x}px`, top: `${y}px`, fontSize: `${s}px` }}>${e}</span>`)}
      <div class="col">
        <div class="vs" style="align-items:center;gap:1px;padding-top:22px">
          <div style=${{ fontFamily: 'var(--hand)', fontSize: '25px', lineHeight: 1.1 }}>my study day ✨</div>
          <div style=${{ fontSize: '11px', fontWeight: 700, opacity: 0.55 }}>${d.date}</div>
        </div>
        <div class="polaroid">
          <div class="paper">
            <div class="photo">
              <div class="rug" style=${{ background: RUG[d.outfit.rug] || 'rgba(255,255,255,.5)' }} />
              <div class="pet"><${CritterCanvas} species=${d.species} coat=${d.coat} pose=${{ emotion: progress >= 1 ? 'proud' : 'happy', phase: 0.42, outfit: d.outfit }} scale=${0.72} w=${160} h=${156} ox=${8} oy=${8} sticker=${2} style=${{ marginBottom: '-8px' }} /></div>
              <div class="sign"><div class="board">
                <div style=${{ fontFamily: 'var(--hand)', fontSize: '25px', lineHeight: 1.05 }}>${timeText(d.focusMinutes)}</div>
                <div style=${{ fontFamily: 'var(--hand)', fontSize: '13px', opacity: 0.8 }}>focused today ${progress >= 1 ? '🏆' : '🔥'}</div>
                <div class="paws"><i style=${{ background: paw }} /><i style=${{ background: paw }} /></div>
              </div></div>
            </div>
            <div class="cap">studying with ${d.name} 🐾</div>
          </div>
          <div class="tapeS" />
        </div>
        <div class="statrow">
          <${Stat} emoji="🔥" value=${d.streak} label="day streak" />
          <${Stat} emoji="🍅" value=${d.sessions} label=${d.sessions === 1 ? 'session' : 'sessions'} />
          <${Stat} emoji="⭐️" value=${`Lv ${d.level}`} label=${d.title} />
        </div>
        <div class="tasks whitebox">
          <div style="font-size:10.5px;font-weight:900;opacity:.6;text-transform:uppercase">${tasks.length === 0 ? `tiny habits ${d.habitsDone}/${d.habitsTotal} 🌷` : 'done today ✅'}</div>
          ${tasks.length === 0 && html`<div style="height:6px;border-radius:99px;background:rgba(87,61,92,.12);overflow:hidden"><i style=${{ display: 'block', height: '100%', width: `${(d.habitsDone / Math.max(1, d.habitsTotal)) * 100}%`, background: 'rgb(242,140,184)' }} /></div>`}
          ${tasks.map((t) => html`<div class="hs g7"><span style="color:rgb(242,140,184);font-size:14px">●</span><span class="ell" style=${{ fontFamily: 'var(--hand)', fontSize: '14px' }}>${t}</span></div>`)}
          ${d.doneTasks.length > 2 && html`<div style="font-size:10.5px;font-weight:700;opacity:.55">+ ${d.doneTasks.length - 2} more</div>`}
        </div>
        <div class="ach whitebox"><span style="font-size:15px">🏆</span><span class="ell" style="font-size:17px;white-space:nowrap">${d.badges.slice(-7).join(' ')}</span><div class="sp" />
          <span style="font-size:11px;font-weight:900;opacity:.6">${d.badges.length}/${d.badgeTotal}</span></div>
        <div class="foot">
          <img class="qr" src=${qr()} alt="" />
          <div class="vs g2"><div style="font-size:13px;font-weight:900">studying with Cariberry 🐾</div><div style="font-size:10.5px;font-weight:600;opacity:.6">a tiny pet who keeps you focused</div></div>
        </div>
      </div>
    </div>`
}

export function ShareCard({ d }) {
  const progress = Math.min(1, d.focusMinutes / Math.max(1, d.goalMinutes))
  const stat = (emoji, value, label) => html`<div class="sbox"><div style="font-size:18px">${emoji}</div><div style="font-size:19px;font-weight:900">${value}</div><div style="font-size:9.5px;font-weight:700;opacity:.6">${label}</div></div>`
  return html`
    <div class="share"><div class="c1" /><div class="c2" />
      <div class="col">
        <div style="font-size:15px;font-weight:900;opacity:.7;padding-top:22px">${d.dayTitle.toLowerCase()} ✨</div>
        <${CritterCanvas} species=${d.species} coat=${d.coat} pose=${{ emotion: progress >= 1 ? 'proud' : 'happy', phase: 0.42, outfit: d.outfit }} scale=${0.82} w=${180} h=${176} ox=${8} oy=${8} sticker=${2} />
        <div class="vs" style="align-items:center;gap:2px"><div style="font-size:46px;font-weight:900;line-height:1.1">${timeText(d.focusMinutes)}</div>
          <div style="font-size:14px;font-weight:800;opacity:.65">of focus${progress >= 1 ? ' · goal reached 🏆' : ''}</div></div>
        <div class="hs g8" style="padding:0 22px;width:100%">${stat('🔥', d.streak, 'day streak')}${stat('🍅', d.sessions, 'sessions')}${stat('✅', d.tasks, 'to-dos')}</div>
        <div class="vs" style="align-items:center;gap:1px;margin-top:auto;padding-bottom:18px">
          <div style="font-size:12px;font-weight:800;opacity:.75">${d.name} · Lv ${d.level} ${d.title}</div>
          <div style="font-size:10.5px;font-weight:600;opacity:.5">${d.date} · made with Cariberry 💗</div></div>
      </div>
    </div>`
}

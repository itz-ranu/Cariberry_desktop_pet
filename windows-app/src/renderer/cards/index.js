// The floating cards (FloatingWindows.swift): the daily mood check-in, today's sticky note, the chat drawer,
// the achievement toast and the study card. card.html?kind=... picks one; main.js sizes and places the window.
import { html, render, useState, useEffect, useRef, Icon, CritterCanvas, centered, cari, rpc, reduceMotion } from '../ui/kit.js'
import { applyTheme } from '../theme.js'
import { StoryCard, ShareCard } from './story.js'

const q = new URLSearchParams(location.search)
const kind = q.get('kind') || 'mood'

// ---------------------------------------------------------------- daily mood check-in

const MOOD_TINT = { radiant: 'var(--butter)', cozy: 'var(--peach)', stressed: 'var(--accent)', tired: 'var(--sky)', excited: 'var(--second)' }

function MoodCard() {
  const [moods, setMoods] = useState([])
  useEffect(() => { rpc('catalog').then((c) => setMoods(c.moods)) }, [])
  const choose = (m) => cari.invoke('mood:chosen', m)
  return html`
    <div class="moodcard drag fadein">
      <div class="vs g3" style="align-items:center">
        <div style="font-size:17px;font-weight:900">How are we feeling today, bestie?</div>
        <div class="soft" style="font-size:12px;font-weight:600">no wrong answer. I'll match your vibe 💗</div>
      </div>
      <div class="opts nodrag">${moods.map((m) => html`
        <button class="press opt" style=${{ '--t': MOOD_TINT[m.id] }} onClick=${() => choose(m.id)} aria-label=${m.title}>
          <div style="font-size:26px;line-height:1.2">${m.emoji}</div><div style="font-size:10.5px;font-weight:800">${m.title}</div></button>`)}</div>
      <button class="nodrag soft" style="font-size:11.5px;font-weight:700" onClick=${() => choose(null)}>maybe later</button>
    </div>`
}

// ---------------------------------------------------------------- sticky note

function NoteCard() {
  const [d, setD] = useState(null)
  const [pinned, setPinned] = useState(false)
  useEffect(() => { rpc('noteData').then((n) => { setD(n); setPinned(n.pinned); rpc('noteShown') }) }, [])
  const toggle = async () => { const v = !pinned; setPinned(v); await rpc('setNotePinned', v); cari.send('card:pin', v) }
  if (!d) return null
  const brown = 'rgb(107, 77, 102)'
  return html`
    <div class="notewrap drag fadein">
      <div class="note-paper">
        <div class="hs g8"><span style=${{ fontFamily: 'var(--hand)', fontSize: '15px', fontWeight: 700, color: brown }}>${d.moodInfo.emoji} today's note</span><div class="sp" />
          <button class="nodrag" style=${{ color: brown, opacity: pinned ? 0.95 : 0.6 }} onClick=${toggle} title=${pinned ? 'Unpin: let it float above your windows' : 'Pin it to your desktop'} aria-label="Pin"><${Icon} name=${pinned ? 'pin' : 'pinOff'} size=${12} sw=${2.6} fill=${pinned} /></button>
          <button class="nodrag" style=${{ color: brown, opacity: 0.6 }} onClick=${() => cari.send('card:close')} title="Put it away" aria-label="Close"><${Icon} name="x" size=${11} sw=${3} /></button></div>
        <div style=${{ fontFamily: 'var(--hand)', fontSize: '18px', lineHeight: 1.25, color: 'rgb(77, 56, 82)' }}>${d.text}</div>
        <div class="sp" />
        <div style=${{ fontFamily: 'var(--hand)', fontSize: '12px', lineHeight: 1.3, color: brown, opacity: 0.8, whiteSpace: 'pre-line' }}>${d.extras}</div>
      </div>
      <div class="tape" />
    </div>`
}

// ---------------------------------------------------------------- achievement toast

function Toast() {
  const [b, setB] = useState(null)
  useEffect(() => { const off = cari.on('toast:data', setB); cari.invoke('toast:ready').then((x) => x && setB(x)); return off }, [])
  if (!b) return null
  return html`
    <div class="toast fadein">
      <div class="em">${b.emoji}</div>
      <div class="vs g2" style="min-width:0">
        <div style="font-size:10.5px;font-weight:900;opacity:.6;letter-spacing:.4px;text-transform:uppercase">achievement unlocked ✨</div>
        <div class="ell" style="font-size:17px;font-weight:900">${b.title}</div>
        <div class="ell" style="font-size:11px;font-weight:600;opacity:.6">${b.detail}  ·  +15 🍓</div>
      </div>
    </div>`
}

// ---------------------------------------------------------------- chat drawer

const EMPTY_CHAT = { messages: [], thinking: false, status: '', brain: false, name: 'Cariberry', species: 'cat', coat: 0, outfit: {}, emotion: 'happy' }

function Chat() {
  const [st, setSt] = useState(EMPTY_CHAT)
  const [text, setText] = useState('')
  const logRef = useRef(null), inputRef = useRef(null)
  useEffect(() => {
    const off = cari.on('chat:state', setSt)
    cari.invoke('chat:open').then((s) => s && setSt(s))
    inputRef.current?.focus()
    const onKey = (e) => e.key === 'Escape' && cari.send('card:close')
    window.addEventListener('keydown', onKey)
    return () => { off(); window.removeEventListener('keydown', onKey) }
  }, [])
  useEffect(() => { logRef.current?.scrollTo({ top: 1e6, behavior: reduceMotion() ? 'auto' : 'smooth' }) }, [st.messages.length, st.messages[st.messages.length - 1]?.text, st.thinking])
  const send = () => { const t = text.trim(); if (!t) return; cari.send('chat:send', t); setText('') }
  return html`
    <div class="chat fadein">
      <div class="head drag">
        <div class="av"><${CritterCanvas} animate=${true} species=${st.species} coat=${st.coat} pose=${{ emotion: st.emotion, outfit: st.outfit }} scale=${0.26} w=${40} h=${40} circle=${true} ...${centered(40, 40, 0.26, -2, -5)} /></div>
        <div class="vs g2 grow"><div style="font-size:14px;font-weight:900">🐾 Cranberry AI Bestie</div>
          <div class="hs g4"><i style=${{ width: '6px', height: '6px', borderRadius: '50%', background: st.brain ? '#34c759' : 'var(--butter)' }} />
            <span class="soft" style="font-size:10.5px;font-weight:600">${st.brain ? 'brain connected' : `chatting as ${st.name}`}</span></div></div>
        <button class="nodrag soft" onClick=${() => cari.send('card:close')} aria-label="Close chat"><${Icon} name="xCircle" size=${19} sw=${2} /></button>
      </div>
      ${!st.brain && html`
        <div class="banner"><span style="font-size:14px">💡</span>
          <span class="grow" style="font-size:10.5px;font-weight:600;line-height:1.3">Connect a chat brain in Settings for homework help & email rewrites. I can still chat and do things without it.</span>
          <button class="hotbtn" style="font-size:11px;font-weight:900;padding:5px 10px" onClick=${() => cari.invoke('open', 'panel', { tab: 'settings' })}>Settings</button></div>`}
      <div class="log" ref=${logRef}>
        ${st.messages.map((m) => html`<div class="msg ${m.role === 'user' ? 'user' : ''}"><div class="b">${m.text}</div></div>`)}
        ${st.thinking && html`<div class="typing"><i /><i /><i /></div>`}
        ${st.status && html`<div class="note s" style="padding-left:4px;font-weight:600">${st.status}</div>`}
      </div>
      <div class="inbar">
        <input ref=${inputRef} placeholder="Talk to Cranberry..." value=${text} maxlength="2000" onInput=${(e) => setText(e.target.value)} onKeyDown=${(e) => e.key === 'Enter' && send()} aria-label="Message" />
        <button class="send press" disabled=${!text.trim()} onClick=${send} aria-label="Send"><${Icon} name="send" size=${14} sw=${2.2} fill=${true} /></button>
      </div>
    </div>`
}

// ---------------------------------------------------------------- the study card preview (save, copy, show)

function StoryPreview() {
  const [d, setD] = useState(null)
  const [note, setNote] = useState('')
  useEffect(() => { rpc('storyData').then(setD) }, [])
  const act = async (what) => {
    const r = await cari.invoke(`story:${what}`)
    setNote(r?.ok ? { save: 'saved to your Desktop 💌', copy: 'copied! paste it into your story 💌', show: 'opened its folder 📂' }[what] : 'couldn\'t do that 😟')
    setTimeout(() => setNote(''), 3500)
  }
  if (!d) return null
  return html`
    <div class="storyprev drag fadein">
      <div class="frame"><div class="scaled"><${StoryCard} d=${d} /></div>
        <button class="nodrag" style="position:absolute;top:8px;right:8px;width:22px;height:22px;border-radius:50%;background:rgba(0,0,0,.45);color:#fff;display:grid;place-items:center" onClick=${() => cari.send('card:close')} aria-label="Close"><${Icon} name="x" size=${10} sw=${3.4} /></button></div>
      <div class="hs g6 nodrag"><button class="chip" onClick=${() => act('save')}>Save</button><button class="chip blush" onClick=${() => act('copy')}>Copy</button><button class="chip sage" onClick=${() => act('show')}>Show file</button></div>
      <div class="note s" style="height:14px;font-weight:700">${note}</div>
    </div>`
}

// ---------------------------------------------------------------- pages that are only ever photographed

function Photo({ Comp }) {
  const d = JSON.parse(q.get('data') || '{}')
  useEffect(() => { document.fonts.ready.then(() => requestAnimationFrame(() => setTimeout(() => { document.body.dataset.ready = '1' }, 120))) }, [])
  return html`<${Comp} d=${d} />`
}

const PAGES = {
  mood: MoodCard, note: NoteCard, toast: Toast, chat: Chat, story: StoryPreview,
  storycard: () => html`<${Photo} Comp=${StoryCard} />`, sharecard: () => html`<${Photo} Comp=${ShareCard} />`,
}

async function main() {
  const theme = q.get('theme') || (await cari.invoke('theme:get'))
  applyTheme(theme)
  cari.on('theme', applyTheme)
  render(html`<${PAGES[kind] || MoodCard} />`, document.getElementById('app'))
}
main()

// The Focus tab: study with me (the timer), the sounds, today's to-dos and the tiny habits.
import { html, useState, Icon, Label, Card, Chip, Ring, Select, Bar, Equalizer, timeText, reduceMotion } from '../ui/kit.js'
import { STATIONS, NATURE } from '../ambience.js'
import { useCountdown, clock } from './parts.js'

const PRESETS = [15, 25, 45, 60, 90]
const GOAL_CHOICES = [15, 30, 45, 60, 90, 120, 180, 240]

// ---------------------------------------------------------------- the timer

function RunningTimer({ s, call, left }) {
  const t = s.timer
  const progress = t.total > 0 ? 1 - left / t.total : 0
  return html`
    <div class="vs g12 center" style="align-items:stretch">
      <${Label}>${t.isBreak ? '🧋 Break time' : '📖 Studying together'}<//>
      <div class="hs" style="justify-content:center">
        <${Ring} progress=${progress} size=${140} line=${13} colors=${t.isBreak ? ['var(--sage)', 'var(--sky)'] : undefined}>
          <div class="vs center"><div class="mono" style="font-size:32px;font-weight:900">${clock(left)}</div>
            <div class="soft" style="font-size:12px;font-weight:700">${t.isBreak ? 'sip sip' : 'locked in'}</div></div>
        <//>
      </div>
      ${!t.isBreak && t.intention && html`<div class="clamp2 center" style="font-size:13px;font-weight:700">“${t.intention}”</div>`}
      <div class="hs" style="justify-content:center"><${Chip} class="alert" onClick=${() => call('do', 'stopTimer')}>${t.isBreak ? 'Skip break' : 'Stop timer'}<//></div>
    </div>`
}

function IdleTimer({ s, call }) {
  const [intention, setIntention] = useState(s.timer.intention || '')
  const [mins, setMins] = useState(25)
  const start = () => { call('setIntention', intention).then(() => call('startFocus', mins)) }
  return html`
    <div class="vs g12">
      <${Label}>Study with me 📖<//>
      <input class="field" placeholder="What are you working on?" maxlength="80" value=${intention} onInput=${(e) => setIntention(e.target.value)}
        onKeyDown=${(e) => e.key === 'Enter' && start()} aria-label="What are you working on?" />
      <div class="chips">${PRESETS.map((m) => html`<button class="chipbtn ${mins === m ? 'on' : ''}" aria-pressed=${mins === m} onClick=${() => setMins(m)}>${m}m</button>`)}</div>
      <button class="press hotbtn cta" onClick=${start}>Start ${mins} min focus ✨</button>
      <div class="note">She'll sit beside you with a book, and bring boba on your break.</div>
    </div>`
}

function Timer({ s, call }) {
  const left = useCountdown(s.timer, s.__at)
  return html`<${Card}>${left !== null ? html`<${RunningTimer} s=${s} call=${call} left=${left} />` : html`<${IdleTimer} s=${s} call=${call} />`}<//>`
}

// ---------------------------------------------------------------- today's goal

function Goal({ s, call }) {
  const choices = [...new Set([...GOAL_CHOICES, s.focus.goal])].sort((a, b) => a - b)
  return html`
    <${Card}>
      <div class="vs g10">
        <div class="hs g8">
          <${Label}>Today<//><div class="sp" />
          <span class="soft" style="font-size:12px;font-weight:800">🔥 ${s.streakDays} day${s.streakDays === 1 ? '' : 's'} · ✅ ${s.focus.sessions} session${s.focus.sessions === 1 ? '' : 's'}</span>
        </div>
        <div class="hs g10"><div class="grow"><${Bar} value=${s.focus.progress} colors=${['var(--hot1)', 'var(--hot2)']} height=${10} /></div>
          <span style="font-size:13px;font-weight:900;white-space:nowrap">${timeText(s.focus.today)} of</span>
          <${Select} width=${74} value=${s.focus.goal} label="Daily goal" align="right" options=${choices.map((m) => [m, timeText(m)])} onChange=${(m) => call('setGoal', m)} /></div>
      </div>
    <//>`
}

// ---------------------------------------------------------------- sounds

function Sounds({ s, cat, call }) {
  const A = cat.ambience
  const playing = s.music.playing
  const station = s.music.ambience === 'off' ? 'lofi' : s.music.ambience
  const info = A[station]
  const rm = reduceMotion()
  return html`
    <${Card}>
      <div class="vs g12">
        <div class="hs g12">
          <button class="press hotbtn" style=${{ width: '48px', height: '48px', borderRadius: '50%', flex: 'none', boxShadow: '0 3px 8px var(--hot-shadow)' }}
            onClick=${() => call('do', 'toggleAmbienceNow')} title=${playing ? 'Pause the music' : `Play ${info.title}`} aria-label=${playing ? 'Pause music' : 'Play music'}>
            <${Icon} name=${playing ? 'pause' : 'play'} size=${20} fill=${true} style=${{ marginLeft: playing ? 0 : '3px' }} />
          </button>
          <div class="vs g2 grow">
            <div class="ell" style="font-size:15px;font-weight:900">${info.emoji} ${info.title}</div>
            <div class="note ell">${playing ? 'she\'s bopping along 🎶' : info.mood}</div>
          </div>
          <${Equalizer} playing=${playing} reduceMotion=${rm} />
        </div>
        <div class="chips">${[...STATIONS, ...NATURE].map((k) => html`
          <button class="chipbtn ${station === k ? 'on' : ''}" title=${A[k].mood} aria-pressed=${station === k} onClick=${() => call('do', 'chooseAmbience', k)}>${A[k].emoji} ${A[k].short}</button>`)}</div>
        <div class="hs g8">
          <${Icon} name="speakerLow" size=${13} class="soft" />
          <input type="range" min="0.05" max="1" step="0.01" value=${s.music.volume} style=${{ '--v': `${((s.music.volume - 0.05) / 0.95) * 100}%` }}
            onInput=${(e) => call('pref', 'ambienceVolume', Number(e.target.value))} aria-label="Volume" />
          <${Icon} name="speaker" size=${14} class="soft" />
        </div>
      </div>
    <//>`
}

// ---------------------------------------------------------------- to-dos and habits

function Tasks({ s, call }) {
  const [draft, setDraft] = useState('')
  const add = () => { if (!draft.trim()) return; call('do', 'addTask', draft); setDraft('') }
  return html`
    <${Card}>
      <div class="vs g10">
        <div class="hs"><${Label}>To-dos<//><div class="sp" />
          ${s.tasks.some((t) => t.done) && html`<button class="soft" style="font-size:12px;font-weight:800" onClick=${() => call('do', 'clearDoneTasks')}>Clear done</button>`}</div>
        <div class="hs g8">
          <input class="field" placeholder="Add a tiny task…" maxlength="120" value=${draft} onInput=${(e) => setDraft(e.target.value)} onKeyDown=${(e) => e.key === 'Enter' && add()} aria-label="Add a task" />
          <button class="press circle-btn hot" style="width:36px;height:36px;opacity:${draft.trim() ? 1 : 0.4}" disabled=${!draft.trim()} onClick=${add} aria-label="Add task"><${Icon} name="plus" size=${15} sw=${3} /></button>
        </div>
        ${s.tasks.length === 0
          ? html`<div class="note">Nothing here yet. Add one small thing, and she'll cheer when you finish it.</div>`
          : html`<div class="vs g8">${s.tasks.map((t) => html`
              <div class="task ${t.done ? 'done' : ''}">
                <button onClick=${() => call('do', 'toggleTask', t.id)} aria-label=${t.done ? 'Mark not done' : 'Mark done'}>
                  <${Icon} name=${t.done ? 'checkCircle' : 'circle'} size=${22} sw=${2.2} style=${{ color: t.done ? 'var(--hot1)' : 'var(--ink-soft)' }} /></button>
                <span class="t clamp2 grow">${t.title}</span>
                <button class="soft" style="width:24px;height:24px;display:grid;place-items:center" onClick=${() => call('do', 'removeTask', t.id)} aria-label="Delete task"><${Icon} name="x" size=${12} sw=${3} /></button>
              </div>`)}</div>`}
      </div>
    <//>`
}

function Habits({ s, call }) {
  const [open, setOpen] = useState(false)
  const done = s.habits.filter((h) => h.done).length
  const all = done === s.habits.length
  return html`
    <${Card}>
      <div class="vs g10">
        <button class="hs g8 fill" onClick=${() => setOpen(!open)} aria-expanded=${open}>
          <${Label}>Tiny habits 🌷<//><div class="sp" />
          <span style="font-size:12px;font-weight:900" class=${all ? '' : 'soft'}>${all ? 'all done 🥹' : `${done}/${s.habits.length}`}</span>
          <${Icon} name="chevronRight" size=${12} sw=${3} class="soft" style=${{ transform: open ? 'rotate(90deg)' : 'none', transition: 'transform .2s' }} />
        </button>
        ${open && html`
          <div class="vs g10">
            ${s.habits.map((h) => html`
              <button class="hs g10" onClick=${() => call('do', 'toggleHabit', h.id)} aria-label=${`${h.title}, ${h.done ? 'done' : 'not done'}`}>
                <${Icon} name=${h.done ? 'checkCircle' : 'circle'} size=${21} sw=${2.2} style=${{ color: h.done ? 'var(--hot1)' : 'var(--ink-soft)' }} />
                <span style=${{ fontSize: '13px', fontWeight: 700, color: h.done ? 'var(--ink-soft)' : 'var(--ink)', textDecoration: h.done ? 'line-through' : 'none' }}>${h.emoji} ${h.title}</span>
                <span class="sp" />
                ${h.auto && !h.done && html`<span class="soft" style="font-size:11px;font-weight:800">auto</span>`}
              </button>`)}
            <div class="note">${`each one is +${s.habitRewards.xp} xp and ${s.habitRewards.berries} 🍓, and finishing them all is +${s.habitRewards.bonus} 🍓`}</div>
          </div>`}
      </div>
    <//>`
}

export function Focus(p) {
  return html`<${Timer} ...${p} /><${Goal} ...${p} /><${Sounds} ...${p} /><${Tasks} ...${p} /><${Habits} ...${p} />`
}

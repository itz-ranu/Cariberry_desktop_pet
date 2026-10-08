// The Home tab: today's focus with one big button, a few ways to look after her, how you're feeling, and what she sees.
// Everything else (the radio, to-dos, habits) lives on the Focus tab, and the trophies in the stats window.
import { html, useState, Icon, Label, Card, Chip, Ring, Bar, Notice, pct, timeText, rpc, cari } from '../ui/kit.js'
import { useCountdown, clock, Heading, Disclosure } from './parts.js'

// ---------------------------------------------------------------- today

function Today({ s, call, setTab }) {
  const left = s.tasks.filter((t) => !t.done).length
  const remaining = useCountdown(s.timer, s.__at)
  const t = s.timer
  if (remaining !== null) {
    const progress = t.total > 0 ? 1 - remaining / t.total : 0
    return html`
      <${Card}>
        <div class="vs g12">
          <div class="hs g14">
            <${Ring} progress=${progress} size=${76} line=${9} colors=${t.isBreak ? ['var(--sage)', 'var(--sky)'] : undefined}>
              <div class="mono" style="font-size:16px;font-weight:900">${clock(remaining)}</div>
            <//>
            <div class="vs g3 grow">
              <${Label}>${t.isBreak ? 'Break time 🧋' : 'Studying together 📖'}<//>
              <div class="clamp2" style="font-size:15px;font-weight:800">${!t.isBreak && t.intention ? `“${t.intention}”` : t.isBreak ? 'sip sip' : 'locked in'}</div>
            </div>
          </div>
          <${Chip} class="alert" onClick=${() => call('do', 'stopTimer')}>${t.isBreak ? 'Skip break' : 'Stop timer'}<//>
        </div>
      <//>`
  }
  return html`
    <${Card}>
      <div class="vs g12">
        <button class="hs g14 fill" onClick=${() => setTab('focus')} aria-label="Open Focus">
          <${Ring} progress=${s.focus.progress} size=${76} line=${9}>
            <div style="font-size:16px;font-weight:900">${pct(s.focus.progress)}%</div>
          <//>
          <div class="vs g3 grow">
            <${Label}>Today's focus<//>
            <div style="font-size:19px;font-weight:900">${timeText(s.focus.today)} <span class="soft" style="font-size:14px;font-weight:700">of ${timeText(s.focus.goal)}</span></div>
            <div class="note">${left === 0 ? 'no tasks waiting ✨' : `${left} task${left === 1 ? '' : 's'} to go`}</div>
          </div>
          <${Icon} name="chevronRight" size=${14} sw=${2.6} class="soft" />
        </button>
        <button class="press hotbtn cta" onClick=${() => call('startFocus', 25)}>Start 25 min focus ✨</button>
      </div>
    <//>`
}

// ---------------------------------------------------------------- care

function Care({ s, call }) {
  const [more, setMore] = useState(false)
  const napping = s.act === 'sleep'
  // [emoji, label, tooltip, colour, highlighted?, action]
  const main = [
    ['🍖', 'Feed', 'A full meal', 'var(--peach)', false, () => call('do', 'feed')],
    ['🎾', 'Play', 'Zoomies! (or a happy dance if she\'s staying put)', 'var(--sky)', false, () => call('do', 'play')],
    ['🫶', 'Pet', 'Scritch scritch', 'var(--second)', false, () => call('do', 'petMe')],
    [s.staying ? '📍' : '🪑', s.staying ? 'Staying' : 'Stay', s.staying ? 'She\'s sitting still. Tap to let her roam again.' : 'Tell her to sit still right where she is', 'var(--sage)', s.staying, () => call('do', 'toggleStay')],
  ]
  const extra = [
    ['🦴', 'Treat', 'A little snack', 'var(--butter)', false, () => call('do', 'feed', true)],
    ['📣', 'Come', 'Closes this, then she runs to your cursor. Move it where you want her!', 'var(--accent)', false, () => { cari.send('panel:close'); rpc('come') }],
    ['💃', 'Dance', 'A little dance party', 'var(--second)', false, () => call('do', 'dance')],
    [napping ? '☀️' : '😴', napping ? 'Wake' : 'Nap', napping ? 'Rise and shine' : 'Tuck her in', 'var(--accent)', false, () => (napping ? call('wake') : call('do', 'nap'))],
  ]
  const grid = (tiles) => html`<div class="care">${tiles.map(([e, l, tip, tint, on, act]) => html`
    <button class="press ${on ? 'on' : ''}" style=${{ '--t': tint }} title=${tip} aria-label=${l} onClick=${act}><div class="e">${e}</div><div class="l">${l}</div></button>`)}</div>`
  return html`
    <div class="section">
      <${Heading} right=${html`<${Disclosure} label=${more ? 'Less' : 'More'} open=${more} onToggle=${() => setMore(!more)} />`}>Look after her<//>
      ${grid(main)}
      ${more && grid(extra)}
    </div>`
}

// ---------------------------------------------------------------- mood

function Mood({ s, cat, call }) {
  const cur = s.mood ? cat.moods.find((m) => m.id === s.mood) : null
  return html`
    <${Card}>
      <div class="vs g10">
        <div class="hs"><${Label}>${cur ? `Feeling ${cur.title.toLowerCase()} today` : 'How are you feeling today?'}<//><div class="sp" />
          ${cur && html`<${Chip} onClick=${() => cari.invoke('open', 'note')}>Today's note 💌<//>`}</div>
        <div class="moods">${cat.moods.map((m) => html`
          <button class="press ${cur?.id === m.id ? 'on' : ''}" title=${m.title} aria-label=${m.title} aria-pressed=${cur?.id === m.id} onClick=${() => call('do', 'setMood', m.id)}>${m.emoji}</button>`)}</div>
      </div>
    <//>`
}

// ---------------------------------------------------------------- what she sees, and how she feels

function Watching({ s, call }) {
  const v = s.activity.verdict
  const icon = v === 'work' ? '💗' : v === 'distraction' ? '😤' : '😐'
  return html`
    <div class="vs g8">
      <div class="hs g8 center soft" style="font-size:12.5px;font-weight:700;justify-content:center">
        <span>${icon}</span><span class="ell">Watching: ${s.activity.label || 'nothing yet'}</span>
        ${s.focus.seconds >= 60 && html`<span>· ${s.focus.inFlow ? '🌊 in flow ' : ''}${Math.floor(s.focus.seconds / 60)} min</span>`}
      </div>
      ${s.activity.note && html`<div class="note center">⏸ ${s.activity.note}. Focus time isn't counting until you're back.</div>`}
      ${!s.prefs.browserAwareness && html`<${Notice} text="Turn on browser awareness so I can catch Reels" action="Turn on" onAction=${() => call('pref', 'browserAwareness', true)} />`}
      ${s.monitor.undoLabel && html`<${Notice} text=${`Closed “${s.monitor.undoLabel.slice(0, 28)}”`} action="Reopen" onAction=${() => call('undoClose')} />`}
    </div>`
}

function Vitals({ s }) {
  const v = s.vitals
  const item = (e, name, value, color) => html`<div class="v" title=${`${name} ${pct(value)}%`}><span class="e">${e}</span><${Bar} value=${value} colors=${[color, color]} height=${6} /><span>${name}</span></div>`
  return html`<${Card}><div class="vitals">${item('🍖', 'Belly', v.hunger, 'var(--peach)')}${item('😊', 'Happy', v.happiness, 'var(--second)')}${item('⚡️', 'Energy', v.energy, 'var(--sage)')}${item('💗', 'Love', v.affection, 'var(--accent)')}</div><//>`
}

export function Home(p) {
  return html`
    <${Today} ...${p} /><${Care} ...${p} /><${Mood} ...${p} /><${Vitals} ...${p} /><${Watching} ...${p} />
    <button class="press linkbtn" onClick=${() => cari.invoke('open', 'stats')}><${Icon} name="chart" size=${15} sw=${2.4} /> Stats, streaks & badges</button>`
}

// The Settings tab, in the order you'd want it: how she looks, how she coaches you, what she guards, her own habits,
// and a "More" fold for everything you set once and forget.
import { html, useState, useEffect, Icon, Label, Card, Chip, Select, rgbCss, clockHour, cari } from '../ui/kit.js'
import { Toggle, Heading, Disclosure } from './parts.js'

const PROVIDERS = [
  { id: 'local', title: 'On this PC only', model: '', needsKey: false, privacy: 'Your messages never leave this PC.' },
  { id: 'ollama', title: 'Ollama (local model)', model: 'llama3.2', needsKey: false, privacy: 'Your messages go to Ollama running on this PC.' },
  { id: 'openai', title: 'ChatGPT / OpenAI', model: 'gpt-4o-mini', needsKey: true, privacy: 'Your chat messages, plus her name, personality and the mood you picked, are sent to OpenAI. Nothing else is. OpenAI sets its own age limit and terms.' },
  { id: 'gemini', title: 'Gemini', model: 'gemini-2.0-flash', needsKey: true, privacy: 'Your chat messages, plus her name, personality and the mood you picked, are sent to Google. Nothing else is. Google sets its own age limit and terms.' },
]

const REPO = 'https://github.com/itz-ranu/Cariberry/blob/main'
const LEGAL = [['Privacy', `${REPO}/PRIVACY.md`], ['Terms', `${REPO}/TERMS.md`], ['Licences', `${REPO}/THIRD_PARTY_NOTICES.md`]]

const short = (t, n) => (t.length > n ? `${t.slice(0, n)}…` : t)

// ---------------------------------------------------------------- look

function Look({ s, cat, call }) {
  const cur = cat.themes.find((t) => t.id === s.prefs.theme) || cat.themes[0]
  return html`
    <div class="section">
      <${Heading} right=${html`<span class="soft" style="font-size:12px;font-weight:800">${cur.title}</span>`}>Look<//>
      <${Card}><div class="themes">${cat.themes.map((t) => html`
        <button class="press themedot ${t.id === cur.id ? 'on' : ''}" title=${t.title} aria-label=${`${t.title} theme`} aria-pressed=${t.id === cur.id} onClick=${() => call('pref', 'theme', t.id)}>
          <i style=${{ background: `linear-gradient(135deg, ${rgbCss(t.hot[0])}, ${rgbCss(t.hot[1])})` }}>${t.emoji}</i></button>`)}</div><//>
    </div>`
}

// ---------------------------------------------------------------- coach

function Coach({ s, cat, call }) {
  const P = s.prefs
  const cur = cat.vibes.find((v) => v.id === s.vibe) || cat.vibes[0]
  return html`
    <div class="section">
      <${Heading}>Coach<//>
      <${Card}>
        <div class="vs g12">
          <div class="vs g8">
            <div class="chips">${cat.vibes.map((v) => html`<button class="chipbtn ${v.id === cur.id ? 'on' : ''}" aria-pressed=${v.id === cur.id} onClick=${() => call('pref', 'vibe', v.id)}>${v.emoji} ${v.title}</button>`)}</div>
            <div class="note">${cur.blurb} <span style="opacity:.85">${cur.example}</span></div>
          </div>
          <div>
            <${Toggle} title="Focus coaching" subtitle="Reacts to what you're doing" on=${!!P.focusCoaching} onChange=${(v) => call('pref', 'focusCoaching', v)} />
            <${Toggle} title="Watch my browser" subtitle="Reads your tab's title and address to spot Reels" on=${!!P.browserAwareness} onChange=${(v) => call('pref', 'browserAwareness', v)} />
            <${Toggle} title="Close Reels tabs for me" subtitle="One warning first" on=${!!P.autoCloseReels} enabled=${!!P.browserAwareness} onChange=${(v) => call('pref', 'autoCloseReels', v)} />
          </div>
        </div>
      <//>
    </div>`
}

// ---------------------------------------------------------------- guard

function Guard({ s, call }) {
  const [draft, setDraft] = useState('')
  const add = () => { if (!draft.trim()) return; call('block', draft); setDraft('') }
  const aware = !!s.prefs.browserAwareness
  const seen = s.monitor.seen
  const fresh = seen && Date.now() - seen.at < 15000
  const what = !fresh ? null : seen.browser ? `${seen.name}: ${seen.url ? short(seen.url.replace(/^https?:\/\//, ''), 34) : short(seen.title || '(no title)', 34)}` : `${seen.name} (an app)`
  return html`
    <div class="section">
      <${Heading} right=${html`<span class="soft" style="font-size:12px;font-weight:800">${s.guards.filter((g) => g.on).length} on</span>`}>Guard these<//>
      <${Card}>
        <div class="vs g12">
          <div class="note">Switch on anything that eats your focus. She'll nudge you the moment she sees it.</div>
          <div class="guards">${s.guards.map((g) => html`
            <button class=${g.on ? 'on' : ''} aria-pressed=${g.on} aria-label=${`Guard ${g.name}`} onClick=${() => call('guard', g.id, !g.on)}><span class="e">${g.emoji}</span><span class="ell">${g.name}</span></button>`)}</div>
          <div class="hs g8">
            <input class="field" placeholder="Add your own, e.g. etsy.com" value=${draft} onInput=${(e) => setDraft(e.target.value)} onKeyDown=${(e) => e.key === 'Enter' && add()} aria-label="Add a site or app to guard" />
            <${Chip} disabled=${!draft.trim()} onClick=${add}>Add<//>
          </div>
          ${s.blocks.length > 0 && html`<div class="chips">${s.blocks.map((term) => html`
            <button class="chipbtn on" title="Stop guarding" aria-label=${`Stop guarding ${term}`} onClick=${() => call('unblock', term)}>🚫 ${term} ✕</button>`)}</div>`}
          ${aware && html`<div class="note" style="background:var(--track);border-radius:10px;padding:7px 9px;font-weight:700">👀 Right now she sees: <span style="font-weight:600">${what || 'nothing yet. Click another window and look back here'}</span></div>`}
        </div>
      <//>
    </div>`
}

// ---------------------------------------------------------------- her

function Her({ s, call }) {
  const P = s.prefs
  return html`
    <div class="section">
      <${Heading}>Her<//>
      <${Card}>
        <${Toggle} title="Her voice" subtitle="Barks, purrs and clicks. The music has its own play button" on=${!!P.sounds} onChange=${(v) => call('pref', 'sounds', v)} />
        <${Toggle} title="Roam around" subtitle="Wander near where she sits" on=${!!P.roams} onChange=${(v) => call('pref', 'roams', v)} />
        <${Toggle} title="Start with Windows" on=${!!P.launchAtLogin} onChange=${(v) => call('pref', 'launchAtLogin', v)} />
      <//>
    </div>`
}

// ---------------------------------------------------------------- more

function HourSelect({ value, onChange, label }) {
  return html`<${Select} width=${78} value=${value} label=${label} options=${Array.from({ length: 24 }, (_, h) => [h, clockHour(h)])} onChange=${onChange} />`
}

function Brain({ s, call }) {
  const prov = PROVIDERS.find((p) => p.id === s.prefs.chatProvider) || PROVIDERS[0]
  const [key, setKey] = useState('')
  const [model, setModel] = useState(s.prefs.chatModel || '')
  const [hasKey, setHasKey] = useState(false)
  useEffect(() => { if (prov.needsKey) cari.invoke('secret:has', prov.id).then(setHasKey); else setHasKey(false) }, [prov.id])
  const save = async () => {
    const k = key.trim()
    if (!k) return
    await cari.invoke('secret:set', prov.id, k)
    setKey(''); setHasKey(true)
  }
  return html`
    <${Card}>
      <div class="vs g10">
        <${Label}>Chat brain<//>
        <${Select} value=${prov.id} label="Provider" options=${PROVIDERS.map((p) => [p.id, p.title])} onChange=${(v) => call('pref', 'chatProvider', v)} width=${316} />
        ${prov.id !== 'local' && html`
          <input class="field s" placeholder=${`Model (default ${prov.model})`} value=${model} onInput=${(e) => setModel(e.target.value)}
            onBlur=${() => call('pref', 'chatModel', model.trim())} onKeyDown=${(e) => e.key === 'Enter' && call('pref', 'chatModel', model.trim())} aria-label="Model" />`}
        ${prov.needsKey && html`
          <div class="hs g8">
            <input class="field s" type="password" autocomplete="off" placeholder=${`Paste your ${prov.title} API key`} value=${key} onInput=${(e) => setKey(e.target.value)}
              onKeyDown=${(e) => e.key === 'Enter' && save()} aria-label="API key" />
            <${Chip} disabled=${!key.trim()} onClick=${save}>Save<//>
          </div>
          ${hasKey && html`<div class="note" style="font-weight:700">✅ a key is saved, encrypted by Windows for your account only</div>`}`}
        <div class="note" style="font-weight:700">${prov.privacy}</div>
        <div class="note">She answers in her own voice with no setup. Connect a brain and she can help with homework and rewrite your emails too.</div>
      </div>
    <//>`
}

function More({ s, call }) {
  const [open, setOpen] = useState(false)
  const P = s.prefs
  return html`
    <div class="section">
      <${Heading} right=${html`<${Disclosure} label=${open ? 'Hide' : 'Show'} open=${open} onToggle=${() => setOpen(!open)} />`}>More options<//>
      ${open && html`
        <${Card}>
          <div>
            <${Toggle} title="Gentle reminders" subtitle="Water, a stretch, and an eye rest" on=${!!P.reminders} onChange=${(v) => call('pref', 'reminders', v)} />
            <${Toggle} title="Daily mood check-in" subtitle="A soft “how are we feeling?” each morning" on=${!!P.dailyCheckIn} onChange=${(v) => call('pref', 'dailyCheckIn', v)} />
            <${Toggle} title="Quiet hours" subtitle="No barking while you're winding down" on=${!!P.quietHoursEnabled} onChange=${(v) => call('pref', 'quietHoursEnabled', v)} />
            ${P.quietHoursEnabled && html`
              <div class="hs g8" style="margin-top:10px">
                <span class="soft" style="font-size:12px;font-weight:700">From</span><${HourSelect} value=${P.quietHoursStart} label="Quiet hours start" onChange=${(h) => call('pref', 'quietHoursStart', h)} />
                <span class="soft" style="font-size:12px;font-weight:700">to</span><${HourSelect} value=${P.quietHoursEnd} label="Quiet hours end" onChange=${(h) => call('pref', 'quietHoursEnd', h)} />
              </div>`}
            <${Toggle} title="Bop to my music" subtitle="Listens to what your PC is playing. She nods along" on=${!!P.musicBop} onChange=${(v) => call('pref', 'musicBop', v)} />
            <${Toggle} title="Above fullscreen apps" subtitle="Stay visible over a fullscreen video or game" on=${!!P.aboveFullscreen} onChange=${(v) => call('pref', 'aboveFullscreen', v)} />
            <${Toggle} title="Let me drop her anywhere" subtitle="Drag her onto any spot on your screen" on=${!!P.placeAnywhere} onChange=${(v) => call('pref', 'placeAnywhere', v)} />
            ${s.perched && html`<div style="margin-top:10px"><${Chip} tint="var(--second)" onClick=${() => call('do', 'goHome')}>Send her home 🏠<//></div>`}
          </div>
        <//>
        <${Brain} s=${s} call=${call} />
        <${Card}>
          <div class="vs g10">
            <${Label}>Rules<//>
            <div class="note">What counts as work or a distraction lives in a small file you can edit.</div>
            <div class="chips">
              <${Chip} tint="var(--second)" onClick=${async () => { await call('flush'); cari.invoke('open', 'rules') }}>Edit rules file<//>
              <${Chip} tint="var(--second)" onClick=${() => call('reloadRules')}>Reload<//>
              <${Chip} tint="var(--second)" onClick=${() => call('resetRules')}>Reset<//>
            </div>
          </div>
        <//>`}
    </div>`
}

export function Settings(p) {
  return html`
    <${Look} ...${p} /><${Coach} ...${p} /><${Guard} ...${p} /><${Her} ...${p} /><${More} ...${p} />
    <button class="press linkbtn quit" onClick=${() => cari.invoke('quit')}><${Icon} name="power" size=${15} sw=${2.4} /> Quit ${p.s.name}</button>
    <div class="note center" style="padding-bottom:2px">made with 💗 by Ranu</div>
    <div class="chips" style="justify-content:center">
      ${LEGAL.map(([title, url]) => html`<${Chip} tint="var(--second)" onClick=${() => cari.invoke('open', 'external', url)}>${title}<//>`)}
    </div>
    <div class="note center" style="padding-bottom:6px;font-size:11px">For ages 13+. Independent: not affiliated with or endorsed by Apple, Microsoft, Google, OpenAI or any other company named here.</div>`
}

// Her scrapbook. Pick any day (the calendar, or the arrows) to see how it went: focus against your goal, time lost
// to distractions, sessions, finished to-dos, where the time went app by app. Below: records, badges and a card to share.
// Ported from StatsView.swift.
import { html, render, useState, useEffect, useCallback, Icon, Label, Card, Pill, Chip, Bar, Ring, CritterCanvas, centered, pct, timeText, cari, rpc } from '../ui/kit.js'
import { applyTheme } from '../theme.js'
import { dayKey, addDays, parseDay } from '../../engine/util.js'

const locale = navigator.language || 'en'
const firstWeekday = () => { try { return new Intl.Locale(locale).getWeekInfo?.().firstDay ?? new Intl.Locale(locale).weekInfo?.firstDay ?? 7 } catch { return 7 } }
const dur = (seconds) => {
  const total = Math.floor(seconds), h = Math.floor(total / 3600), m = Math.floor((total % 3600) / 60)
  if (h > 0) return `${h}h ${m}m`
  if (m > 0) return `${m}m`
  return total > 0 ? '<1m' : '0m'
}
const moodWord = (r) => (r >= 0.8 ? 'excellent' : r >= 0.6 ? 'good' : r >= 0.4 ? 'mixed' : 'rough day')

function Tile({ emoji, label, value, tint }) {
  return html`<div class="tile2"><div class="ic" style=${{ background: `color-mix(in srgb, ${tint} 40%, transparent)` }}>${emoji}</div>
    <div class="vs g2" style="min-width:0"><div class="v ell">${value}</div><div class="l ell">${label}</div></div></div>`
}

function Header({ d }) {
  const since = new Date(d.born).toLocaleDateString(locale, { day: 'numeric', month: 'short', year: 'numeric' })
  return html`
    <div class="hs g14">
      <div class="avatar84">
        <${CritterCanvas} species=${d.species} coat=${d.coatIndex} pose=${{ emotion: 'proud', phase: 0.42, outfit: d.outfit, collarTier: d.collarTier }} scale=${0.46} w=${84} h=${84} circle=${true} ...${centered(84, 84, 0.46, -3, -8)} />
      </div>
      <div class="vs g3 grow">
        <div style="font-size:24px;font-weight:900" class="ell">${d.name}</div>
        <div class="note s" style="font-weight:600">together ${d.ageDays} day${d.ageDays === 1 ? '' : 's'} · since ${since}</div>
      </div>
    </div>`
}

function LevelCard({ d }) {
  const c = d.collarColor
  return html`
    <div class="levelcard vs g9">
      <div class="hs g8" style="align-items:baseline">
        <span style="font-size:21px;font-weight:900">Level ${d.level}</span>
        <span style="font-size:12px;font-weight:800;color:var(--accent)">${d.levelTitle}</span><div class="sp" />
        ${d.collarTier > 0 && html`<div class="hs g4"><i style=${{ width: '9px', height: '9px', borderRadius: '50%', background: `rgb(${c.map((x) => Math.round(x * 255)).join(',')})` }} /><span class="soft" style="font-size:10px;font-weight:600">${d.collarName}</span></div>`}
      </div>
      <${Bar} value=${d.levelProgress} colors=${['var(--accent)', 'var(--second)']} height=${10} />
      <div class="hs"><span class="soft" style="font-size:10px;font-weight:800">${Math.floor(d.xpInto)} / ${Math.floor(d.xpNeeded)} XP</span><div class="sp" />
        ${d.nextUnlock && html`<span class="soft" style="font-size:10px;font-weight:600">next: ${d.nextUnlock}</span>`}</div>
    </div>`
}

function Calendar({ d, selected, setSelected, today }) {
  const first = firstWeekday()
  const dow = ((parseDay(today).getDay() + 6) % 7) + 1             // 1 = Monday ... 7 = Sunday
  const weekStart = addDays(today, -((dow - first + 7) % 7))
  const start = addDays(weekStart, -28)
  const days = Array.from({ length: 35 }, (_, i) => addDays(start, i))
  const letters = days.slice(0, 7).map((k) => new Intl.DateTimeFormat(locale, { weekday: 'narrow' }).format(parseDay(k)))
  const goal = Math.max(1, d.dailyGoal)
  return html`
    <div class="vs g6">
      <div class="cal">${letters.map((l) => html`<div class="dow">${l}</div>`)}</div>
      <div class="cal">${days.map((k) => {
        const future = k > today, m = d.dailyFocus[k] || 0, frac = Math.min(1, m / goal), hit = m >= goal
        const mood = d.moods[k] ? d.moodTable[d.moods[k]] : null
        return html`
          <button class="day ${m > 0 ? 'has' : ''} ${hit ? 'hit' : ''} ${k === selected ? 'sel' : ''} ${k === today ? 'today' : ''} ${future ? 'future' : ''}"
            style=${!hit && m > 0 ? { background: `color-mix(in srgb, var(--accent) ${Math.round((0.22 + 0.5 * frac) * 100)}%, transparent)` } : null}
            disabled=${future} onClick=${() => setSelected(k)} aria-label=${`${k}: ${timeText(m)} focus`}>
            ${Number(k.slice(8))}${k === today && html`<i class="dot" />`}${mood && html`<span class="m">${mood.emoji}</span>`}
          </button>`
      })}</div>
    </div>`
}

const trackedSeconds = (d, day) => Object.values(d.dailyAppTime[day] || {}).reduce((a, b) => a + b, 0)
const kindTint = (d, app) => (d.siteKinds?.[app] === 'work' ? 'var(--sage)' : d.siteKinds?.[app] === 'distraction' ? 'var(--second)' : 'var(--accent)')
const Legend = ({ c, t }) => html`<span class="hs g4"><i class="kdot" style=${{ background: c }} /><span class="soft" style="font-size:10px;font-weight:600">${t}</span></span>`

/** Where the whole day went: focus, distraction, everything else and time away from the keys. The four add up
 *  to the time she watched, so the bar never claims more than she saw. */
function Composition({ d, selected, ratio }) {
  const focusS = (d.dailyFocus[selected] || 0) * 60
  const tracked = trackedSeconds(d, selected)
  const distS = Math.min((d.dailyDistraction[selected] || 0), Math.max(0, tracked - focusS))
  const away = d.dailyAway?.[selected] || 0
  const other = Math.max(0, tracked - focusS - distS)
  const total = focusS + distS + other + away
  if (total <= 0) return null
  const segs = [[focusS, 'var(--sage)'], [distS, 'var(--second)'], [other, 'color-mix(in srgb, var(--accent) 55%, transparent)'], [away, 'var(--track)']].filter((x) => x[0] > 0)
  const stat = (c, t, sec) => html`<div class="vs g1 grow"><span class="hs g4"><i class="kdot" style=${{ background: c }} /><span class="soft" style="font-size:10px;font-weight:600">${t}</span></span><span style="font-size:13px;font-weight:900">${dur(sec)}</span></div>`
  return html`
    <div class="vs g8">
      <div class="hs"><${Label}>How the day split<//><div class="sp" />
        ${ratio >= 0 && html`<span style="font-size:11px;font-weight:700">${Math.floor(ratio * 100)}% focused · ${moodWord(ratio)}</span>`}</div>
      <div class="splitbar" style="height:12px">${segs.map(([v, c]) => html`<i style=${{ width: `${Math.max(1, v / total * 100)}%`, background: c, minWidth: '5px' }} />`)}</div>
      <div class="hs">${stat('var(--sage)', 'Focused', focusS)}${stat('var(--second)', 'Distracted', distS)}${stat('color-mix(in srgb, var(--accent) 70%, transparent)', 'Other', other)}${away > 60 && stat('var(--ink-soft)', 'Away', away)}</div>
    </div>`
}

function DayDetails({ d, selected }) {
  const f = d.dailyFocus[selected] || 0, dMin = (d.dailyDistraction[selected] || 0) / 60
  const goal = d.dailyGoal
  const delta = f - (d.dailyFocus[addDays(selected, -1)] || 0)
  const ratio = f + dMin > 0 ? f / (f + dMin) : -1
  const mood = d.moods[selected] ? d.moodTable[d.moods[selected]] : null
  const apps = Object.entries(d.dailyAppTime[selected] || {}).sort((a, b) => b[1] - a[1]).slice(0, 7)
  const top = apps[0]?.[1] || 1
  const tracked = Math.max(1, trackedSeconds(d, selected))
  return html`
    <div class="vs g14">
      <div class="hs g16">
        <${Ring} progress=${Math.min(1, f / Math.max(1, goal))} size=${92} line=${11}>
          <div class="vs center"><div style="font-size:20px;font-weight:900">${Math.floor(Math.min(f / Math.max(1, goal), 9.99) * 100)}%</div><div class="soft" style="font-size:10px;font-weight:700">of goal</div></div>
        <//>
        <div class="vs g5 grow">
          <div style="font-size:30px;font-weight:900;line-height:1.1">${timeText(f)}</div>
          <div class="note" style="font-weight:600">focused · goal ${timeText(goal)} · vs day before</div>
          <div class="hs g6">
            ${f >= goal && html`<${Pill} tint="var(--butter)" small=${true}>🏆 goal hit<//>`}
            ${Math.abs(delta) >= 1 && html`<${Pill} tint=${delta > 0 ? 'var(--sage)' : 'var(--peach)'} small=${true}>${delta > 0 ? '▲' : '▼'} ${timeText(Math.abs(delta))}<//>`}
          </div>
        </div>
      </div>
      ${mood && html`<div class="hs g8" style="padding:8px 12px;border-radius:14px;background:color-mix(in srgb, var(--accent) 18%, transparent)">
        <span style="font-size:20px">${mood.emoji}</span><span style="font-size:12.5px;font-weight:700">You felt ${mood.title.toLowerCase()} this day</span></div>`}
      <div class="grid cols2 gap8">
        <${Tile} emoji="✅" label="To-dos done" value=${d.dailyTasks[selected] || 0} tint="var(--sage)" />
        <${Tile} emoji="🍅" label="Sessions" value=${d.dailySessions[selected] || 0} tint="var(--peach)" />
        <${Tile} emoji="📵" label="Distracted" value=${timeText(dMin)} tint="var(--second)" />
        <${Tile} emoji="🐾" label="Told off" value=${`${d.dailyBarks[selected] || 0}×`} tint="var(--butter)" />
      </div>
      <${Composition} d=${d} selected=${selected} ratio=${ratio} />
      <div class="vs g9">
        <${Label}>Where the day went<//>
        ${apps.length === 0 ? html`<div class="note">No app time was tracked for this day.</div>` : apps.map(([name, sec]) => html`
          <div class="vs g4"><div class="hs g7"><i class="kdot" style=${{ background: kindTint(d, name) }} /><span class="ell" style="font-size:12.5px;font-weight:700">${name}</span><div class="sp" />
            <span class="soft" style="font-size:10.5px;font-weight:600;opacity:.8">${Math.round(sec / tracked * 100)}%</span><span class="soft dur" style="font-size:11.5px;font-weight:700">${dur(sec)}</span></div>
            <${Bar} value=${sec / top} height=${6} colors=${[kindTint(d, name), kindTint(d, name)]} /></div>`)}
        ${apps.length > 0 && html`<div class="hs g12" style="margin-top:2px"><${Legend} c="var(--sage)" t="work" /><${Legend} c="var(--second)" t="distraction" /><${Legend} c="var(--accent)" t="everything else" /></div>`}
      </div>
    </div>`
}

function DayCard({ d, today, selected, setSelected }) {
  const [note, setNote] = useState('')
  const isToday = selected === today
  const hasData = (d.dailyFocus[selected] || 0) > 0 || (d.dailyDistraction[selected] || 0) > 0 || Object.keys(d.dailyAppTime[selected] || {}).length > 0 || (d.dailySessions[selected] || 0) > 0
  const title = isToday ? 'Today' : selected === addDays(today, -1) ? 'Yesterday' : new Date(parseDay(selected)).toLocaleDateString(locale, { weekday: 'long' })
  const date = parseDay(selected).toLocaleDateString(locale, { day: 'numeric', month: 'long', year: 'numeric' })
  const flash = (t) => { setNote(t); setTimeout(() => setNote(''), 3000) }
  const share = async (save) => {
    const out = await cari.invoke('share:day', { save, selected, title, date })
    flash(out?.ok ? (save ? 'saved to your Desktop 💌' : 'copied! paste it anywhere 💌') : 'couldn\'t make the card 😟')
  }
  return html`
    <${Card} big=${true}>
      <div class="vs g14">
        <div class="hs g10">
          <button class="stepbtn" onClick=${() => setSelected(addDays(selected, -1))} aria-label="Previous day"><${Icon} name="chevronLeft" size=${13} sw=${3} /></button>
          <div class="vs g2"><div style="font-size:19px;font-weight:900">${title}</div><div class="note s" style="font-weight:600">${date}</div></div>
          <button class="stepbtn" disabled=${isToday} onClick=${() => !isToday && setSelected(addDays(selected, 1))} aria-label="Next day"><${Icon} name="chevronRight" size=${13} sw=${3} /></button>
          <div class="sp" />
          ${!isToday && html`<${Chip} onClick=${() => setSelected(today)}>Today<//>`}
        </div>
        <${Calendar} d=${d} selected=${selected} setSelected=${setSelected} today=${today} />
        <div class="divider" />
        ${hasData ? html`<${DayDetails} d=${d} selected=${selected} />` : html`
          <div class="vs center" style="padding:16px 0;gap:8px;align-items:center"><div style="font-size:34px">${isToday ? '🌱' : '🌙'}</div>
            <div style="font-size:13px;font-weight:800">${isToday ? 'A fresh day. Nothing logged yet.' : 'Nothing was logged on this day.'}</div>
            <div class="note center">${isToday ? 'Start a focus session and watch this fill up.' : 'She wasn\'t watching, or you had a day off. That\'s okay 💗'}</div></div>`}
        <div class="hs g8">
          <${Chip} onClick=${() => share(false)}><${Icon} name="copy" size=${14} /> Copy card<//>
          <${Chip} tint="var(--second)" onClick=${() => share(true)}><${Icon} name="download" size=${14} /> Save to Desktop<//>
          ${note && html`<span class="soft" style="font-size:11px;font-weight:700">${note}</span>`}
        </div>
      </div>
    <//>`
}

function WeekCard({ d, today, selected, setSelected }) {
  const days = Array.from({ length: 7 }, (_, i) => addDays(today, i - 6))
  const vals = days.map((k) => d.dailyFocus[k] || 0)
  const goal = Math.max(1, d.dailyGoal)
  const top = Math.max(goal, ...vals) * 1.12
  const total = vals.reduce((a, b) => a + b, 0)
  const last = Array.from({ length: 7 }, (_, i) => d.dailyFocus[addDays(today, -(7 + i))] || 0).reduce((a, b) => a + b, 0)
  const delta = total - last
  const active = vals.filter((v) => v > 0).length
  const chartH = 96
  return html`
    <${Card} big=${true}>
      <div class="vs g12">
        <div class="hs"><${Label}>📈 This week<//><div class="sp" />
          ${Math.abs(delta) >= 1 && (total > 0 || last > 0) && html`<${Pill} tint=${delta > 0 ? 'var(--sage)' : 'var(--peach)'} small=${true}>${delta > 0 ? '▲' : '▼'} ${timeText(Math.abs(delta))} vs last week<//>`}</div>
        <div class="weekchart" style=${{ height: `${chartH}px` }}>
          <i class="goalline" style=${{ bottom: `${(goal / top) * (chartH - 14) + 14}px` }}><b>goal</b></i>
          ${days.map((k, i) => {
            const v = vals[i], hit = v >= goal, sel = k === selected
            return html`<button class="wbar ${sel ? 'sel' : ''}" onClick=${() => setSelected(k)} aria-label=${`${new Date(parseDay(k)).toLocaleDateString(locale, { weekday: 'long' })}: ${timeText(v)} focus`}>
              ${v > 0 && html`<span class="wv">${timeText(v)}</span>`}
              <i class="${v > 0 ? (hit ? 'hit' : 'has') : ''}" style=${{ height: `${Math.max(5, (chartH - 14) * (v / top))}px` }} /></button>`
          })}
        </div>
        <div class="weekdays">${days.map((k) => html`<span class=${k === today ? 'now' : ''}>${new Date(parseDay(k)).toLocaleDateString(locale, { weekday: 'short' })}</span>`)}</div>
        <div class="hs g8">
          ${[['Total', timeText(total)], ['Daily avg', timeText(active > 0 ? total / active : 0)], ['Days at goal', `${vals.filter((v) => v >= goal).length} / 7`]].map(([t, v]) =>
            html`<div class="mini grow"><b>${v}</b><span>${t}</span></div>`)}
        </div>
      </div>
    <//>`
}

const hourLabel = (h) => `${h % 12 === 0 ? 12 : h % 12} ${h < 12 ? 'AM' : 'PM'}`

function InsightsCard({ d, today }) {
  const hours = Array.from({ length: 24 }, (_, h) => d.focusByHour?.[h] || 0)
  const hoursTotal = hours.reduce((a, b) => a + b, 0)
  const topH = Math.max(1, ...hours), peak = hours.indexOf(topH)
  const rows = []
  if (hoursTotal >= 20) rows.push(['⏰', 'Your focus hour', `You focus best around ${hourLabel(peak)}`])
  // strongest weekday, once there are enough days for it to mean something
  const sums = {}
  for (const [k, m] of Object.entries(d.dailyFocus)) if (m >= 5) { const w = parseDay(k).getDay(); (sums[w] ||= [0, 0]); sums[w][0] += m; sums[w][1] += 1 }
  const counted = Object.values(sums).reduce((a, v) => a + v[1], 0)
  const best = Object.entries(sums).filter(([, v]) => v[1] >= 2).sort((a, b) => b[1][0] / b[1][1] - a[1][0] / a[1][1])[0]
  if (counted >= 5 && best) rows.push(['📅', 'Strongest day', `${new Date(2024, 0, 7 + Number(best[0])).toLocaleDateString(locale, { weekday: 'long' })}s: about ${timeText(best[1][0] / best[1][1])} on average`])
  // the biggest thing she barked about this week
  const sink = {}
  for (let i = 0; i < 7; i++) for (const [app, sec] of Object.entries(d.dailyAppTime[addDays(today, -i)] || {})) if (d.siteKinds?.[app] === 'distraction') sink[app] = (sink[app] || 0) + sec
  const topSink = Object.entries(sink).sort((a, b) => b[1] - a[1])[0]
  if (topSink && topSink[1] >= 300) rows.push(['📵', 'Biggest time sink this week', `${topSink[0]}, ${dur(topSink[1])}`])
  if (d.streakDays >= 2) rows.push(['🔥', 'On a roll', `${d.streakDays} days in a row. Don't break it!`])
  return html`
    <${Card} big=${true}>
      <div class="vs g12"><${Label}>✨ Little discoveries<//>
        ${rows.length === 0 ? html`<div class="note">Focus for a few days and she'll start spotting your patterns: your best hour, your strongest day, what keeps pulling you away. 🌱</div>`
          : rows.map(([e, t, v]) => html`<div class="hs g10"><div class="insic">${e}</div><div class="vs g1"><span class="insl">${t}</span><span style="font-size:12.5px;font-weight:700">${v}</span></div></div>`)}
        ${hoursTotal >= 20 && html`<div class="vs g4"><div class="hourchart">${hours.map((v, h) => html`<i class=${h === peak ? 'peak' : v > 0 ? 'has' : ''} style=${{ height: `${Math.max(3, 38 * (v / topH))}px` }} />`)}</div>
          <div class="hs"><span class="hl">12a</span><div class="sp" /><span class="hl">6a</span><div class="sp" /><span class="hl">12p</span><div class="sp" /><span class="hl">6p</span><div class="sp" /><span class="hl">11p</span></div></div>`}
      </div>
    <//>`
}

function RecordsCard({ d }) {
  const t = d.totals
  const days = (n) => `${n} day${n === 1 ? '' : 's'}`
  return html`
    <${Card} big=${true}>
      <div class="vs g12"><${Label}>🏅 Records<//>
        <div class="grid cols2 gap8">
          <${Tile} emoji="🔥" label="Current streak" value=${days(d.streakDays)} tint="var(--peach)" />
          <${Tile} emoji="👑" label="Best streak" value=${days(d.bestStreak)} tint="var(--butter)" />
          <${Tile} emoji="⏱" label="Lifetime focus" value=${dur(t.focusMinutes * 60)} tint="var(--accent)" />
          <${Tile} emoji="🌟" label="Best day" value=${timeText(t.mostFocusInADay)} tint="var(--sage)" />
          <${Tile} emoji="🍅" label="Sessions" value=${t.sessions} tint="var(--peach)" />
          <${Tile} emoji="✅" label="To-dos done" value=${t.tasks} tint="var(--sage)" />
          <${Tile} emoji="🍖" label="Treats eaten" value=${t.treats} tint="var(--butter)" />
          <${Tile} emoji="🐾" label="Times told off" value=${t.barks} tint="var(--second)" />
        </div>
      </div>
    <//>`
}

function BadgesCard({ d }) {
  const got = d.badges.filter((b) => b.earned).length
  return html`
    <${Card} big=${true}>
      <div class="vs g12"><div class="hs"><${Label}>🎖 Badges<//><div class="sp" /><span class="soft" style="font-size:11px;font-weight:800">${got} of ${d.badges.length}</span></div>
        <div class="grid cols4 gap8">${d.badges.map((b) => html`
          <div class="badge ${b.earned ? 'got' : ''}" title=${b.earned ? b.detail : `Locked: ${b.detail}`} aria-label=${b.earned ? `${b.title}, earned` : `${b.title}, locked. ${b.detail}`}>
            <div class="e">${b.earned ? b.emoji : '🔒'}</div><div class="t">${b.title}</div></div>`)}</div>
      </div>
    <//>`
}

function AllTimeCard({ d }) {
  const totals = {}
  for (const [name, sec] of Object.entries(d.categoryTime)) { const key = d.ruleKinds[name] ? name : 'Other'; totals[key] = (totals[key] || 0) + sec }
  const rows = Object.entries(totals).map(([name, seconds]) => ({ name, seconds, kind: d.ruleKinds[name] || 'neutral' }))
  const sum = (k) => rows.filter((r) => r.kind === k).reduce((a, r) => a + r.seconds, 0)
  const work = sum('work'), dis = sum('distraction')
  const ratio = work + dis > 0 ? work / (work + dis) : -1
  const best = (k) => rows.filter((r) => r.kind === k).sort((a, b) => b.seconds - a.seconds)[0]
  const w = best('work'), x = best('distraction')
  const pill = (r, tint) => html`<span class="catpill"><i style=${{ width: '6px', height: '6px', borderRadius: '50%', background: tint }} />${r.name === 'YouTube (might be learning, might not)' ? 'YouTube' : r.name}<span class="soft" style="font-size:10px;font-weight:600">${dur(r.seconds)}</span></span>`
  return html`
    <${Card} big=${true}>
      <div class="vs g12" style="align-items:center">
        <div class="hs fill"><${Label}>Work vs distraction<//><div class="sp" /><span class="soft" style="font-size:10px;font-weight:600">all time</span></div>
        <${Ring} progress=${ratio >= 0 ? Math.max(0.03, ratio) : 0} size=${100} line=${12}>
          ${ratio >= 0 ? html`<div class="vs center"><div style="font-size:24px;font-weight:900">${Math.floor(ratio * 100)}%</div><div class="soft" style="font-size:10px;font-weight:600">${moodWord(ratio)}</div></div>` : html`<div style="font-size:26px">🐾</div>`}
        <//>
        ${ratio >= 0 ? html`<div class="hs g8">${w && pill(w, 'var(--sage)')}${x && pill(x, 'var(--second)')}</div>` : html`<div class="note">not enough data yet, get to work 💪</div>`}
      </div>
    <//>`
}

function App() {
  const [d, setD] = useState(null)
  const [selected, setSelected] = useState(dayKey())
  const pull = useCallback(async () => { const s = await rpc('stats'); if (s) setD(s) }, [])
  useEffect(() => { pull(); const id = setInterval(() => document.visibilityState === 'visible' && pull(), 3000); return () => clearInterval(id) }, [])
  useEffect(() => { if (d) { applyTheme(d.theme); document.title = `${d.name}'s Stats` } }, [d?.theme, d?.name])
  const today = dayKey()
  return html`
    <div class="stats-page page"><div class="blob a" /><div class="blob b" /></div>
    <div class="dragbar" />
    <div class="stats">${d && html`
      <div class="stack">
        <${Header} d=${d} /><${LevelCard} d=${d} /><${WeekCard} d=${d} today=${today} selected=${selected} setSelected=${setSelected} /><${DayCard} d=${d} today=${today} selected=${selected} setSelected=${setSelected} /><${InsightsCard} d=${d} today=${today} /><${RecordsCard} d=${d} /><${BadgesCard} d=${d} /><${AllTimeCard} d=${d} />
      </div>`}</div>`
}
render(html`<${App} />`, document.getElementById('app'))

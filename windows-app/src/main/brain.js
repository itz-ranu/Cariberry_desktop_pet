// Cranberry's brain, in JavaScript: what the Mac app gets from its separate Python service. Two jobs:
//   * talk: Ollama, OpenAI or Gemini if you've connected one (streamed word by word), otherwise she
//     answers in her own voice, so the chat always answers;
//   * do: "open Spotify", "close Chrome", "open Notion and start my study playlist".
// What a provider gets is the conversation you type, plus a short line saying who she is (her name, species, personality,
// the coaching style you chose and the mood you picked at check-in). Nothing else is ever sent.
// Ported from cranberry/brain/llm.py, slots.py, infer.py and rpa/chain.py.
import fs from 'node:fs'
import path from 'node:path'
import os from 'node:os'
import { execFile, spawn } from 'node:child_process'

// ------------------------------------------------------------------ talking: the LLM brains

export const PROVIDERS = {
  ollama: { model: 'llama3.2' },
  openai: { model: 'gpt-4o-mini' },
  gemini: { model: 'gemini-2.0-flash' },
}
const OLLAMA_URL = 'http://127.0.0.1:11434'
const HISTORY_TURNS = 12
const TIMEOUT_MS = 40000

export class LLMError extends Error {}

export function systemPrompt(p = {}) {
  const name = p.name || 'Cranberry', species = p.species || 'pet'
  const lines = [
    `You are ${name}, a ${species} who lives on the user's PC as a desktop pet and study bestie.`,
    `Your personality: ${p.voice || 'a sweet, encouraging desktop pet'}.`,
    'Talk like a warm, witty friend: short messages (1 to 4 sentences), a few emoji, never preachy.',
    'You can help with homework (explain simply, step by step), rewrite emails or messages (reply with just the rewrite unless asked otherwise), and have cozy chit-chat.',
    'Stay in character. Don\'t claim to have done things on the computer yourself; you only chat here.',
    'If a request is unsafe or harmful, decline gently and suggest something kinder.',
  ]
  if (p.vibe && p.vibe !== 'Her own voice') lines.push(`Coaching style the user chose: ${p.vibe}.`)
  if (p.mood) lines.push(`The user said they feel ${String(p.mood).toLowerCase()} today. Be gentle if that's stressed or tired.`)
  return lines.join('\n')
}

/** Server-sent events: yields the JSON of every `data:` line. */
export async function* sseJson(body) {
  const reader = body.getReader(), dec = new TextDecoder()
  let buf = ''
  for (;;) {
    const { value, done } = await reader.read()
    if (done) break
    buf += dec.decode(value, { stream: true })
    let i
    while ((i = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, i).trim(); buf = buf.slice(i + 1)
      if (!line.startsWith('data:')) continue
      const payload = line.slice(5).trim()
      if (!payload || payload === '[DONE]') continue
      try { yield JSON.parse(payload) } catch { /* a partial line: ignore */ }
    }
  }
}

/** Newline-delimited JSON (Ollama). */
async function* ndjson(body) {
  const reader = body.getReader(), dec = new TextDecoder()
  let buf = ''
  for (;;) {
    const { value, done } = await reader.read()
    if (done) break
    buf += dec.decode(value, { stream: true })
    let i
    while ((i = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, i).trim(); buf = buf.slice(i + 1)
      if (line) { try { yield JSON.parse(line) } catch { /* ignore */ } }
    }
  }
}

async function post(fetchFn, url, body, headers) {
  let res
  try {
    res = await fetchFn(url, { method: 'POST', headers: { 'content-type': 'application/json', ...headers }, body: JSON.stringify(body), signal: AbortSignal.timeout(TIMEOUT_MS) })
  } catch (e) {
    throw new LLMError(e.name === 'TimeoutError' ? 'timed out' : (e.cause?.code === 'ECONNREFUSED' ? 'nothing is listening there' : e.message))
  }
  if (!res.ok) {
    let detail = ''
    try { detail = (await res.text()).slice(0, 200) } catch { /* ignore */ }
    throw new LLMError(`HTTP ${res.status} ${detail}`.trim())
  }
  return res
}

const providers = {
  async *ollama({ fetchFn, model, system, messages }) {
    const res = await post(fetchFn, `${OLLAMA_URL}/api/chat`, { model, stream: true, messages: [{ role: 'system', content: system }, ...messages] }, {})
    for await (const ev of ndjson(res.body)) {
      if (ev.error) throw new LLMError(String(ev.error))
      yield ev.message?.content || ''
      if (ev.done) break
    }
  },
  async *openai({ fetchFn, model, system, messages, key }) {
    const res = await post(fetchFn, 'https://api.openai.com/v1/chat/completions', { model, stream: true, messages: [{ role: 'system', content: system }, ...messages] },
      { authorization: `Bearer ${key}`, accept: 'text/event-stream' })
    for await (const ev of sseJson(res.body)) for (const c of ev.choices || []) yield c.delta?.content || ''
  },
  async *gemini({ fetchFn, model, system, messages, key }) {
    const contents = messages.map((m) => ({ role: m.role === 'assistant' ? 'model' : 'user', parts: [{ text: m.content }] }))
    const res = await post(fetchFn, `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:streamGenerateContent?alt=sse`,
      { systemInstruction: { parts: [{ text: system }] }, contents }, { 'x-goog-api-key': key, accept: 'text/event-stream' })
    for await (const ev of sseJson(res.body)) for (const c of ev.candidates || []) for (const p of c.content?.parts || []) yield p.text || ''
  },
}

export class LLM {
  constructor(fetchFn = globalThis.fetch) { this.fetch = fetchFn; this.history = [] }
  reset() { this.history = [] }

  /** Yields the reply in chunks. Throws LLMError if the brain can't answer. */
  async *stream({ provider, model, key, text, persona }) {
    const impl = providers[provider]
    if (!impl) throw new LLMError(`unknown provider ${provider}`)
    if (provider !== 'ollama' && !key) throw new LLMError('no API key saved')
    const messages = [...this.history.slice(-HISTORY_TURNS * 2), { role: 'user', content: text }]
    const reply = []
    try {
      for await (const chunk of impl({ fetchFn: this.fetch, model: model || PROVIDERS[provider].model, system: systemPrompt(persona), messages, key })) {
        if (chunk) { reply.push(chunk); yield chunk }
      }
    } catch (e) {
      if (e instanceof LLMError) throw e
      throw new LLMError(e.message)
    } finally {
      if (reply.length) this.history.push({ role: 'user', content: text }, { role: 'assistant', content: reply.join('') })
    }
  }
}

// ------------------------------------------------------------------ doing: understanding "open X and then Y"

const SPLIT = /\s*(?:,\s*(?:and\s+|then\s+)?|\s+and\s+then\s+|\s+then\s+|\s+and\s+|\s+&\s+)\s*/i
const OPEN = /^(?:please\s+|can you\s+|could you\s+)?(?:open|launch|pull up|start up|go to)\s+(?:my\s+|the\s+)?(.+)$/i
const CLOSE = /^(?:please\s+)?(?:close|quit|shut down|exit)\s+(?:my\s+|the\s+)?(.+)$/i
const MUSIC = /\b(?:play|start|put on|queue|turn on)\b.*\b(?:playlist|music|songs?|lo-?fi|tunes|vibes)\b/i
const FOCUS_WORDS = /\b(?:focus|pomodoro|study session)\b/i
const START_WORDS = /\b(?:start|begin|set up|do)\b/i
const MINUTES = /(\d{1,3})\s*-?\s*min/i
const FILLER = new Set(['my', 'the', 'a', 'some', 'please', 'playlist', 'music', 'songs', 'song'])
const MUSIC_VERBS = new Set(['play', 'start', 'put', 'on', 'queue', 'turn'])

export const musicQuery = (text) => {
  const words = (text.toLowerCase().match(/[\w'-]+/g) || []).filter((w) => !FILLER.has(w) && !MUSIC_VERBS.has(w))
  return words.join(' ').trim() || 'study'
}

/** The steps in a request, or [] if it isn't a multi-step / music / focus command (so the chat brain answers instead). */
export function parseChain(text) {
  const steps = []
  for (const part of text.trim().split(SPLIT)) {
    let p = part.replace(/^[\s.!?]+|[\s.!?]+$/g, '')
    if (!p) continue
    p = p.replace(/^(?:hey\s+)?cranberry[,:]?\s*/i, '')
    let m
    if (MUSIC.test(p)) steps.push({ kind: 'music', arg: musicQuery(p) })
    else if ((m = p.match(OPEN))) steps.push({ kind: 'open', arg: m[1].trim() })
    else if ((m = p.match(CLOSE))) steps.push({ kind: 'close', arg: m[1].trim() })
    else if (START_WORDS.test(p) && FOCUS_WORDS.test(p)) steps.push({ kind: 'focus', arg: (p.match(MINUTES) || [])[1] || '25' })
    else if (steps.length && ['open', 'close'].includes(steps[steps.length - 1].kind) && p.split(/\s+/).length <= 3 && /^[a-z0-9]+$/i.test(p.replace(/\s/g, ''))) {
      steps.push({ kind: steps[steps.length - 1].kind, arg: p })           // "open Chrome, then Spotify"
    }
  }
  const musical = steps.some((s) => s.kind === 'music')
  return steps.length >= 2 || musical || steps.some((s) => s.kind === 'focus') ? steps : []
}

// ---- names of apps and websites

export const KNOWN_APPS = ['WhatsApp', 'Chrome', 'Edge', 'Firefox', 'Spotify', 'Notepad', 'Calculator', 'Word', 'Excel', 'PowerPoint', 'Outlook', 'Teams', 'Discord',
  'Slack', 'VS Code', 'Terminal', 'File Explorer', 'Paint', 'Settings', 'Notion', 'Steam', 'Zoom', 'OneNote', 'Calendar', 'Mail', 'Photos', 'Camera', 'Clock']
const ALIASES = {
  WhatsApp: ['whatsapp', 'whats app', 'whatsup', 'watsapp', 'whatsaap'], Chrome: ['chrome', 'google chrome'], Edge: ['edge', 'microsoft edge'], Firefox: ['firefox'],
  Spotify: ['spotify', 'spotifiy'], Notepad: ['notepad', 'note pad'], Calculator: ['calculator', 'calc'], Word: ['word', 'ms word', 'microsoft word'],
  Excel: ['excel'], PowerPoint: ['powerpoint', 'power point', 'ppt'], Outlook: ['outlook'], Teams: ['teams', 'microsoft teams'], Discord: ['discord'], Slack: ['slack'],
  'VS Code': ['vs code', 'vscode', 'visual studio code', 'code'], Terminal: ['terminal', 'cmd', 'command prompt', 'powershell'], 'File Explorer': ['explorer', 'file explorer', 'files', 'my files'],
  Paint: ['paint', 'ms paint'], Settings: ['settings'], Notion: ['notion'], Steam: ['steam'], Zoom: ['zoom'], OneNote: ['onenote', 'one note'], Calendar: ['calendar', 'cal'],
  Mail: ['mail', 'email'], Photos: ['photos'], Camera: ['camera'], Clock: ['clock', 'alarms'],
}
// the program to start for the built-in names (found with no Start-menu shortcut)
const LAUNCH = { Notepad: 'notepad', Calculator: 'calc', Paint: 'mspaint', 'File Explorer': 'explorer', Terminal: 'wt', Settings: 'ms-settings:', Clock: 'ms-clock:',
  Calendar: 'outlookcal:', Mail: 'outlookmail:', Photos: 'ms-photos:', Camera: 'microsoft.windows.camera:', Edge: 'msedge', Chrome: 'chrome', Firefox: 'firefox' }
const WEB_APPS = {
  'https://notebooklm.google.com': ['notebooklm', 'notebook lm'], 'https://mail.google.com': ['gmail', 'google mail'], 'https://docs.google.com': ['google docs', 'gdocs'],
  'https://sheets.google.com': ['google sheets', 'gsheets'], 'https://drive.google.com': ['google drive', 'gdrive'], 'https://youtube.com': ['youtube'],
  'https://calendar.google.com': ['google calendar', 'gcal'], 'https://chat.openai.com': ['chatgpt'], 'https://github.com': ['github'],
}
const WEB_NAMES = { 'https://notebooklm.google.com': 'NotebookLM', 'https://mail.google.com': 'Gmail', 'https://docs.google.com': 'Google Docs', 'https://sheets.google.com': 'Google Sheets',
  'https://drive.google.com': 'Google Drive', 'https://youtube.com': 'YouTube', 'https://calendar.google.com': 'Google Calendar', 'https://chat.openai.com': 'ChatGPT',
  'https://github.com': 'GitHub' }
export const webAppName = (url) => WEB_NAMES[url] || url

export const tokenize = (text) => text.toLowerCase().match(/[a-z0-9']+|[^\sa-z0-9']/gu) || []

/** A similarity between 0 and 1 (the share of matching characters, like difflib's ratio). */
export function similarity(a, b) {
  if (a === b) return 1
  if (!a || !b) return 0
  const m = a.length, n = b.length
  let prev = new Array(n + 1).fill(0), best = 0
  // longest-common-subsequence length, close enough to difflib's matching-blocks ratio for short app names
  for (let i = 1; i <= m; i++) {
    const cur = new Array(n + 1).fill(0)
    for (let j = 1; j <= n; j++) cur[j] = a[i - 1] === b[j - 1] ? prev[j - 1] + 1 : Math.max(prev[j], cur[j - 1])
    prev = cur; best = cur[n]
  }
  return (2 * best) / (m + n)
}

/** Whole words or word pairs first (so "mail" never matches inside "gmail"), then a strict fuzzy match for typos. */
export function bestMatch(text, candidates) {
  const words = tokenize(text)
  const phrases = [...words, ...words.slice(1).map((w, i) => `${words[i]} ${w}`)]
  for (const ph of phrases) if (Object.hasOwn(candidates, ph)) return candidates[ph]
  let value = null, score = 0
  for (const ph of phrases) {
    if (ph.length < 4) continue
    for (const [key, v] of Object.entries(candidates)) {
      const s = similarity(ph, key)
      if (s >= 0.9 && s > score) { value = v; score = s }
    }
  }
  return value
}

export function appSlot(text, installed = []) {
  const candidates = {}
  for (const app of [...KNOWN_APPS, ...installed]) candidates[app.toLowerCase()] = app
  for (const [app, list] of Object.entries(ALIASES)) for (const a of list) candidates[a] = app
  return bestMatch(text, candidates)
}
export function webAppSlot(text) {
  const candidates = {}
  for (const [url, names] of Object.entries(WEB_APPS)) for (const n of names) candidates[n] = url
  return bestMatch(text, candidates)
}

/** A request like "open spotify" or "close that window": what to do, to what. */
export function understand(text, installed = []) {
  const t = text.toLowerCase()
  const app = appSlot(text, installed)
  if ((app || webAppSlot(text)) && /\b(open|launch|start|pull up)\b/.test(t)) {
    if (app) return { intent: 'open_app', kind: 'app', target: app }
    return { intent: 'open_app', kind: 'url', target: webAppSlot(text) }
  }
  if (/\b(close|quit|shut)\b/.test(t)) {
    if (app) return { intent: 'close_app', kind: 'app', target: app }
    if (/\b(this|that|the)\s+(window|tab)\b|^close$/.test(t)) return { intent: 'close_app', kind: 'window', target: null }
  }
  return { intent: 'chat' }
}

const pick = (a) => a[Math.floor(Math.random() * a.length)]
export const REPLIES = {
  open_app: ['on it! opening {app} 🐾', 'opening {app} now 💪'],
  close_app: ['closing {app} for you 🐾', 'on it: shutting {app} down'],
  close_window: ['closing this window 🐾', 'on it: closing that window'],
}
export const replyFor = (kind, app) => pick(REPLIES[kind]).replace('{app}', app || '')

// ------------------------------------------------------------------ doing: Windows

/** The programs in the Start menu, so "open anything" means anything you have installed. */
let appCache = { at: 0, list: [] }
export function installedApps() {
  if (process.platform !== 'win32') return []
  if (Date.now() - appCache.at < 5 * 60 * 1000) return appCache.list
  const roots = [path.join(process.env.ProgramData || 'C:\\ProgramData', 'Microsoft', 'Windows', 'Start Menu', 'Programs'),
    path.join(process.env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming'), 'Microsoft', 'Windows', 'Start Menu', 'Programs')]
  const found = new Map()
  const skip = /uninstall|readme|release notes|documentation|\bhelp\b|website|license|manual|support/i
  const walk = (dir, depth) => {
    let entries = []
    try { entries = fs.readdirSync(dir, { withFileTypes: true }) } catch { return }
    for (const e of entries) {
      const full = path.join(dir, e.name)
      if (e.isDirectory() && depth < 3) walk(full, depth + 1)
      else if (e.isFile() && /\.lnk$/i.test(e.name)) {
        const name = e.name.replace(/\.lnk$/i, '')
        if (!skip.test(name) && !found.has(name.toLowerCase())) found.set(name.toLowerCase(), { name, file: full })
      }
    }
  }
  roots.forEach((r) => walk(r, 0))
  appCache = { at: Date.now(), list: [...found.values()] }
  return appCache.list
}

const safeName = (s) => String(s).replace(/[^\p{L}\p{N} ._+-]/gu, '').trim().slice(0, 60)

// the program behind a name, where it isn't just the name ("Word" is winword.exe)
const PROCESSES = {
  Word: ['winword'], Excel: ['excel'], PowerPoint: ['powerpnt'], Outlook: ['outlook', 'olk'], OneNote: ['onenote'], Teams: ['ms-teams', 'teams', 'msteams'],
  'VS Code': ['code'], Chrome: ['chrome'], Edge: ['msedge'], Firefox: ['firefox'], Spotify: ['spotify'], Discord: ['discord'], Slack: ['slack'], WhatsApp: ['whatsapp'],
  Notepad: ['notepad'], Calculator: ['calculatorapp', 'calculator', 'calc'], Paint: ['mspaint'], Terminal: ['windowsterminal', 'wt'], 'File Explorer': [], Notion: ['notion'],
  Steam: ['steam'], Zoom: ['zoom'], Settings: [], Photos: [], Camera: [], Clock: [], Calendar: [], Mail: [],
}

/** PowerShell that asks each window of those programs to close, the way clicking X does, and prints how many it asked.
 *  Only program names are matched (never window titles), and never the shell, this app or the PowerShell running it. */
export function closeScript(processNames) {
  const names = processNames.map(safeName).filter(Boolean).map((n) => n.replace(/\s+/g, '').toLowerCase())
  if (!names.length) return null
  const cond = names.map((n) => `$_.ProcessName -like '${n}*'`).join(' -or ')
  return `$n = @(Get-Process | Where-Object { $_.MainWindowTitle -and $_.ProcessName -notin @('explorer','cariberry','electron','ApplicationFrameHost','dwm','csrss','winlogon','services','svchost','powershell') -and (${cond}) } | ForEach-Object { if ($_.CloseMainWindow()) { 1 } }).Count; Write-Output $n`
}

export function makeActions({ shell, win32mod, status = () => {} }) {
  const apps = () => installedApps()
  return {
    installedNames: () => apps().map((a) => a.name),
    /** Starts a program from your Start menu, or one of the few built-in ones. It never guesses at a command line. */
    async openApp(name) {
      const n = safeName(name)
      if (!n) return false
      const lower = n.toLowerCase()
      const list = apps()
      const hit = list.find((a) => a.name.toLowerCase() === lower) || list.find((a) => a.name.toLowerCase().includes(lower)) || list.find((a) => lower.includes(a.name.toLowerCase()) && a.name.length > 3)
      if (hit) return (await shell.openPath(hit.file)) === ''
      const launch = LAUNCH[n]
      if (!launch) return false
      if (launch.endsWith(':')) { await shell.openExternal(launch); return true }
      if (process.platform !== 'win32') return false
      return new Promise((resolve) => {
        const p = spawn('cmd.exe', ['/c', 'start', '', launch], { windowsHide: true, stdio: 'ignore', detached: true })
        p.on('error', () => resolve(false)); p.on('exit', (code) => resolve(code === 0))
        p.unref()
      })
    },
    async openUrl(url) { if (/^https:\/\//.test(url)) { await shell.openExternal(url); return true } return false },
    /** Closes the program's windows the polite way (like clicking X), so unsaved work still gets asked about. */
    closeApp(name) {
      const n = safeName(name)
      if (!n || process.platform !== 'win32') return Promise.resolve(false)
      const canonical = Object.keys(PROCESSES).find((k) => k.toLowerCase() === n.toLowerCase())
      const script = closeScript(canonical ? PROCESSES[canonical] : [n])
      if (!script) return Promise.resolve(false)
      return new Promise((resolve) => {
        execFile(win32mod.powershellPath?.() || 'powershell.exe', ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', script], { windowsHide: true, timeout: 8000 }, (e, out) => resolve(!e && Number(String(out).trim()) > 0))
      })
    },
    closeFrontWindow(hwnd) { return win32mod.closeWindow(hwnd) },
    status,
  }
}

/** Runs a chain of steps and says what happened. `env` is {actions, startFocus, startRadio, status}. */
export async function runSteps(steps, env) {
  const done = []
  for (const step of steps) {
    if (step.kind === 'open' || step.kind === 'close') {
      const slot = understand(`${step.kind} ${step.arg}`, env.actions.installedNames())
      const label = slot.target ? (slot.kind === 'url' ? webAppName(slot.target) : slot.target) : step.arg
      env.status(`🐾 ${step.kind === 'open' ? 'opening' : 'closing'} ${label}...`)
      let ok = false
      if (step.kind === 'open') ok = slot.kind === 'url' ? await env.actions.openUrl(slot.target) : await env.actions.openApp(slot.target || step.arg)
      else ok = await env.actions.closeApp(slot.target || step.arg)
      done.push(ok ? `${step.kind === 'open' ? 'opened' : 'closed'} ${label}` : `couldn't ${step.kind} ${label}`)
    } else if (step.kind === 'music') {
      env.status('🐾 finding your music...')
      done.push(await startMusic(step.arg, env))
    } else if (step.kind === 'focus') {
      await env.startFocus(Number(step.arg) || 25)
      done.push(`started a ${step.arg} minute focus`)
    }
  }
  env.status('')
  return done.length ? `done! ${done.join(', then ')} 🐾` : 'hmm, I couldn\'t do that one 🥺'
}

/** Study music: her own lo-fi radio for "lo-fi" and "study", or Spotify if you ask for it by name. */
async function startMusic(query, env) {
  const wantsSpotify = /spotify/i.test(query)
  if (wantsSpotify && env.actions.installedNames().some((n) => /spotify/i.test(n))) {
    const ok = await env.actions.openApp('Spotify')
    if (ok) return 'opened Spotify'
  }
  const station = await env.startRadio(query)
  return `started ${station}`
}

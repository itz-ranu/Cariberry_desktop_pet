// What are you doing right now? Every two seconds: which program is in front, its window title, where the
// window is and whether a full-screen app is running. For a browser (and only if "browser awareness" is on)
// it also reads the address from the address bar through Windows UI Automation, so Instagram Reels can be told
// apart from the Instagram feed. Windows needs no permission for any of it.
//
// Nothing here leaves the machine, and the address is never stored: it is matched against the rules and dropped.
import { spawn, execFile } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import * as win32 from './win32.js'

const BROWSERS = {
  chrome: 'Google Chrome', msedge: 'Microsoft Edge', firefox: 'Firefox', brave: 'Brave', opera: 'Opera', opera_gx: 'Opera GX', vivaldi: 'Vivaldi',
  arc: 'Arc', iexplore: 'Internet Explorer', waterfox: 'Waterfox', librewolf: 'LibreWolf', thorium: 'Thorium', chromium: 'Chromium', zen: 'Zen Browser',
}
// programs whose file name isn't what you'd call them
const FRIENDLY = {
  code: 'VS Code', winword: 'Word', excel: 'Excel', powerpnt: 'PowerPoint', outlook: 'Outlook', onenote: 'OneNote', msteams: 'Teams', teams: 'Teams',
  explorer: 'File Explorer', windowsterminal: 'Terminal', wt: 'Terminal', cmd: 'Command Prompt', powershell: 'PowerShell', notepad: 'Notepad',
  mspaint: 'Paint', calc: 'Calculator', spotify: 'Spotify', discord: 'Discord', slack: 'Slack', whatsapp: 'WhatsApp', telegram: 'Telegram',
  steam: 'Steam', epicgameslauncher: 'Epic Games', javaw: 'Java', devenv: 'Visual Studio', acrord32: 'Acrobat Reader', 'notepad++': 'Notepad++',
  obsidian: 'Obsidian', notion: 'Notion', figma: 'Figma', zoom: 'Zoom', roblox: 'Roblox', robloxplayerbeta: 'Roblox', anki: 'Anki', kindle: 'Kindle',
  applicationframehost: 'a Windows app', systemsettings: 'Settings', taskmgr: 'Task Manager', snippingtool: 'Snipping Tool', vlc: 'VLC', itunes: 'iTunes',
}
const stem = (exe) => (exe || '').toLowerCase().replace(/\.exe$/, '')
export const isBrowserExe = (exe) => Object.hasOwn(BROWSERS, stem(exe))
export const browserName = (exe) => BROWSERS[stem(exe)] || null

/** "Page title - Google Chrome" becomes "Page title". Edge hides a zero-width space inside its own name, and (alone among
 *  browsers) puts the profile name before it: "Page and 2 more pages - Personal - Microsoft Edge". The site's own name
 *  ("- YouTube") must survive, because the rules look for it. */
export function stripBrowserSuffix(title = '') {
  return title.replace(/[\u200b-\u200f\u2060\ufeff]/g, '')
    .replace(/\s+[-–—]\s+[^-–—]+\s+[-–—]\s+Microsoft Edge\s*$/i, '')
    .replace(/\s+[-–—]\s+(?:Google Chrome|Microsoft Edge|Mozilla Firefox|Firefox|Brave|Opera(?: GX)?|Vivaldi|Arc|Chromium|Waterfox|LibreWolf|Thorium|Zen Browser)\s*$/i, '')
    .replace(/\s+and \d+ more pages?\s*$/i, '')
    .trim()
}

function prettyName(fg) {
  const s = stem(fg.exe)
  if (BROWSERS[s]) return BROWSERS[s]
  if (s === 'applicationframehost' && fg.title) return fg.title          // Store apps: the window title is the app's name
  if (FRIENDLY[s]) return FRIENDLY[s]
  if (!s) return fg.title || 'something'
  return s.replace(/[_-]+/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase())
}

// ------------------------------------------------------------------ the address bar (UI Automation)

const UIA_SCRIPT = String.raw`
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$AE = [System.Windows.Automation.AutomationElement]
$edit = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)
[Console]::Out.WriteLine('ready')
while ($true) {
  $line = [Console]::In.ReadLine()
  if ($null -eq $line) { break }
  $url = ''
  try {
    $root = $AE::FromHandle([IntPtr][int64]($line.Trim()))
    $box = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $edit)
    if ($box -ne $null) {
      $vp = $box.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
      $url = [string]$vp.Current.Value
    }
  } catch {}
  $url = $url -replace '[\r\n|]', ' '
  [Console]::Out.WriteLine(($line.Trim()) + '|' + $url)
}
`

class AddressReader {
  constructor(dir) {
    this.dir = dir
    this.proc = null; this.ready = false; this.buf = ''
    this.waiting = new Map()        // hwnd -> resolve
    this.lastUse = 0
    this.failures = 0
  }

  ensure() {
    if (this.proc || this.failures >= 3 || process.platform !== 'win32') return
    try {
      const file = path.join(this.dir, 'address-reader.ps1')
      fs.mkdirSync(this.dir, { recursive: true })
      // a UTF-8 BOM so Windows PowerShell reads the file as UTF-8
      fs.writeFileSync(file, '' + UIA_SCRIPT)
      const p = spawn(win32.powershellPath(), ['-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', file],
        { windowsHide: true, stdio: ['pipe', 'pipe', 'ignore'] })
      p.stdout.setEncoding('utf8')
      p.stdout.on('data', (d) => this.onData(d))
      p.on('error', () => { this.failures++; this.reset() })
      p.on('exit', () => { if (this.proc === p) { this.failures += this.ready ? 0 : 1; this.reset() } })
      this.proc = p
    } catch { this.failures++ }
  }

  onData(d) {
    this.buf += d
    let i
    while ((i = this.buf.indexOf('\n')) >= 0) {
      const line = this.buf.slice(0, i).trim(); this.buf = this.buf.slice(i + 1)
      if (line === 'ready') { this.ready = true; continue }
      const bar = line.indexOf('|')
      if (bar < 0) continue
      const key = line.slice(0, bar), url = line.slice(bar + 1).trim()
      this.waiting.get(key)?.(url); this.waiting.delete(key)
    }
  }

  reset() {
    this.proc = null; this.ready = false; this.buf = ''
    for (const r of this.waiting.values()) r('')
    this.waiting.clear()
  }

  stop() { try { this.proc?.stdin.end(); this.proc?.kill() } catch {} this.reset() }

  /** The address in that window's address bar, or '' if it can't be read. */
  read(hwnd) {
    this.ensure()
    this.lastUse = Date.now()
    if (!this.proc || !this.ready) return Promise.resolve('')
    return new Promise((resolve) => {
      const key = String(hwnd)
      const t = setTimeout(() => { this.waiting.delete(key); resolve('') }, 3500)
      this.waiting.set(key, (v) => { clearTimeout(t); resolve(v) })
      try { this.proc.stdin.write(`${hwnd}\n`) } catch { clearTimeout(t); this.waiting.delete(key); resolve('') }
    })
  }
}

// ------------------------------------------------------------------ the monitor

export class ActivityMonitor {
  /** `onSample(sample)` gets {exe, name, title, browser, url, probe, uwp, self, bounds, fullscreen, hwnd}. */
  constructor({ onSample, dataDir, selfExe }) {
    this.onSample = onSample
    this.selfExe = (selfExe || '').toLowerCase()
    this.reader = new AddressReader(dataDir)
    this.config = { browserAwareness: false, focusCoaching: true }
    this.timer = null
    this.last = null            // the most recent sample, for closing a tab
    this.lastForeign = null     // the last window that wasn't ours, for "close this window"
    this.busy = false
  }

  setConfig(c) { Object.assign(this.config, c); if (!this.config.browserAwareness) this.reader.stop() }

  start() {
    if (this.timer) return
    const tick = async () => {
      if (!this.busy) { this.busy = true; try { await this.sample() } catch (e) { console.error('[monitor]', e.message) } this.busy = false }
      this.timer = setTimeout(tick, 2000)
    }
    tick()
  }

  stop() { clearTimeout(this.timer); this.timer = null; this.reader.stop() }

  async sample() {
    if (process.platform === 'win32') return this.sampleWindows()
    // development off Windows only: CARI_FAKE_ACTIVITY='{"exe":"chrome.exe","name":"Google Chrome","title":"Instagram","browser":true,"url":"instagram.com/reels/x"}'
    if (process.env.CARI_FAKE_ACTIVITY) {
      try { this.onSample({ self: false, fullscreen: false, bounds: null, url: '', uwp: false, ...JSON.parse(process.env.CARI_FAKE_ACTIVITY) }) } catch { /* bad fixture */ }
      return
    }
    if (process.platform === 'darwin' && process.env.CARI_MONITOR) return this.sampleMac()
  }

  async sampleWindows() {
    const fg = win32.foreground()
    const fullscreen = win32.fullscreenAppRunning()
    if (!fg || !fg.exe) { this.onSample({ none: true, fullscreen, self: false }); return }
    const browser = isBrowserExe(fg.exe)
    const self = fg.exe === this.selfExe || /^cariberry/i.test(fg.exe)
    const sample = {
      hwnd: fg.hwnd, exe: fg.exe, name: prettyName(fg), title: browser ? stripBrowserSuffix(fg.title) : fg.title, rawTitle: fg.title,
      browser, uwp: stem(fg.exe) === 'applicationframehost', self, fullscreen, url: '', probe: browser ? 'title' : '',
      bounds: fg.rect && !fg.minimized && fg.rect.right > fg.rect.left ? { x: fg.rect.left, y: fg.rect.top, w: fg.rect.right - fg.rect.left, h: fg.rect.bottom - fg.rect.top } : null,
    }
    if (browser && this.config.browserAwareness && this.config.focusCoaching && !fg.minimized) {
      const url = await this.reader.read(fg.hwnd)
      if (url) { sample.url = url.toLowerCase(); sample.probe = 'address' }
    } else if (Date.now() - this.reader.lastUse > 60000) this.reader.stop()      // not needed for a while: free its memory
    this.last = sample
    if (!self) this.lastForeign = sample
    this.onSample(sample)
  }

  sampleMac() {
    // development on a Mac only: just the front app's name, so the pipeline can be exercised
    const script = 'tell application "System Events" to set p to first application process whose frontmost is true\nreturn (name of p) & "|" & (bundle identifier of p)'
    return new Promise((resolve) => {
      execFile('osascript', ['-e', script], { timeout: 1500 }, (e, out) => {
        if (!e && out) {
          const [name, id] = out.trim().split('|')
          this.onSample({ exe: id || name, name, title: '', browser: false, uwp: false, self: false, fullscreen: false, url: '', bounds: null })
        }
        resolve()
      })
    })
  }
}

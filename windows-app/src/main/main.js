// Cariberry for Windows: the app shell. It owns the windows, the tray, the files on disk and the parts of the
// system a web page can't reach (which program is in front, pressing Ctrl+W, the login item). The pet herself
// lives in the pet window's page: src/renderer/pet.js and runtime.js. Everything else asks her through `rpc`.
import { app, ipcMain, protocol, session, desktopCapturer, powerMonitor, screen, shell, Menu, dialog } from 'electron'
import path from 'node:path'
import os from 'node:os'
import fs from 'node:fs'
import { spawn } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { readJSON, writeJSON, dataDir } from './store.js'
import { createWindows } from './windows.js'
import { createTray } from './tray.js'
import { ActivityMonitor, isBrowserExe } from './monitor.js'
import { createChat } from './chat.js'
import { makeActions } from './brain.js'
import * as secrets from './secrets.js'
import * as win32 from './win32.js'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const ROOT = app.getAppPath()
const PRELOAD = path.join(HERE, 'preload.cjs')
const ICON = path.join(ROOT, 'assets', 'icon.png')
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.wav': 'audio/wav',
  '.png': 'image/png', '.svg': 'image/svg+xml', '.woff2': 'font/woff2', '.ico': 'image/x-icon' }

protocol.registerSchemesAsPrivileged([{ scheme: 'cari', privileges: { standard: true, secure: true, supportFetchAPI: true, corsEnabled: true, stream: true } }])
app.setName('Cariberry')
app.setAppUserModelId('com.cariberry.app')
// A transparent, always-on-top window is "covered" by other windows as far as Chromium can tell; without this it
// may stop painting her. Also let her sounds start without a click.
app.commandLine.appendSwitch('disable-features', 'CalculateNativeWinOcclusion')
app.commandLine.appendSwitch('autoplay-policy', 'no-user-gesture-required')

// Some PCs (virtual machines, remote desktop, very old graphics drivers) can't draw with the GPU. If the GPU process
// dies, she remembers it and draws in software from the next start, so she still shows up.
const SOFTWARE_FLAG = path.join(dataDir(), 'software-rendering')
if (fs.existsSync(SOFTWARE_FLAG)) app.disableHardwareAcceleration()
app.on('child-process-gone', (_e, d) => {
  if (d.type !== 'GPU' || d.reason === 'clean-exit' || d.reason === 'killed' || fs.existsSync(SOFTWARE_FLAG)) return
  try { fs.writeFileSync(SOFTWARE_FLAG, `the GPU process stopped (${d.reason}); Cariberry now draws in software\n`) } catch { return }
  app.relaunch(); app.exit(0)
})

const pageUrl = (page, query = '') => `cari://app/src/renderer/${page}${query}`

if (!app.requestSingleInstanceLock()) {
  app.quit()
} else {
  start()
}

function start() {
  let wm = null, trayHandle = null, monitor = null, chat = null
  let quitting = false
  let theme = readJSON('prefs.json', {}).theme || 'coquette'
  let aboveFullscreen = !!readJSON('prefs.json', {}).aboveFullscreen
  const pending = new Map()               // rpc id -> resolve
  let rpcId = 0

  // ------------------------------------------------------------------ asking her (the pet page) to do things

  const rpc = (name, ...args) => new Promise((resolve) => {
    const pet = wm?.pet
    if (!pet || pet.isDestroyed()) return resolve(null)
    const id = ++rpcId
    const t = setTimeout(() => { pending.delete(id); resolve(null) }, 4000)
    pending.set(id, (v) => { clearTimeout(t); resolve(v) })
    pet.webContents.send('rpc', id, name, args)
  })
  ipcMain.on('rpc:result', (_e, id, value) => { pending.get(id)?.(value); pending.delete(id) })
  ipcMain.handle('rpc', (_e, name, ...args) => rpc(name, ...args))

  // ------------------------------------------------------------------ screens and the cursor

  const screenInfo = () => ({
    primaryH: screen.getPrimaryDisplay().bounds.height,
    displays: screen.getAllDisplays().map((d) => ({ work: d.workArea, bounds: d.bounds, scale: d.scaleFactor })),
  })
  ipcMain.handle('screens', () => screenInfo())
  const watchScreens = () => {
    const send = () => wm.sendPet('screens', screenInfo())
    for (const ev of ['display-added', 'display-removed', 'display-metrics-changed']) screen.on(ev, send)
  }

  // her eyes follow the cursor, and being carried follows it exactly: sampled gently, and quickly only while she's held
  let cursorEvery = 83, lastCursor = ''
  const pollCursor = () => {
    const p = screen.getCursorScreenPoint()
    const key = `${p.x},${p.y}`
    if (key !== lastCursor && wm.pet && !wm.pet.isDestroyed()) { lastCursor = key; wm.pet.webContents.send('cursor', p) }
    setTimeout(pollCursor, cursorEvery)
  }
  ipcMain.on('cursor:rate', (_e, ms) => { cursorEvery = Math.min(200, Math.max(12, Number(ms) || 83)) })

  ipcMain.on('pet:bounds', (_e, b) => wm.setPetBounds(b))
  ipcMain.on('pet:ignore', (_e, ignore) => wm.setPetClickable(!ignore))
  ipcMain.on('pet:level', (_e, v) => { aboveFullscreen = !!v; wm.setPetLevel(aboveFullscreen); if (aboveFullscreen) wm.setPetVisible(true) })

  // ------------------------------------------------------------------ files on disk

  ipcMain.handle('load', () => ({ save: readJSON('pet.json', {}), prefs: readJSON('prefs.json', {}), rules: readJSON('rules.json', null) }))
  ipcMain.on('save', (_e, d) => {
    if (d.save) writeJSON('pet.json', d.save)
    if (d.prefs) writeJSON('prefs.json', d.prefs)
    if (d.rules) writeJSON('rules.json', d.rules)
  })
  ipcMain.on('theme', (_e, id) => { theme = id; wm.sendAll('theme', id); wm.restyleStats(id) })
  ipcMain.handle('theme:get', () => theme)

  // ------------------------------------------------------------------ start with Windows

  const setLogin = (on) => { try { app.setLoginItemSettings({ openAtLogin: !!on }) } catch { /* not allowed here */ } }
  ipcMain.on('login:set', (_e, on) => setLogin(on))

  // ------------------------------------------------------------------ closing a tab for her

  ipcMain.handle('tab:close', () => {
    const last = monitor?.last
    const fg = win32.foreground()
    // only ever press Ctrl+W if a browser is still what's in front: never at whatever else you've since clicked on
    if (!fg || !isBrowserExe(fg.exe) || !last || last.hwnd !== fg.hwnd) return { ok: false }
    const ok = win32.sendKeys([win32.VK.CONTROL, win32.VK.W])
    return { ok, exe: fg.exe, title: last.title, url: last.url }
  })
  ipcMain.handle('tab:reopen', (_e, { url, exe } = {}) => {
    const fg = win32.foreground()
    if (fg && isBrowserExe(fg.exe) && (!exe || fg.exe === exe)) return win32.sendKeys([win32.VK.CONTROL, win32.VK.SHIFT, win32.VK.T])
    if (url && /^https?:\/\//i.test(url)) { shell.openExternal(url); return true }
    return false
  })

  // ------------------------------------------------------------------ what you're doing, and whether you're there

  const watchPresence = () => {
    const send = (state) => wm.sendPet('presence', state)
    powerMonitor.on('lock-screen', () => send({ screenOff: true }))
    powerMonitor.on('unlock-screen', () => send({ screenOff: false }))
    powerMonitor.on('suspend', () => send({ screenOff: true }))
    powerMonitor.on('resume', () => send({ screenOff: false }))
    monitor = new ActivityMonitor({
      dataDir: dataDir(), selfExe: path.basename(process.execPath),
      onSample: (sample) => {
        // a full-screen app in front: stay out of its way, unless she's been told to nag over it
        if (typeof sample.fullscreen === 'boolean') wm.setPetVisible(aboveFullscreen || !sample.fullscreen)
        const out = { ...sample, idle: powerMonitor.getSystemIdleTime() }
        if (sample.bounds && process.platform === 'win32') {
          const d = screen.screenToDipRect(null, { x: sample.bounds.x, y: sample.bounds.y, width: sample.bounds.w, height: sample.bounds.h })
          out.bounds = { x: d.x, y: d.y, w: d.width, h: d.height }
        }
        wm.sendPet('activity', out)
      },
    })
    monitor.start()
  }
  ipcMain.on('monitor:config', (_e, c) => monitor?.setConfig(c))

  // ------------------------------------------------------------------ the tray

  ipcMain.on('tray:icon', (_e, dataUrl) => trayHandle?.setFace(dataUrl))
  ipcMain.on('tray:tip', (_e, tip) => trayHandle?.setTip(String(tip)))

  // ------------------------------------------------------------------ windows and what opens them

  ipcMain.handle('open', (_e, what, arg) => {
    switch (what) {
      case 'panel': {
        const o = typeof arg === 'string' ? (arg === 'welcome' ? { tab: 'closet', welcome: true } : { tab: arg }) : (arg || {})
        wm.openPanel({ at: 'tray', ...o })
        break
      }
      case 'stats': wm.closePanel(); wm.openStats(); break
      case 'chat': wm.closePanel(); toggleChat(); break
      case 'mood': wm.openCard('mood'); break
      case 'note': wm.closePanel(); wm.openCard('note', { replace: true, pinned: !!readJSON('prefs.json', {}).notePinned }); break
      case 'story': wm.closePanel(); wm.openCard('story', { replace: true }); break
      case 'toast': wm.toast(arg); break
      case 'rules': {
        // Notepad, so a .json file with no program of its own doesn't bring up "How do you want to open this?"
        const f = path.join(dataDir(), 'rules.json')
        if (!fs.existsSync(f)) break
        if (process.platform === 'win32') spawn('notepad.exe', [f], { detached: true, stdio: 'ignore' }).unref(); else shell.openPath(f)
        break
      }
      case 'external': if (/^https:\/\//.test(String(arg))) shell.openExternal(arg); break
      case 'userdata': shell.openPath(dataDir()); break
      default: break
    }
    return true
  })
  ipcMain.handle('quit', () => { app.quit(); return true })
  ipcMain.on('panel:close', () => wm.closePanel())
  ipcMain.on('card:close', (e) => wm.closeWhatSent(e.sender))
  ipcMain.on('card:pin', (_e, pinned) => wm.pinNote(pinned))

  // the daily check-in: answering it opens today's note a moment later
  ipcMain.handle('mood:chosen', async (_e, mood) => {
    wm.closeCard('mood')
    if (mood) { await rpc('moodChosen', mood); setTimeout(() => wm.openCard('note', { replace: true, pinned: !!readJSON('prefs.json', {}).notePinned }), 900) }
    return true
  })

  ipcMain.handle('toast:ready', () => wm.toastData)

  // ------------------------------------------------------------------ chat

  const toggleChat = () => { if (wm.hasCard('chat')) wm.closeCard('chat'); else wm.openCard('chat') }
  ipcMain.handle('chat:open', () => chat.open())
  ipcMain.on('chat:send', (_e, text) => chat.send(text))
  ipcMain.handle('secret:has', (_e, provider) => secrets.hasSecret(provider))
  ipcMain.handle('secret:set', (_e, provider, key) => { const r = secrets.setSecret(provider, key); return r })

  // ------------------------------------------------------------------ pictures to share

  const stamp = () => new Date().toISOString().slice(0, 10)
  let lastStoryFile = null
  const storyImage = async () => wm.photograph('storycard', await rpc('storyData'), 360, 640)
  ipcMain.handle('story:save', async () => { try { lastStoryFile = wm.savePng(await storyImage(), `Cariberry study card ${stamp()}.png`); wm.showFile(lastStoryFile); return { ok: true } } catch (e) { console.error(e); return { ok: false } } })
  ipcMain.handle('story:copy', async () => { try { await wm.copyImage(await storyImage()); return { ok: true } } catch (e) { console.error(e); return { ok: false } } })
  ipcMain.handle('story:show', async () => {
    try { if (!lastStoryFile || !fs.existsSync(lastStoryFile)) lastStoryFile = wm.savePng(await storyImage(), `Cariberry study card ${stamp()}.png`); wm.showFile(lastStoryFile); return { ok: true } } catch { return { ok: false } }
  })
  ipcMain.handle('share:day', async (_e, { save, selected, title, date }) => {
    try {
      const s = await rpc('stats')
      if (!s) return { ok: false }
      const data = { name: s.name, species: s.species, coat: s.coatIndex, outfit: s.outfit, dayTitle: title, date, focusMinutes: s.dailyFocus[selected] || 0, goalMinutes: s.dailyGoal,
        streak: s.streakDays, sessions: s.dailySessions[selected] || 0, tasks: s.dailyTasks[selected] || 0, level: s.level, title: s.levelTitle }
      const img = await wm.photograph('sharecard', data, 360, 450)
      if (save) { const f = wm.savePng(img, `${s.name} ${selected}.png`); wm.showFile(f) } else await wm.copyImage(img)
      return { ok: true }
    } catch (e) { console.error(e); return { ok: false } }
  })

  // ------------------------------------------------------------------ the music: hearing what the PC plays (opt-in)

  const allowCapture = () => {
    session.defaultSession.setDisplayMediaRequestHandler(async (request, callback) => {
      // only her own page may ask, and it only ever gets the sound: the picture is thrown away on the other side
      if (!String(request.frame?.url || '').startsWith(pageUrl('pet.html'))) return callback({})
      try {
        const sources = await desktopCapturer.getSources({ types: ['screen'], thumbnailSize: { width: 1, height: 1 } })
        callback({ video: sources[0], audio: 'loopback' })
      } catch { callback({}) }
    })
    session.defaultSession.setPermissionRequestHandler((_wc, _perm, cb) => cb(false))
  }

  // ------------------------------------------------------------------ lifecycle

  const serve = () => {
    protocol.handle('cari', async (req) => {
      try {
        const pathname = decodeURIComponent(new URL(req.url).pathname)
        // her sounds can be replaced by yours: the Sounds folder in her data folder, audio files only
        const own = pathname.match(/^\/userdata\/Sounds\/([\w .-]+\.(?:wav|mp3|m4a|ogg|flac))$/i)
        const full = own ? path.join(dataDir(), 'Sounds', own[1]) : path.normalize(path.join(ROOT, pathname))
        if (!own && (!/^[\\/](src|assets)[\\/]/.test(pathname) || !full.startsWith(ROOT + path.sep))) return new Response('forbidden', { status: 403 })
        const body = await fs.promises.readFile(full)
        return new Response(body, { status: 200, headers: { 'content-type': MIME[path.extname(full).toLowerCase()] || 'application/octet-stream', 'cache-control': app.isPackaged ? 'max-age=3600' : 'no-store' } })
      } catch { return new Response('not found', { status: 404 }) }
    })
  }

  app.on('second-instance', () => { if (wm) wm.openPanel({ tab: 'home', at: 'tray' }) })
  app.on('window-all-closed', () => { /* she lives in the tray: closing every window doesn't quit */ })
  app.on('before-quit', (e) => {
    if (quitting) return
    e.preventDefault(); quitting = true
    monitor?.stop()
    Promise.race([rpc('flush'), new Promise((r) => setTimeout(r, 1200))]).then(() => setTimeout(() => app.exit(0), 150))
  })

  app.whenReady().then(() => {
    Menu.setApplicationMenu(null)
    if (process.platform === 'darwin') app.dock?.hide()
    serve()
    allowCapture()
    wm = createWindows({ preload: PRELOAD, pageUrl, iconPath: ICON, getTheme: () => theme, getTray: () => trayHandle?.tray })
    const actions = makeActions({ shell, win32mod: win32 })
    chat = createChat({ wm, rpc, actions, secrets, lastForeign: () => monitor?.lastForeign })
    wm.createPet()
    trayHandle = createTray({
      fallbackIcon: ICON,
      onToggle: () => wm.togglePanel({ at: 'tray' }),
      items: [
        { label: 'Open Cariberry', click: () => wm.openPanel({ at: 'tray' }) },
        { label: 'Start a 25 minute focus', click: () => rpc('startFocus', 25) },
        { label: 'Chat with her', click: toggleChat },
        { label: 'Today\'s note', click: () => wm.openCard('note', { replace: true }) },
        { type: 'separator' },
        { label: 'Mute / unmute her voice', click: () => rpc('toggleMute') },
        { label: 'Show her stats', click: () => wm.openStats() },
        { type: 'separator' },
        { label: 'Quit Cariberry', click: () => app.quit() },
      ],
    })
    watchScreens()
    pollCursor()
    watchPresence()
    // starting with Windows is opt-in: it stays off until the user turns it on in Settings, and that choice is remembered
    if (process.argv.includes('--diagnose')) diagnose()
  })

  // `Cariberry.exe --diagnose` writes what she can see to a file on the Desktop, so a problem can be shown to someone
  function diagnose() {
    const lines = [`Cariberry ${app.getVersion()} on ${process.platform} ${process.arch}`, `Electron ${process.versions.electron}, Chromium ${process.versions.chrome}`, `Windows ${os.release()} (${os.version?.() || '?'})`, `drawing: ${fs.existsSync(SOFTWARE_FLAG) ? 'software (the GPU failed once)' : 'GPU'}`, `PowerShell: ${win32.powershellPath()}`, `win32 calls: ${win32.available() ? 'ok' : `unavailable (${win32.lastError()})`}`]
    setTimeout(() => {
      lines.push(`foreground: ${JSON.stringify(win32.foreground())}`, `full-screen app running: ${win32.fullscreenAppRunning()}`, `last sample: ${JSON.stringify(monitor?.last)}`)
      try { fs.writeFileSync(path.join(app.getPath('desktop'), 'cariberry-diagnose.txt'), lines.join('\n')) } catch { /* ignore */ }
      dialog.showMessageBox({ message: 'Wrote cariberry-diagnose.txt to your Desktop.' })
    }, 6000)
  }
}

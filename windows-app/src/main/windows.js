// Every window the app opens, and where each one goes: the pet's own transparent window, the control panel
// (a flyout above the taskbar, or beside her), the stats window, and the little cards that float near her.
// Positions are in Electron's DIPs (y runs down); the engine's own space is converted in the pet page.
import { BrowserWindow, screen, clipboard, app, shell } from 'electron'
import path from 'node:path'
import fs from 'node:fs'

const PANEL = { w: 372, h: 660, margin: 16 }            // the panel itself, and room around it for its shadow
const CARDS = { mood: [380, 250], note: [260, 300], chat: [366, 486], toast: [330, 96], story: [252, 462] }
const clamp = (v, lo, hi) => Math.min(Math.max(v, lo), Math.max(lo, hi))

export function createWindows({ preload, pageUrl, iconPath, getTheme, getTray }) {
  const wm = { pet: null, panel: null, stats: null, cards: {}, petBounds: { x: 0, y: 0, width: 270, height: 236 }, hit: { x: 0, y: 0, w: 270, h: 236 } }
  let lastPanelHide = 0

  // Only she must never be throttled (her timers keep her moving). Throttling also drives the page-visibility API, which
  // is how the other windows know to stop animating and polling while they're hidden.
  // `toolbar` is Windows' "tool window" style: no Alt+Tab entry and no taskbar button for her or her cards.
  const make = ({ throttle = true, ...opts } = {}) => new BrowserWindow({
    show: false, frame: false, transparent: true, hasShadow: false, resizable: false, thickFrame: false, skipTaskbar: true,
    fullscreenable: false, minimizable: false, maximizable: false, icon: iconPath, ...(process.platform === 'win32' ? { type: 'toolbar' } : {}),
    webPreferences: { preload, contextIsolation: true, nodeIntegration: false, sandbox: true, backgroundThrottling: throttle, spellcheck: false, autoplayPolicy: 'no-user-gesture-required' },
    ...opts,
  })
  const lock = (win) => {
    win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }))
    win.webContents.on('will-navigate', (e) => e.preventDefault())
  }
  const nearest = (r) => screen.getDisplayNearestPoint({ x: Math.round(r.x + (r.width || 0) / 2), y: Math.round(r.y + (r.height || 0) / 2) }).workArea
  const petArea = () => nearest(wm.petBounds)

  // ---------------------------------------------------------------- her

  wm.createPet = () => {
    const win = make({ throttle: false, width: 270, height: 236, focusable: false, alwaysOnTop: true, show: false })
    wm.pet = win
    lock(win)
    win.setAlwaysOnTop(true, 'floating')
    win.setIgnoreMouseEvents(true, { forward: true })      // clicks pass through everywhere except her (the page flips this)
    win.loadURL(pageUrl('pet.html'))
    win.once('ready-to-show', () => win.showInactive())
    win.on('closed', () => { wm.pet = null })
    return win
  }
  wm.setPetBounds = (b) => {
    if (!wm.pet || wm.pet.isDestroyed()) return
    wm.petBounds = { x: Math.round(b.x), y: Math.round(b.y), width: Math.round(b.w), height: Math.round(b.h) }
    if (b.hit) wm.hit = b.hit
    wm.pet.setBounds(wm.petBounds, false)        // always with a size: a bare position drifts on fractional display scales
  }
  wm.setPetClickable = (clickable) => { if (wm.pet && !wm.pet.isDestroyed()) wm.pet.setIgnoreMouseEvents(!clickable, { forward: true }) }
  wm.setPetLevel = (aboveFullscreen) => { if (wm.pet && !wm.pet.isDestroyed()) wm.pet.setAlwaysOnTop(true, aboveFullscreen ? 'screen-saver' : 'floating') }
  wm.setPetVisible = (visible) => {
    const w = wm.pet
    if (!w || w.isDestroyed()) return
    if (visible && !w.isVisible()) w.showInactive()
    else if (!visible && w.isVisible()) w.hide()
  }
  wm.sendPet = (ch, ...a) => { if (wm.pet && !wm.pet.isDestroyed()) wm.pet.webContents.send(ch, ...a) }

  // where her head is on screen, for putting cards just above it
  const headTop = () => wm.petBounds.y + wm.hit.y
  const petCenterX = () => wm.petBounds.x + wm.hit.x + wm.hit.w / 2

  // ---------------------------------------------------------------- the control panel

  wm.panelVisible = () => !!wm.panel && !wm.panel.isDestroyed() && wm.panel.isVisible()

  function ensurePanel() {
    if (wm.panel && !wm.panel.isDestroyed()) return wm.panel
    const win = make({ width: PANEL.w + PANEL.margin * 2, height: PANEL.h + PANEL.margin * 2, alwaysOnTop: true, focusable: true })
    wm.panel = win
    lock(win)
    win.setAlwaysOnTop(true, 'pop-up-menu')
    win.loadURL(pageUrl('panel.html'))
    // like a popover: clicking anywhere else puts it away
    win.on('blur', () => {
      setTimeout(() => {
        if (win.isDestroyed() || win.isFocused() || win.webContents.isDevToolsOpened()) return
        if (win.isVisible()) { win.hide(); lastPanelHide = Date.now(); wm.sendPet('panel:open', false) }
      }, 120)
    })
    win.on('closed', () => { wm.panel = null })
    // a hidden page still costs memory: let it go after a while and rebuild it on demand
    win.on('hide', () => { clearTimeout(win._reap); win._reap = setTimeout(() => { if (!win.isDestroyed() && !win.isVisible()) win.destroy() }, 90000) })
    win.on('show', () => clearTimeout(win._reap))
    return win
  }

  function placePanel(win, at) {
    const innerW = PANEL.w, innerH = PANEL.h
    let wa, x, y
    const tray = getTray()
    const tb = tray && !tray.isDestroyed() ? tray.getBounds() : null
    if (at === 'tray' && tb && tb.width > 0) {
      wa = nearest(tb)
      const cx = tb.x + tb.width / 2, cy = tb.y + tb.height / 2
      if (cy >= wa.y + wa.height) { x = cx - innerW / 2; y = wa.y + wa.height - innerH - 10 }          // taskbar at the bottom
      else if (cy < wa.y) { x = cx - innerW / 2; y = wa.y + 10 }                                         // at the top
      else if (cx < wa.x) { x = wa.x + 10; y = cy - innerH / 2 }                                          // at the left
      else { x = wa.x + wa.width - innerW - 10; y = cy - innerH / 2 }                                     // at the right
    } else if (at === 'pet') {
      wa = petArea()
      const top = headTop() - innerH - 8
      if (top >= wa.y + 8) { x = petCenterX() - innerW / 2; y = top }                                    // above her
      else {                                                                                             // no room above: beside her
        const right = wm.petBounds.x + wm.hit.x + wm.hit.w + 8
        x = right + innerW <= wa.x + wa.width - 8 ? right : wm.petBounds.x + wm.hit.x - 8 - innerW
        y = wa.y + wa.height - innerH - 8
      }
    } else {                                                                                             // no tray to anchor to: bottom right
      wa = screen.getPrimaryDisplay().workArea
      x = wa.x + wa.width - innerW - 10; y = wa.y + wa.height - innerH - 10
    }
    x = clamp(x, wa.x + 8, wa.x + wa.width - innerW - 8); y = clamp(y, wa.y + 8, wa.y + wa.height - innerH - 8)
    win.setBounds({ x: Math.round(x - PANEL.margin), y: Math.round(y - PANEL.margin), width: PANEL.w + PANEL.margin * 2, height: PANEL.h + PANEL.margin * 2 }, false)
  }

  wm.openPanel = ({ tab = 'home', at = 'tray', welcome = false } = {}) => {
    const win = ensurePanel()
    placePanel(win, at)
    const show = () => {
      win.webContents.send('panel:show', { tab, welcome })
      win.show(); win.focus(); win.moveTop()
      wm.sendPet('panel:open', true)
    }
    if (win.webContents.isLoading()) win.webContents.once('did-finish-load', show); else show()
  }
  wm.togglePanel = (opts = {}) => {
    if (wm.panelVisible()) { wm.closePanel(); return }
    if (Date.now() - lastPanelHide < 250) return        // the click that closed it by blurring shouldn't reopen it
    wm.openPanel(opts)
  }
  wm.closePanel = () => { if (wm.panel && !wm.panel.isDestroyed() && wm.panel.isVisible()) { wm.panel.hide(); lastPanelHide = Date.now(); wm.sendPet('panel:open', false) } }

  // ---------------------------------------------------------------- the stats window

  const THEME_BG = { coquette: '#fff7fa', y2k: '#fff2fa', cottagecore: '#f9fbf4', darkAcademia: '#251d1b', boba: '#fdf6ef', cyberPastel: '#f5f4ff' }
  const THEME_INK = { darkAcademia: '#f5ebd6' }
  wm.openStats = () => {
    if (wm.stats && !wm.stats.isDestroyed()) { if (wm.stats.isMinimized()) wm.stats.restore(); wm.stats.show(); wm.stats.focus(); return }
    const theme = getTheme()
    const bg = THEME_BG[theme] || '#fff7fa'
    const win = new BrowserWindow({
      width: 440, height: 860, minWidth: 380, minHeight: 520, show: false, title: 'Cariberry stats', icon: iconPath, backgroundColor: bg, autoHideMenuBar: true,
      titleBarStyle: 'hidden', titleBarOverlay: { color: bg, symbolColor: THEME_INK[theme] || '#523f63', height: 36 },
      webPreferences: { preload, contextIsolation: true, nodeIntegration: false, sandbox: true, spellcheck: false },
    })
    wm.stats = win
    lock(win)
    win.setMenuBarVisibility(false)
    win.loadURL(pageUrl('stats.html'))
    win.once('ready-to-show', () => { win.show(); win.focus() })
    win.on('closed', () => { wm.stats = null })
  }
  wm.restyleStats = (theme) => {
    const w = wm.stats
    if (!w || w.isDestroyed() || process.platform === 'darwin') return
    const bg = THEME_BG[theme] || '#fff7fa'
    try { w.setBackgroundColor(bg); w.setTitleBarOverlay({ color: bg, symbolColor: THEME_INK[theme] || '#523f63' }) } catch { /* not supported here */ }
  }

  // ---------------------------------------------------------------- the floating cards

  const cardPlace = (kind, w, h) => {
    const wa = petArea()
    let x, y
    if (kind === 'note') { x = wa.x + wa.width - w - 18; y = wa.y + 30 }
    else if (kind === 'toast') { x = wa.x + wa.width - w - 18; y = wa.y + 16 }
    else if (kind === 'chat') {
      const right = wm.petBounds.x + wm.hit.x + wm.hit.w + 6
      x = right + w > wa.x + wa.width - 8 ? wm.petBounds.x + wm.hit.x - 6 - w : right
      y = wm.petBounds.y + wm.petBounds.height - h + 20
    } else if (kind === 'story') { x = petCenterX() - w / 2; y = headTop() - h - 12 }
    else { x = petCenterX() - w / 2; y = headTop() - h + 12 }                 // mood: just above her head
    return { x: Math.round(clamp(x, wa.x + 8, wa.x + wa.width - w - 8)), y: Math.round(clamp(y, wa.y + 8, wa.y + wa.height - h - 8)), width: w, height: h }
  }

  wm.hasCard = (kind) => !!wm.cards[kind] && !wm.cards[kind].isDestroyed()
  wm.closeCard = (kind) => { if (wm.hasCard(kind)) wm.cards[kind].close() }
  wm.openCard = (kind, { replace = false, pinned = false } = {}) => {
    if (wm.hasCard(kind)) { if (!replace) return wm.cards[kind]; wm.cards[kind].close() }
    const [w, h] = CARDS[kind]
    const win = make({ ...cardPlace(kind, w, h), focusable: kind === 'chat', alwaysOnTop: true })
    wm.cards[kind] = win
    lock(win)
    win.setAlwaysOnTop(!pinned, 'floating')
    win.loadURL(pageUrl('card.html', `?kind=${kind}`))
    win.once('ready-to-show', () => (kind === 'chat' ? (win.show(), win.focus()) : win.showInactive()))
    win.on('closed', () => { if (wm.cards[kind] === win) delete wm.cards[kind]; if (kind === 'chat') wm.sendPet('chat:open', false) })
    return win
  }
  wm.closeWhatSent = (webContents) => BrowserWindow.fromWebContents(webContents)?.close()
  wm.pinNote = (pinned) => { if (wm.hasCard('note')) wm.cards.note.setAlwaysOnTop(!pinned, 'floating') }
  wm.toast = (badge) => {
    wm.toastData = badge                                  // handed to the card's page when it asks
    wm.closeCard('toast')
    const win = wm.openCard('toast')
    win.webContents.once('did-finish-load', () => win.webContents.send('toast:data', badge))
    setTimeout(() => { if (!win.isDestroyed()) win.close() }, 5400)
  }

  // ---------------------------------------------------------------- pictures: a card page, photographed

  /** Renders card.html?kind=... off screen at 3x and returns it as a nativeImage (1080 px wide). */
  wm.photograph = async (kind, data, w, h) => {
    const win = new BrowserWindow({
      width: w * 3, height: h * 3, useContentSize: true, show: false, frame: false, transparent: false, backgroundColor: '#ffffff', enableLargerThanScreen: true, skipTaskbar: true,
      webPreferences: { preload, contextIsolation: true, nodeIntegration: false, sandbox: true, zoomFactor: 3, backgroundThrottling: false },
    })
    try {
      const q = `?kind=${kind}&theme=${encodeURIComponent(getTheme())}&data=${encodeURIComponent(JSON.stringify(data))}`
      await win.loadURL(pageUrl('card.html', q))
      await win.webContents.executeJavaScript('new Promise((res) => { const t = Date.now(); (function w() { document.body.dataset.ready === "1" || Date.now() - t > 4000 ? res() : setTimeout(w, 50) })() })')
      const img = await win.webContents.capturePage({ x: 0, y: 0, width: w * 3, height: h * 3 })
      const size = img.getSize()
      return size.width === w * 3 ? img : img.resize({ width: w * 3, height: h * 3, quality: 'best' })
    } finally { win.destroy() }
  }
  // CARI_DESKTOP lets tests write somewhere other than the real Desktop
  wm.savePng = (img, name) => {
    const f = path.join(process.env.CARI_DESKTOP || app.getPath('desktop'), name)
    fs.writeFileSync(f, img.toPNG())
    return f
  }
  wm.copyImage = (img) => clipboard.writeImage(img)
  wm.showFile = (f) => { if (!process.env.CARI_DESKTOP) shell.showItemInFolder(f) }

  wm.sendAll = (ch, ...a) => { for (const w of BrowserWindow.getAllWindows()) if (!w.isDestroyed()) w.webContents.send(ch, ...a) }
  wm.destroyAll = () => { for (const w of BrowserWindow.getAllWindows()) if (!w.isDestroyed()) w.destroy() }
  return wm
}

// The few Windows calls she needs, made in-process through koffi (no PowerShell, no helper programs):
// which window is in front, which program owns it, where it is, whether a full-screen app is running,
// and pressing keys (Ctrl+W to close a tab). Every call is wrapped so that a failure just means "I can't
// see that", never a crash. Handles (HWND, HANDLE) are plain numbers (intptr_t) and every out-parameter
// is a Buffer, which keeps the foreign-function declarations as simple as they can be.
import path from 'node:path'
import fs from 'node:fs'
import { createRequire } from 'node:module'

const require = createRequire(import.meta.url)
let api = null
let loadError = null

function load() {
  if (api || loadError || process.platform !== 'win32') return api
  try {
    const koffi = require('koffi')
    const user32 = koffi.load('user32.dll')
    const kernel32 = koffi.load('kernel32.dll')
    const shell32 = koffi.load('shell32.dll')
    api = {
      GetForegroundWindow: user32.func('intptr_t __stdcall GetForegroundWindow()'),
      GetWindowTextW: user32.func('int __stdcall GetWindowTextW(intptr_t hWnd, void *lpString, int nMaxCount)'),
      GetClassNameW: user32.func('int __stdcall GetClassNameW(intptr_t hWnd, void *lpClassName, int nMaxCount)'),
      GetWindowThreadProcessId: user32.func('uint32_t __stdcall GetWindowThreadProcessId(intptr_t hWnd, void *lpdwProcessId)'),
      GetWindowRect: user32.func('int32_t __stdcall GetWindowRect(intptr_t hWnd, void *lpRect)'),
      IsIconic: user32.func('int32_t __stdcall IsIconic(intptr_t hWnd)'),
      PostMessageW: user32.func('int32_t __stdcall PostMessageW(intptr_t hWnd, uint32_t Msg, uintptr_t wParam, intptr_t lParam)'),
      keybd_event: user32.func('void __stdcall keybd_event(uint8_t bVk, uint8_t bScan, uint32_t dwFlags, uintptr_t dwExtraInfo)'),
      OpenProcess: kernel32.func('intptr_t __stdcall OpenProcess(uint32_t dwDesiredAccess, int32_t bInheritHandle, uint32_t dwProcessId)'),
      CloseHandle: kernel32.func('int32_t __stdcall CloseHandle(intptr_t hObject)'),
      QueryFullProcessImageNameW: kernel32.func('int32_t __stdcall QueryFullProcessImageNameW(intptr_t hProcess, uint32_t dwFlags, void *lpExeName, void *lpdwSize)'),
      SHQueryUserNotificationState: shell32.func('int32_t __stdcall SHQueryUserNotificationState(void *pquns)'),
    }
  } catch (e) {
    loadError = e
    console.error('[win32] could not load koffi:', e.message)
  }
  return api
}

/** Windows PowerShell by its full path, so a changed PATH can't hide it (falls back to the bare name). */
export function powershellPath() {
  const p = path.win32.join(process.env.SystemRoot || process.env.windir || 'C:\\Windows', 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe')
  try { return fs.existsSync(p) ? p : 'powershell.exe' } catch { return 'powershell.exe' }
}

export const available = () => !!load()
export const lastError = () => loadError?.message || null

const utf16 = (buf, chars) => buf.toString('utf16le', 0, Math.max(0, chars) * 2)

/** Everything about the window in front, or null if there isn't one (or Windows won't say). */
export function foreground() {
  const w = load()
  if (!w) return null
  try {
    const hwnd = w.GetForegroundWindow()
    if (!hwnd) return null
    const tb = Buffer.alloc(1024)
    const title = utf16(tb, w.GetWindowTextW(hwnd, tb, 512))
    const cb = Buffer.alloc(512)
    const cls = utf16(cb, w.GetClassNameW(hwnd, cb, 256))
    const pidBuf = Buffer.alloc(4)
    w.GetWindowThreadProcessId(hwnd, pidBuf)
    const pid = pidBuf.readUInt32LE(0)
    let exePath = ''
    if (pid) {
      const h = w.OpenProcess(0x1000, 0, pid)          // PROCESS_QUERY_LIMITED_INFORMATION
      if (h) {
        try {
          const pb = Buffer.alloc(2 * 1024)
          const sz = Buffer.alloc(4); sz.writeUInt32LE(1024, 0)
          if (w.QueryFullProcessImageNameW(h, 0, pb, sz)) exePath = utf16(pb, sz.readUInt32LE(0))
        } finally { w.CloseHandle(h) }
      }
    }
    const rb = Buffer.alloc(16)
    const hasRect = w.GetWindowRect(hwnd, rb)
    const rect = hasRect ? { left: rb.readInt32LE(0), top: rb.readInt32LE(4), right: rb.readInt32LE(8), bottom: rb.readInt32LE(12) } : null
    return { hwnd, pid, title, cls, exePath, exe: exePath ? path.win32.basename(exePath).toLowerCase() : '', rect, minimized: !!w.IsIconic(hwnd) }
  } catch (e) {
    return null
  }
}

/** Is a full-screen app (a game, a video, a presentation) in front? */
export function fullscreenAppRunning() {
  const w = load()
  if (!w) return false
  try {
    const b = Buffer.alloc(4)
    if (w.SHQueryUserNotificationState(b) !== 0) return false
    const s = b.readInt32LE(0)
    return s === 2 || s === 3 || s === 4                   // BUSY, RUNNING_D3D_FULL_SCREEN, PRESENTATION_MODE
  } catch { return false }
}

const KEYUP = 0x0002
export const VK = { CONTROL: 0x11, SHIFT: 0x10, W: 0x57, T: 0x54 }

/** Presses the keys together, then lets them go in reverse order: sendKeys([VK.CONTROL, VK.W]) is Ctrl+W. */
export function sendKeys(keys) {
  const w = load()
  if (!w) return false
  try {
    for (const k of keys) w.keybd_event(k, 0, 0, 0)
    for (const k of [...keys].reverse()) w.keybd_event(k, 0, KEYUP, 0)
    return true
  } catch { return false }
}

/** Asks a window to close, politely (the same as clicking its X). */
export function closeWindow(hwnd) {
  const w = load()
  if (!w || !hwnd) return false
  try { return !!w.PostMessageW(hwnd, 0x0010, 0, 0) } catch { return false }   // WM_CLOSE
}

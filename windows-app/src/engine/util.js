// Small helpers shared by the engine. No DOM, no Electron: it also runs under plain Node.
export const now = () => Date.now() / 1000
export const rand = (a, b) => a + Math.random() * (b - a)
export const pick = (arr) => arr[Math.floor(Math.random() * arr.length)]
export const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v))
export const clamp01 = (v) => Math.min(1, Math.max(0, v))

const pad = (n) => String(n).padStart(2, '0')
/** 'YYYY-MM-DD' in the local timezone: the key every per-day table uses. */
export const dayKey = (d = new Date()) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
export const parseDay = (k) => { const [y, m, d] = k.split('-').map(Number); return new Date(y, m - 1, d) }
export const addDays = (k, n) => { const d = parseDay(k); d.setDate(d.getDate() + n); return dayKey(d) }
export const uuid = () => (globalThis.crypto?.randomUUID?.() ?? `${Date.now()}-${Math.random().toString(16).slice(2)}`)

/** Replaces {name}-style placeholders. */
export const fill = (text, vars = {}) => Object.entries(vars).reduce((s, [k, v]) => s.split(`{${k}}`).join(v), text)

// Her life on disk: three small JSON files in the user's app-data folder. Writes are atomic
// (temp file, then rename) so a crash mid-save can never leave a half-written file, and a broken
// file is kept aside rather than overwritten.
import fs from 'node:fs'
import path from 'node:path'
import { app } from 'electron'

const dir = () => { const d = app.getPath('userData'); fs.mkdirSync(d, { recursive: true }); return d }
const file = (name) => path.join(dir(), name)

export function readJSON(name, fallback) {
  const f = file(name)
  if (!fs.existsSync(f)) return fallback
  try { return JSON.parse(fs.readFileSync(f, 'utf8')) } catch (e) {
    try { fs.copyFileSync(f, file(`${name}.broken-${new Date().toISOString().replace(/[:.]/g, '')}`)) } catch {}
    return fallback
  }
}

export function writeJSON(name, data) {
  const f = file(name), tmp = `${f}.tmp`
  try { fs.writeFileSync(tmp, JSON.stringify(data)); fs.renameSync(tmp, f) } catch (e) { console.error('save failed', name, e.message) }
}
export const dataDir = dir

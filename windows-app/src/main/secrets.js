// API keys for the optional cloud chat brains. The Mac app keeps them in the Keychain; here they are
// encrypted with Windows' own per-user protection (DPAPI, through Electron's safeStorage), so the file
// is useless on any other account or machine. A key is never written in plain text: if encryption
// isn't available, saving is refused.
import { safeStorage } from 'electron'
import fs from 'node:fs'
import path from 'node:path'
import { app } from 'electron'

const file = () => path.join(app.getPath('userData'), 'secrets.json')
const readAll = () => { try { return JSON.parse(fs.readFileSync(file(), 'utf8')) } catch { return {} } }
const ALLOWED = new Set(['openai', 'gemini'])

export const canStore = () => { try { return safeStorage.isEncryptionAvailable() } catch { return false } }

export function setSecret(provider, value) {
  if (!ALLOWED.has(provider)) return { ok: false, error: 'unknown provider' }
  const all = readAll()
  if (!value) delete all[provider]
  else {
    if (!canStore()) return { ok: false, error: 'Windows encryption isn\'t available, so I won\'t save the key' }
    all[provider] = safeStorage.encryptString(String(value).trim()).toString('base64')
  }
  try {
    const tmp = `${file()}.tmp`
    fs.writeFileSync(tmp, JSON.stringify(all), { mode: 0o600 }); fs.renameSync(tmp, file())
    return { ok: true }
  } catch (e) { return { ok: false, error: e.message } }
}

export function getSecret(provider) {
  const b = readAll()[provider]
  if (!b || !canStore()) return null
  try { return safeStorage.decryptString(Buffer.from(b, 'base64')) } catch { return null }
}
export const hasSecret = (provider) => !!readAll()[provider]

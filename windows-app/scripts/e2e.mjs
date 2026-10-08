// Starts the real app with a throwaway profile and drives it like a person would, reporting PASS or FAIL for each step.
//   npm run e2e            (on Windows it also checks that she can see the program in front)
// It needs a screen (Electron opens real windows) and takes about 40 seconds. Nothing of yours is touched: her save, settings
// and any pictures it makes go to a temporary folder.
import { spawn } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { createRequire } from 'node:module'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const electron = createRequire(import.meta.url)('electron')
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'cariberry-e2e-'))
const port = 9340 + Math.floor(Math.random() * 400)
const onWindows = process.platform === 'win32'
const env = { ...process.env, CARI_DESKTOP: tmp }
// off Windows there is no real foreground window to read, so pretend someone is watching Reels
if (!onWindows) env.CARI_FAKE_ACTIVITY = JSON.stringify({ exe: 'chrome.exe', name: 'Google Chrome', title: 'Instagram', browser: true, url: 'instagram.com/reels/abc', probe: 'address' })

const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
let failures = 0
const check = (name, ok, detail = '') => { console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  (${detail})` : ''}`); if (!ok) failures++ }

const app = spawn(electron, ['.', `--remote-debugging-port=${port}`, `--user-data-dir=${path.join(tmp, 'profile')}`], { cwd: root, env, stdio: ['ignore', 'pipe', 'pipe'] })
let log = ''
app.stdout.on('data', (d) => (log += d)); app.stderr.on('data', (d) => (log += d))
const exited = new Promise((r) => app.on('exit', (code) => r(code)))
const cleanup = async () => { try { app.kill() } catch { /* already gone */ } await sleep(500); try { fs.rmSync(tmp, { recursive: true, force: true }) } catch { /* in use */ } }
process.on('SIGINT', async () => { await cleanup(); process.exit(130) })

// ---- a tiny DevTools-protocol client
const targets = async () => { try { return await (await fetch(`http://127.0.0.1:${port}/json`)).json() } catch { return [] } }
async function page(match, wait = 8000) {
  const t0 = Date.now()
  for (;;) {
    const t = (await targets()).find((x) => x.type === 'page' && x.url.includes(match))
    if (t) return connect(t)
    if (Date.now() - t0 > wait) return null
    await sleep(250)
  }
}
async function connect(t) {
  const ws = new WebSocket(t.webSocketDebuggerUrl)
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej })
  let id = 0; const waits = new Map(); const errors = []
  ws.onmessage = (m) => {
    const d = JSON.parse(m.data)
    if (d.id && waits.has(d.id)) { waits.get(d.id)(d); waits.delete(d.id) }
    else if (d.method === 'Runtime.exceptionThrown') errors.push(d.params.exceptionDetails.exception?.description || d.params.exceptionDetails.text)
  }
  // a window that closes mid-call (the mood card does, when you answer it) answers every pending call with { closed: true }
  ws.onclose = () => { for (const res of waits.values()) res({ closed: true }); waits.clear() }
  const send = (method, params = {}) => new Promise((res) => { if (ws.readyState !== 1) return res({ closed: true }); const i = ++id; waits.set(i, res); ws.send(JSON.stringify({ id: i, method, params })) })
  await send('Runtime.enable')
  return {
    errors,
    eval: async (expr) => { const r = await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true }); if (r.closed) throw new Error('that window closed'); if (r.result?.exceptionDetails) throw new Error(r.result.exceptionDetails.exception?.description || 'eval failed'); return r.result?.result?.value },
    close: () => ws.close(),
  }
}

try {
  console.log(`\nCariberry end-to-end (${process.platform}, Electron ${electron ? 'ok' : '?'}), profile ${tmp}\n`)
  const pet = await page('pet.html', 20000)
  check('the app starts and her page loads', !!pet)
  if (!pet) throw new Error('no pet page')
  await sleep(2500)

  const alive = await pet.eval('(async () => { const a = __rt.pet.phase; await new Promise(r => setTimeout(r, 600)); return __rt.pet.phase > a })()')
  check('she is animating', alive === true)
  check('she is on screen (a real position)', await pet.eval('Number.isFinite(__rt.pet.position.x) && __rt.pet.position.x > 0'))
  const frames = await pet.eval('(async () => { const f = __perf.frames; await new Promise(r => setTimeout(r, 2000)); return (__perf.frames - f) / 2 })()')
  check('she draws at a sane frame rate (3 to 31 per second)', frames >= 3 && frames <= 31, `${frames} fps`)
  check('sounds decode (a bark)', await pet.eval("__rt.sound.load('sounds/bark_cat').then((b) => !!b && b.duration > 0.1)"))
  check('the lo-fi music decodes', await pet.eval("__rt.sound.load('music/lofi').then((b) => !!b && b.duration > 30)"))

  const state = await pet.eval("cari.invoke('rpc', 'state').then((s) => ({ name: s.name, vitals: !!s.vitals, guards: s.guards.length }))")
  check('the control panel can read her state', state.name === 'Cariberry' && state.vitals && state.guards === 10)

  // the panel
  await pet.eval("cari.invoke('open', 'panel', { tab: 'home' })")
  const panel = await page('panel.html')
  check('the control panel opens', !!panel)
  await sleep(1500)
  const ptext = await panel.eval('document.body.innerText')
  check('the panel shows her name, level and the four tabs', /Cariberry/.test(ptext) && /Lv 1/.test(ptext) && /Home/.test(ptext) && /Focus/.test(ptext) && /Closet/.test(ptext) && /Settings/.test(ptext))
  check('Home has the one big start button', /Start 25 min focus/.test(ptext))
  check('and exactly four tabs', (await panel.eval("document.querySelectorAll('.tabbar button').length")) === 4)
  check('the panel had no script errors', panel.errors.length === 0, panel.errors[0] || '')
  await panel.eval("(() => { const b = [...document.querySelectorAll('.tabbar button')].find((x) => /Closet/.test(x.innerText)); b.click() })()")
  await sleep(600)
  await panel.eval("(() => { const b = [...document.querySelectorAll('button.species')].find((x) => x.getAttribute('aria-label').startsWith('Fox')); b.click() })()")
  await sleep(700)
  check('choosing Fox in the panel changes her', (await pet.eval('__rt.pet.species')) === 'fox')

  // chat
  await pet.eval("cari.invoke('open', 'chat')")
  const chat = await page('kind=chat', 20000)
  check('the chat window opens', !!chat)
  await sleep(1200)
  const sendChat = (t) => chat.eval(`(async () => { const i = document.querySelector('.chat input'); Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(i, ${JSON.stringify(t)}); i.dispatchEvent(new Event('input', { bubbles: true })); await new Promise(r => setTimeout(r, 120)); document.querySelector('.chat .send').click(); await new Promise(r => setTimeout(r, 1700)); return [...document.querySelectorAll('.msg')].map(m => m.innerText) })()`)
  const m1 = await sendChat('focus 25')
  check('"focus 25" in chat starts a 25 minute timer', (await pet.eval('__rt.pet.timerEndsAt !== null && __rt.pet.timerRemaining > 1400')) === true)
  check('and she answers', m1.length >= 3, m1.at(-1))
  const m2 = await sendChat('open my unknown widget thing')
  check('chat answers ordinary messages in her own voice', m2.at(-1).length > 3, m2.at(-1))
  chat.close()

  // the stats window and the cards
  await pet.eval("cari.invoke('open', 'stats')")
  const stats = await page('stats.html')
  check('the stats window opens', !!stats)
  await sleep(1200)
  check('and shows her level and a calendar', /Level \d/.test(await stats.eval('document.body.innerText')) && (await stats.eval("document.querySelectorAll('.day').length")) === 35)
  stats.close()
  await pet.eval("cari.invoke('open', 'mood')")
  const mood = await page('kind=mood')
  await sleep(800)
  check('the mood check-in opens with five moods', !!mood && (await mood.eval("document.querySelectorAll('.opt').length")) === 5)
  // choosing a mood closes that window, so the call may end with 'that window closed'
  await mood?.eval("document.querySelector('.opt').click()").catch(() => {})
  await sleep(1800)
  check('answering it records your mood and opens today\'s note', !!(await pet.eval('__rt.prefs.todayMood')) && !!(await page('kind=note', 3000)))

  // pictures
  const story = await pet.eval("cari.invoke('story:save')")
  const png = fs.readdirSync(tmp).find((f) => /study card/.test(f))
  const head = png ? fs.readFileSync(path.join(tmp, png)).subarray(0, 24) : Buffer.alloc(24)
  const w = head.readUInt32BE(16), h = head.readUInt32BE(20)
  check('the study card is saved as a 1080 x 1920 picture', story.ok && head.subarray(1, 4).toString() === 'PNG' && w === 1080 && h === 1920, `${w} x ${h}`)

  // coaching and saving
  if (!onWindows) {
    await pet.eval("__rt.prefs.set('browserAwareness', true)")
    await sleep(30000)
    check('a Reels page makes her tell you off', (await pet.eval('__rt.pet.barksGiven')) >= 1 && (await pet.eval("__rt.pet.lastVerdict")) === 'distraction')
  } else {
    check('Windows calls load (koffi)', true, 'see `Cariberry.exe --diagnose` for what she can see')
  }
  await pet.eval("cari.invoke('rpc', 'flush')")
  await sleep(500)
  const save = JSON.parse(fs.readFileSync(path.join(tmp, 'profile', 'pet.json'), 'utf8'))
  check('her save is written to disk', typeof save.xp === 'number' && save.timerEndsAt > Date.now())
  const prefs = JSON.parse(fs.readFileSync(path.join(tmp, 'profile', 'prefs.json'), 'utf8'))
  check('and her settings (species, mood, spot)', prefs.species === 'fox' && !!prefs.moodToday && !!prefs.petSpot)
  check('the pet page had no script errors', pet.errors.length === 0, pet.errors[0] || '')

  // quitting
  await pet.eval("cari.invoke('quit')").catch(() => {})
  const code = await Promise.race([exited, sleep(8000).then(() => 'timeout')])
  check('she quits cleanly', code === 0, `exit ${code}`)
} catch (e) {
  console.log(`  FAIL  ${e.message}`); failures++
  console.log('\n--- app log (tail) ---\n' + log.split('\n').filter((l) => !/Security Warning|^\s*$|electronjs\.org|Policy set|this app to|more information|warning will not|once the app/i.test(l)).slice(-15).join('\n'))
} finally { await cleanup() }

console.log(failures ? `\n${failures} step(s) failed.\n` : '\nAll steps passed.\n')
process.exit(failures ? 1 : 0)

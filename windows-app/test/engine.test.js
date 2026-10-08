import test from 'node:test'
import assert from 'node:assert/strict'
import { Prefs } from '../src/engine/prefs.js'
import { RuleBook, DEFAULT_RULES, GUARD_PRESETS } from '../src/engine/rules.js'
import { Pet, NullHost } from '../src/engine/pet.js'
import { resolveXP } from '../src/engine/progression.js'
import { dayKey } from '../src/engine/util.js'
import { buildState, buildStats, catalog } from '../src/renderer/state.js'

const make = (prefs = {}) => {
  const calls = { bark: 0, whine: 0, yip: 0 }
  const host = Object.assign(new NullHost(), { onBark: () => calls.bark++, onWhine: () => calls.whine++, onYip: () => calls.yip++ })
  const p = new Prefs({ welcomed: true, ...prefs })
  const rules = new RuleBook(DEFAULT_RULES)
  const pet = new Pet(p, rules, host)
  pet.restore({})
  return { pet, prefs: p, rules, calls }
}
const watch = (pet, rules, sample, seconds, idle = 0) => { for (let t = 0; t < seconds; t += 2) pet.observe(rules.evaluate(sample), 2, idle) }

test('what you are doing is judged from the program and the browser address', () => {
  const { rules } = make()
  const kind = (s) => rules.evaluate(s).ruleName
  assert.equal(kind({ exe: 'chrome.exe', name: 'Google Chrome', title: 'Instagram', url: 'instagram.com/reels/abc' }), 'Reels & short-form video')
  assert.equal(kind({ exe: 'chrome.exe', name: 'Google Chrome', title: 'Shorts', url: 'youtube.com/shorts/xyz' }), 'Reels & short-form video')
  assert.equal(kind({ exe: 'chrome.exe', name: 'Google Chrome', title: 'Instagram', url: 'instagram.com/' }), 'Social media')
  assert.equal(kind({ exe: 'code.exe', name: 'VS Code', title: '', url: '' }), 'Coding')
  assert.equal(kind({ exe: 'winword.exe', name: 'Word', title: '', url: '' }), 'Studying & writing')
  assert.equal(kind({ exe: 'spotify.exe', name: 'Spotify', title: '', url: '' }), 'Music & media')
  assert.equal(kind({ exe: 'steam.exe', name: 'Steam', title: '', url: '' }), 'Games')
})

test('with only a tab title (no address) the common cases still work', () => {
  const { rules } = make()
  assert.equal(rules.evaluate({ exe: 'msedge.exe', name: 'Microsoft Edge', title: 'Instagram', url: '' }).ruleName, 'Social media')
  assert.equal(rules.evaluate({ exe: 'chrome.exe', name: 'Google Chrome', title: 'Funny cats - YouTube', url: '' }).ruleName, 'YouTube (might be learning, might not)')
  assert.equal(rules.evaluate({ exe: 'firefox.exe', name: 'Firefox', title: 'Reels · Instagram', url: '' }).ruleName, 'Reels & short-form video')
})

test('a document called "instagram plan" in Word is still homework: only browsers contribute a title', () => {
  const { rules } = make()
  // runtime.js passes no title for non-browser programs, exactly like the Mac app
  assert.equal(rules.evaluate({ exe: 'winword.exe', name: 'Word', title: '', url: '' }).kind, 'work')
  // a Store app is known by its window title (every one of them is ApplicationFrameHost)
  assert.equal(rules.evaluate({ exe: 'applicationframehost.exe', name: 'Netflix', title: 'Netflix', url: '' }).ruleName, 'Streaming & twitch')
})

test('guarding a site turns it into a rule, and unguarding removes it', () => {
  const { rules } = make()
  const reddit = GUARD_PRESETS.find((p) => p.id === 'reddit')
  rules.setGuard(reddit, true)
  assert.ok(rules.isGuarded(reddit))
  assert.equal(rules.evaluate({ exe: 'chrome.exe', name: 'Chrome', title: 'r/all', url: 'reddit.com/r/all' }).ruleName, 'Guard: Reddit')
  rules.setGuard(reddit, false)
  assert.ok(!rules.isGuarded(reddit))
  rules.addBlock('Etsy.com')
  assert.deepEqual(rules.customBlocks, ['etsy.com'])
  assert.equal(rules.evaluate({ exe: 'chrome.exe', name: 'Chrome', title: '', url: 'etsy.com/shop' }).kind, 'distraction')
})

test('she tells you off after a while on Reels, and not before', () => {
  const { pet, rules, calls } = make()
  const reels = { exe: 'chrome.exe', name: 'Google Chrome', title: 'Instagram', url: 'instagram.com/reels/x' }
  watch(pet, rules, reels, 10)
  assert.equal(calls.bark, 0, 'ten seconds is within the grace')
  watch(pet, rules, reels, 20)
  assert.ok(calls.bark >= 1, 'twenty seconds in, she barks')
  assert.equal(pet.barksGiven >= 1, true)
  assert.equal(pet.lastVerdict, 'distraction')
})

test('quiet hours and a break keep her quiet', () => {
  const { pet, rules, calls, prefs } = make()
  const hour = new Date().getHours()
  prefs.set('quietHoursEnabled', true); prefs.set('quietHoursStart', hour); prefs.set('quietHoursEnd', (hour + 2) % 24)
  watch(pet, rules, { exe: 'chrome.exe', name: 'Chrome', title: '', url: 'instagram.com/reels/x' }, 60)
  assert.equal(calls.bark, 0)
})

test('working earns focus time, XP, berries and a streak', () => {
  const { pet, rules } = make()
  const before = pet.xp
  watch(pet, rules, { exe: 'code.exe', name: 'VS Code', title: '', url: '' }, 300)
  assert.ok(pet.focusTodayMinutes >= 4.9 && pet.focusTodayMinutes <= 5.1, `5 minutes focused, got ${pet.focusTodayMinutes}`)
  assert.ok(pet.xp > before + 20, 'the first focus of the day is a bonus')
  assert.ok(pet.berries >= 40 + 4)
  assert.equal(pet.lastVerdict, 'work')
  assert.ok(resolveXP(pet.xp).level >= 1)
})

test('walking away stops the clock but not the day', () => {
  const { pet, rules } = make()
  watch(pet, rules, { exe: 'code.exe', name: 'VS Code', title: '', url: '' }, 60, 600)      // idle for ten minutes
  assert.equal(pet.focusTodayMinutes, 0)
  assert.match(pet.presenceNote, /resting/)
  pet.noteScreenOff()
  assert.match(pet.presenceNote, /locked/)
})

test('her save survives a round trip, a missing field, and a corrupt one', () => {
  const { pet, rules } = make()
  watch(pet, rules, { exe: 'code.exe', name: 'VS Code', title: '', url: '' }, 120)
  pet.addTask('write essay'); pet.berries += 7
  const saved = JSON.parse(JSON.stringify(pet.snapshot()))
  const { pet: again } = make()
  again.restore(saved)
  assert.equal(again.berries, pet.berries)
  assert.equal(again.tasks.length, 1)
  assert.ok(Math.abs(again.focusTodayMinutes - pet.focusTodayMinutes) < 1e-9)
  const { pet: lenient } = make()
  lenient.restore({ hunger: 'lots', xp: null, tasks: 'no', owned: undefined, dailyFocus: 5 })
  assert.equal(lenient.hunger, 0.85); assert.deepEqual(lenient.tasks, []); assert.equal(typeof lenient.dailyFocus, 'object')
})

test('the UI state and the stats survive being sent between windows', () => {
  const { pet, rules } = make()
  watch(pet, rules, { exe: 'code.exe', name: 'VS Code', title: '', url: '' }, 60)
  const rt = { lastClosed: { title: 'Reels', url: 'x', at: Date.now() }, monitorSeen: { at: Date.now(), name: 'Chrome', url: 'a.com', browser: true } }
  for (const data of [buildState(pet, rules, rt), buildStats(pet, rules), catalog]) {
    const copy = structuredClone(data)                      // what Electron's IPC does
    assert.deepEqual(JSON.parse(JSON.stringify(copy)), JSON.parse(JSON.stringify(data)))
  }
  const s = buildState(pet, rules, rt)
  assert.equal(s.monitor.undoLabel, 'Reels')
  assert.equal(s.guards.length, 10)
  assert.equal(catalog.species.length, 8)
  assert.equal(catalog.vibes.length, 4)
  assert.equal(Object.keys(buildStats(pet, rules).dailyFocus).includes(dayKey()), true)
})

test('buying, wearing and decor follow the Sanctuary\'s rules', () => {
  const { pet } = make()
  pet.berries = 100
  assert.equal(pet.buy('knitSweater'), true); assert.equal(pet.berries, 50)
  assert.equal(pet.buy('knitSweater'), true); assert.equal(pet.berries, 50, 'owning it already costs nothing')
  pet.wear('knitSweater'); assert.equal(pet.outfit.body, 'knitSweater')
  pet.wear('knitSweater'); assert.equal(pet.outfit.body, 'none', 'wearing it again takes it off')
  pet.wear('hoodie'); assert.equal(pet.outfit.body, 'none', 'you can\'t wear what you don\'t own')
  assert.equal(pet.buyDecor('plant'), false, '100 berries is exactly the price: she has 50 left')
  pet.berries = 500
  assert.equal(pet.buyDecor('sakura'), true); assert.equal(pet.buyDecor('leaves'), true)
  assert.deepEqual([...pet.decorOn].filter((d) => ['sakura', 'leaves'].includes(d)), ['leaves'], 'buying a second weather puts the first away')
  pet.toggleDecor('sakura')
  assert.deepEqual([...pet.decorOn].filter((d) => ['sakura', 'leaves'].includes(d)), ['sakura'], 'and turning one on turns the other off')
})

test('she is where you left her after a restart', () => {
  const { pet, prefs } = make()
  pet.restY = 300; pet.position = { x: 700, y: 300 }
  assert.deepEqual(pet.spot, { x: 700, y: 300 })
  pet.restY = null
  assert.equal(pet.spot.y, -1, 'the floor is saved as -1')
  // restoring: a perch comes back as a perch when free placement is on
  prefs.set('petSpot', { x: 500, y: 250 })
  class OneScreen extends NullHost { screens() { return [{ minX: 0, maxX: 1440, minY: 40, maxY: 900 }] } }
  const again = new Pet(prefs, new RuleBook(DEFAULT_RULES), new OneScreen())
  again.placeAtStart()
  assert.equal(again.position.x, 500)
  assert.equal(again.perched, true)
  assert.equal(again.position.y, 250)
})

test('muting her voice leaves the music alone', () => {
  const { pet, prefs } = make()
  pet.toggleAmbienceNow()
  assert.equal(pet.ambiencePlaying, true)
  pet.toggleMute()
  assert.equal(prefs.get('sounds'), false)
  assert.equal(pet.ambiencePlaying, true, 'the lo-fi keeps playing with her voice muted')
  pet.toggleAmbienceNow()
  assert.equal(pet.ambiencePlaying, false, 'and the play button still stops it')
  pet.toggleAmbienceNow()
  assert.equal(prefs.get('sounds'), false, 'starting music does not unmute her')
  assert.equal(pet.ambiencePlaying, true)
})

test('time in an app no rule knows still counts as focus while a focus session is running, and only then', () => {
  const { pet, rules } = make()
  const unknown = { exe: 'notepad.exe', name: 'Notepad', title: '', url: '' }
  assert.equal(rules.evaluate(unknown).kind, 'neutral')
  watch(pet, rules, unknown, 60)
  assert.equal(pet.focusTodayMinutes, 0)                       // just using the computer: not focus
  pet.startTimer(25)
  watch(pet, rules, unknown, 60)
  assert.ok(Math.abs(pet.focusTodayMinutes - 1) < 0.05, `got ${pet.focusTodayMinutes}`)
  pet.startTimer(5, true)                                      // a break is not focus
  watch(pet, rules, unknown, 60)
  assert.ok(Math.abs(pet.focusTodayMinutes - 1) < 0.05)
})

test('focus is remembered by hour of day, and idle time is counted as away', () => {
  const { pet, rules } = make()
  const code = { exe: 'code.exe', name: 'VS Code', title: '', url: '' }
  watch(pet, rules, code, 120)
  const hour = new Date().getHours()
  assert.ok(Math.abs(pet.focusByHour[hour] - 2) < 0.05)
  assert.equal(pet.dailyAway[dayKey()] || 0, 0)
  watch(pet, rules, code, 20, 1000)                            // an hour with no keys or mouse
  assert.ok(pet.dailyAway[dayKey()] >= 19)
  assert.ok(Math.abs(pet.focusTodayMinutes - 2) < 0.05)        // away time never earns focus
})

test('every app is remembered as work, distraction or neither, and survives a save', () => {
  const { pet, rules } = make()
  watch(pet, rules, { exe: 'code.exe', name: 'VS Code', title: '', url: '' }, 10)
  watch(pet, rules, { exe: 'chrome.exe', name: 'Google Chrome', title: 'Instagram', url: 'instagram.com/reels/abc' }, 10)
  watch(pet, rules, { exe: 'notepad.exe', name: 'Notepad', title: '', url: '' }, 10)
  assert.deepEqual(new Set(Object.values(pet.siteKinds)), new Set(['work', 'distraction', 'neutral']))
  const { pet: again } = make()
  again.restore(JSON.parse(JSON.stringify(pet.snapshot())))
  assert.deepEqual(again.siteKinds, pet.siteKinds)
  assert.deepEqual(again.focusByHour, pet.focusByHour)
  const st = buildStats(again, make().rules)
  assert.deepEqual(st.focusByHour, pet.focusByHour)
  assert.ok('dailyAway' in st && 'siteKinds' in st)
})

test('an old save with none of the new stats fields still loads', () => {
  const { pet } = make()
  pet.restore({ name: 'Cariberry', totalFocusMinutes: 40, dailyFocus: { [dayKey()]: 40 } })
  assert.deepEqual(pet.dailyAway, {}); assert.deepEqual(pet.focusByHour, {}); assert.deepEqual(pet.siteKinds, {})
  assert.equal(pet.focusTodayMinutes, 40)
})

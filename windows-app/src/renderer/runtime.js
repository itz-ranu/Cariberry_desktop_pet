// The engine's home: loads her save, builds the Pet with a host that knows this machine, takes in
// what you're doing, and answers every request the panel, the stats window and the cards make.
// No drawing here, so it also runs in a plain browser page (dev/harness.html) for checking the UI.
import { Prefs } from '../engine/prefs.js'
import { RuleBook, DEFAULT_RULES, GUARD_PRESETS } from '../engine/rules.js'
import { Pet, NullHost } from '../engine/pet.js'
import { Stage } from '../engine/stage.js'
import { dayKey } from '../engine/util.js'
import * as Dlg from '../engine/dialogue.js'
import { speciesInfo } from '../shared/data.js'
import { localReply, localCommand } from '../engine/chat.js'
import { note as fortuneNote, MOODS } from '../engine/fortune.js'
import { Sound } from './audio.js'
import { buildState, buildStats, catalog } from './state.js'
import { BeatListener } from './beat.js'

const SAMPLE = 2
const UNDO_WINDOW = 45

export async function boot({ cari }) {
  const loaded = await cari.invoke('load')
  let screensInfo = await cari.invoke('screens')
  let savePending = false

  const flush = () => {
    prefs.data.petSpot = pet.spot                  // quietly: this is saved with everything else, not a change worth saving on its own
    cari.send('save', { save: pet.snapshot(), prefs: prefs.data, rules: rules.rules })
  }
  const persist = () => {
    if (savePending) return
    savePending = true
    setTimeout(() => { savePending = false; flush() }, 800)
  }

  const prefs = new Prefs(loaded.prefs, (k) => { if (k === 'theme') cari.send('theme', prefs.get('theme')); persist() })
  const rules = new RuleBook(loaded.rules || DEFAULT_RULES, persist)
  const sound = new Sound(() => prefs.get('sounds'))
  const rt = { cari, prefs, rules, sound, lastActivity: null, lastClosed: null, started: Date.now() }

  // y-up screen space (the engine's, AppKit style) from Electron's y-down DIPs
  const toYUp = (r) => ({ minX: r.x, maxX: r.x + r.width, minY: screensInfo.primaryH - (r.y + r.height), maxY: screensInfo.primaryH - r.y })
  const host = Object.assign(new NullHost(), {
    screens: () => screensInfo.displays.map((d) => toYUp(d.work)),
    windowSpot() {
      // she leaps onto the top edge of whatever you're in: a browser window, tab bar underneath her paws
      const b = rt.lastActivity?.bounds
      if (!b || b.w < 320) return null
      return { x: b.x + Math.min(190, b.w * 0.3), y: screensInfo.primaryH - b.y - 14 }
    },
    reduceMotion: () => globalThis.matchMedia?.('(prefers-reduced-motion: reduce)').matches ?? false,
    musicBeat: () => sound.musicBeat(),
    setAmbience: (kind, playing, volume) => sound.ambience(kind, playing, volume),
    sizeChanged: () => rt.onSizeChanged?.(),
    save: persist,
    onBark: () => sound.bark(pet.species, 2 + Math.floor(Math.random() * 2)),
    onYip: () => sound.yip(pet.species),
    onBell: () => sound.bell(),
    onMunch: () => sound.munch(pet.species),
    onWhine: () => sound.whine(pet.species),
    onClick: () => sound.click(),
    onTapSound: () => sound.click(),
    onCloseReelsTab: async () => {
      const closed = await cari.invoke('tab:close')
      if (!closed?.ok) return
      rt.lastClosed = { url: closed.url || '', title: closed.title || '', exe: closed.exe || '', at: Date.now() }
      pet.say(Dlg.line('closedTab', pet.species, {}, pet.name), 'proud', 3)
      pet.emit('sparkle', 6, Stage.aura, 40)
    },
    onBadge: (b) => cari.invoke('open', 'toast', { emoji: b.emoji, title: b.title, detail: b.detail }),
  })

  const pet = new Pet(prefs, rules, host)
  pet.restore(loaded.save)
  pet.placeAtStart()
  pet.refreshAmbience()
  rt.pet = pet; rt.host = host; rt.flush = flush; rt.persist = persist
  rt.state = () => buildState(pet, rules, rt)
  rt.setScreens = (s) => { screensInfo = s; pet.position.x = Math.min(Math.max(pet.position.x, pet.minX), pet.maxX); pet.position.y = pet.floorY }
  rt.screens = () => screensInfo

  // ---------------------------------------------------------------- what you're doing

  let lastSample = null, screenOff = false
  cari.on('presence', (p) => { screenOff = !!p.screenOff })
  cari.on('activity', (a) => {
    const t = Date.now() / 1000
    // the real time since the last look: after a sleep or a stall the gap isn't time she watched
    const gap = lastSample === null ? 0 : t - lastSample
    lastSample = t
    const dt = gap > 0 && gap <= SAMPLE * 3 ? gap : 0
    rt.lastActivity = a
    if (a.none) return
    rt.monitorSeen = { at: Date.now(), exe: a.exe, name: a.name, title: a.title, url: a.url || '', browser: !!a.browser, probe: a.probe || '' }
    if (!prefs.get('focusCoaching')) return
    if (screenOff) { pet.noteScreenOff(); return }
    if (a.self) return                        // ourselves in front (the panel, her chat): not her business
    // like the Mac: only a browser contributes a tab title and address; other apps are known by name
    let title = '', url = ''
    if (a.browser && prefs.get('browserAwareness')) { title = a.title || ''; url = a.url || '' }
    else if (a.uwp) title = a.title || ''     // Store apps all run inside ApplicationFrameHost: the title is their name
    pet.observe(rules.evaluate({ exe: a.exe, name: a.name, title, url }), dt, a.idle || 0)
  })
  setInterval(() => {
    const away = (rt.lastActivity?.idle || 0) > 240 || screenOff
    if (away !== pet._away) { pet._away = away; pet.humanIsAway(away) }
  }, 1000)

  // ---------------------------------------------------------------- bop to the music (opt-in)

  rt.beats = new BeatListener({
    cari,
    onBeat: (strength) => { if (performance.now() - sound.lastVoiceAt > 700) pet.beat(strength) },
    onFailure: (why) => { prefs.set('musicBop', false); pet.say(why, 'worried', 7) },
  })
  if (prefs.get('musicBop')) rt.beats.start()

  // ---------------------------------------------------------------- requests from the panel and cards

  const DO = new Set(['feed', 'play', 'dance', 'toggleStay', 'petMe', 'comeHere', 'nap', 'wave', 'goHome', 'chooseSpecies', 'chooseCoat', 'chooseSize',
    'wear', 'clearOutfit', 'buy', 'buyDecor', 'toggleDecor', 'setMood', 'addTask', 'toggleTask', 'removeTask', 'clearDoneTasks', 'toggleHabit',
    'startTimer', 'stopTimer', 'chooseAmbience', 'toggleAmbienceNow', 'toggleMute', 'say'])
  const quote = (s) => String(s ?? '')
  const handlers = {
    state: () => rt.state(),
    catalog: () => catalog,
    stats: () => buildStats(pet, rules),

    do: (method, ...args) => {
      if (!DO.has(method) || typeof pet[method] !== 'function') return null
      if (method === 'feed') pet.feed(!!args[0])
      else if (method === 'petMe') { pet.petMe(); pet.petMe() }
      else pet[method](...args)
      pet.lastInteraction = Date.now() / 1000
      return rt.state()
    },
    /** "Come" closes the panel first, so she waits until the cursor has moved off the button. */
    come: () => { setTimeout(() => { pet.cursor = rt.cursorUp || pet.cursor; pet.comeHere() }, 450); return true },
    rename: (raw) => {
      const n = quote(raw).trim()
      if (n && n !== pet.name) { pet.rename(n); prefs.set('petName', n); pet.say(`I'm ${n}! ${speciesInfo(pet.species).emoji}`, 'excited', 3); flush() }
      return rt.state()
    },
    startFocus: (m) => { pet.startFocus(Math.min(Math.max(1, Number(m) || 25), 240), pet.intention); return rt.state() },
    setIntention: (t) => { pet.intention = quote(t).slice(0, 80); return true },
    setGoal: (m) => { prefs.set('dailyGoal', Number(m)); pet.dailyGoal = Number(m); return rt.state() },
    pref: (key, value) => { applyPref(key, value); return rt.state() },
    guard: (id, on) => {
      const preset = GUARD_PRESETS.find((p) => p.id === id)
      if (!preset) return null
      rules.setGuard(preset, on)
      pet.say(on ? `${preset.name} is on my watch list 👀` : `okay, ${preset.name} is free to roam 🕊️`, on ? 'alert' : 'neutral', 2.6)
      return rt.state()
    },
    block: (term) => {
      const t = quote(term).trim()
      if (!t) return rt.state()
      rules.addBlock(t)
      pet.say(`${t} is BANNED now 😤 don't test me`, 'angry', 4)
      host.onBark()
      return rt.state()
    },
    unblock: (term) => { rules.removeBlock(term); return rt.state() },
    resetRules: () => { rules.reset(); pet.say('back to my default instincts 🐾', 'neutral', 3); return rt.state() },
    /** After editing rules.json by hand: read it back from disk. */
    reloadRules: async () => {
      const l = await cari.invoke('load')
      if (Array.isArray(l.rules) && l.rules.length) rules.rules = l.rules
      pet.say('new rules learned! 🐾', 'excited', 3); host.onYip()
      return rt.state()
    },
    wake: () => { pet.humanIsAway(false); pet.lastInteraction = Date.now() / 1000; return rt.state() },
    undoClose: () => {
      const c = rt.lastClosed
      if (!c || Date.now() - c.at > UNDO_WINDOW * 1000) return null
      rt.lastClosed = null
      cari.invoke('tab:reopen', { url: c.url, exe: c.exe })
      pet.say('brought it back 🐾', 'shy', 2.5)
      return rt.state()
    },
    toggleMute: () => { pet.toggleMute(); return rt.state() },
    flush: () => { flush(); return true },
    sound: (name) => { sound[name]?.(pet.species) },

    // the daily check-in and the sticky note
    moodChosen: (m) => { pet.setMood(m); return rt.state() },
    noteData: () => {
      const mood = pet.prefs.todayMood || 'cozy'
      const n = fortuneNote(mood, dayKey())
      return { mood, moodInfo: MOODS[mood], text: n.text, extras: n.extras, pinned: prefs.get('notePinned') }
    },
    noteShown: () => { prefs.set('noteDay', dayKey()); return true },
    setNotePinned: (v) => { prefs.set('notePinned', !!v); return true },
    storyData: () => storyData(),

    // chat
    chatContext: () => chatContext(),
    chatCommand: (text) => localCommand(String(text), pet),
    localReply: (text) => localReply(String(text), pet),
    chatDone: (text, mood) => { pet.say(String(text).slice(0, 120), mood || null, 4); return true },
    startFocusFromChat: (m) => { pet.startFocus(Math.min(Math.max(1, Number(m) || 25), 240), pet.intention); return true },
    chooseAmbienceFromChat: (kind) => { pet.chooseAmbience(kind); return true },
  }
  rt.handlers = handlers

  function applyPref(key, value) {
    prefs.set(key, value)
    switch (key) {
      case 'aboveFullscreen': cari.send('pet:level', value); break
      case 'launchAtLogin': prefs.set('launchAtLoginPreferenceSet', true); cari.send('login:set', value); break
      case 'sounds': if (value) sound.yip(pet.species); break
      case 'ambienceVolume': pet.refreshAmbience(); break
      case 'roams':
        if (value) pet.say('time to explore again! 🐾', 'happy', 3)
        else { pet.stayPut(); pet.say('okay, staying right here 🐾', 'neutral', 3) }
        break
      case 'placeAnywhere': if (!value) pet.goHome(); break
      case 'browserAwareness':
        pet.say(value ? 'sniffing your tabs now 👃' : 'ok, tabs are private 🙈', value ? 'alert' : 'neutral', value ? 4 : 3)
        cari.send('monitor:config', { browserAwareness: !!value })
        break
      case 'autoCloseReels':
        pet.say(value ? 'one warning, then I\'ll jump up and close the tab myself 😤🐾' : Dlg.flavor('ok, I\'ll just bark from now on 🐾', pet.species),
          value ? 'alert' : 'neutral', value ? 5 : 3)
        break
      case 'quietHoursEnabled': case 'quietHoursStart': case 'quietHoursEnd':
        if (key === 'quietHoursEnabled') {
          const clock = (h) => { const x = h % 24, x12 = x % 12 === 0 ? 12 : x % 12; return `${x12}${x < 12 ? 'am' : 'pm'}` }
          pet.say(value ? `quiet hours on 🌙 I'll stay soft ${clock(prefs.get('quietHoursStart'))}–${clock(prefs.get('quietHoursEnd'))}` : 'quiet hours off, back to full volume 🐾', 'neutral', 4)
        }
        break
      case 'musicBop':
        pet.say(value ? 'ooh, I\'ll bop along 🎧' : 'okay, no more head bopping 🤫', 'happy', 3.5)
        if (value) rt.beats.start(); else rt.beats.stop()
        break
      case 'vibe': pet.say(`${Dlg.VIBES[value]?.emoji || ''} ${Dlg.VIBES[value]?.title || value} it is`, 'happy', 2.4); break
      case 'focusCoaching': if (!value) cari.send('monitor:config', { focusCoaching: false }); break
      case 'dailyGoal': pet.dailyGoal = value; break
      default: break
    }
  }

  // ---------------------------------------------------------------- the study card and chat context

  function storyData() {
    const st = rt.state()
    const earned = prefs.badgeSet
    return {
      name: pet.name, species: pet.species, coat: pet.coatIndex, outfit: pet.outfit, focusMinutes: pet.focusTodayMinutes, goalMinutes: pet.dailyGoal,
      streak: pet.streakDays, sessions: pet.sessionsToday, level: pet.level, title: pet.levelTitle,
      doneTasks: pet.tasks.filter((t) => t.done).map((t) => t.title), habitsDone: pet.habitsDone.size, habitsTotal: st.habits.length,
      badges: st.badges.filter((b) => earned.has(b.id)).map((b) => b.emoji), badgeTotal: st.badges.length,
      date: new Date().toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long' }).toLowerCase(),
      theme: prefs.get('theme'),
    }
  }

  function chatContext() {
    return {
      provider: prefs.get('chatProvider'), model: prefs.get('chatModel'),
      name: pet.name, species: pet.species, coat: pet.coatIndex, outfit: { ...pet.outfit }, emotion: pet.emotion,
      persona: {
        name: pet.name, species: speciesInfo(pet.species).name, voice: Dlg.persona(pet.species),
        vibe: Dlg.VIBES[Dlg.effectiveVibe(prefs)]?.title || '', mood: MOODS[pet.prefs.todayMood]?.title || '', level: pet.level,
      },
      greeting: Dlg.line('greetDay', pet.species, {}, pet.name) + '\nask me anything, or say “focus 25” to start a session 🐾',
      theme: prefs.get('theme'),
    }
  }

  // ---------------------------------------------------------------- once a day: how are we feeling?

  function askMoodIfNeeded() {
    if (prefs.inQuietHours || pet.act === 'sleep' || rt.chatOpen) return
    if (pet.needsCheckIn) cari.invoke('open', 'mood')
    else if (prefs.get('noteDay') !== dayKey()) cari.invoke('open', 'note')
  }
  rt.start = () => {
    // the first time she's ever opened: introduce her and let you choose who she is; otherwise a soft
    // "how are we feeling?", or today's note, once a day
    if (!prefs.get('welcomed')) {
      prefs.set('welcomed', true)
      setTimeout(() => cari.invoke('open', 'panel', 'welcome'), 1800)
    } else setTimeout(askMoodIfNeeded, 6000)
    setInterval(askMoodIfNeeded, 600000)
    cari.on('chat:open', (open) => { rt.chatOpen = !!open })
    window.addEventListener('beforeunload', flush)
    setInterval(flush, 30000)
  }
  rt.askMoodIfNeeded = askMoodIfNeeded
  return rt
}

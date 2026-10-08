// Settings and small remembered facts: the equivalent of UserDefaults. One plain object, saved
// by whoever owns the engine (`onChange`), so it works the same under Electron and under Node.
import { dayKey } from './util.js'

const DEFAULTS = {
  focusCoaching: true, browserAwareness: true, autoCloseReels: false, sounds: true, aboveFullscreen: false,
  roams: true, petName: 'Cariberry', species: 'panda', coats: {}, stay: false, placeAnywhere: true, petSpot: null,
  dailyGoal: 60, goalDay: '', reminders: true, ambience: 'lofi', ambienceVolume: 0.5,
  badges: [], badgesSeeded: false, earlyBird: false, nightOwl: false, musicMinutes: 0,
  vibe: 'own', moodDay: '', moodToday: '', noteDay: '', notePinned: false, dailyCheckIn: true,
  decorOn: [], chatProvider: 'local', chatModel: '', theme: 'coquette', welcomed: false,
  outfit: { hair: 'bow' }, sizeLevel: 1, launchAtLogin: false, launchAtLoginPreferenceSet: false,
  quietHoursEnabled: false, quietHoursStart: 22, quietHoursEnd: 8,
  habits: {}, perfectHabitDays: 0, weekendReport: true,
}

export class Prefs {
  constructor(initial = {}, onChange = () => {}) {
    this.data = { ...structuredClone(DEFAULTS), ...initial }
    this.onChange = onChange
  }
  get(k) { return this.data[k] }
  set(k, v) { this.data[k] = v; this.onChange(k, v) }
  toggle(k) { this.set(k, !this.data[k]); return this.data[k] }

  /** A new pet is a Cocoa panda: the panda's second colourway. */
  coat(species) { return this.data.coats[species] ?? (species === 'panda' ? 1 : 0) }
  setCoat(species, i) { this.set('coats', { ...this.data.coats, [species]: i }) }

  /** Today's mood from the daily check-in (null on a new day until you answer). */
  get todayMood() { return this.data.moodDay === dayKey() ? (this.data.moodToday || null) : null }
  setTodayMood(m) { this.data.moodDay = dayKey(); this.data.moodToday = m; this.onChange('moodToday', m) }

  /** Handles overnight windows (22 to 8) as well as same-day ones. */
  get inQuietHours() {
    if (!this.data.quietHoursEnabled) return false
    const h = new Date().getHours()
    const s = this.data.quietHoursStart, e = this.data.quietHoursEnd
    if (s === e) return false
    return s < e ? h >= s && h < e : h >= s || h < e
  }
  get badgeSet() { return new Set(this.data.badges) }
}

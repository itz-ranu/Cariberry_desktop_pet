// Everything the control panel, the stats window and the cards need to know, as plain data, so they
// can live in their own windows and never touch the engine directly.
import { SPECIES, speciesInfo, coatsOf, accSlot, accTitle, accEmoji, accPrice, ACCESSORIES, DECORS, decorTitle, decorEmoji, decorPrice, decorIsAmbient,
  SLOTS, SLOT_TITLES, accessoriesFor, themeInfo, THEME_IDS, emotionLabel, emotionEmoji } from '../shared/data.js'
import { collarColor } from '../shared/critter.js'
import { BADGES, badgeProgress, badgeProgressText, nextUp, HABITS, HABIT_XP, HABIT_BERRIES, HABIT_BONUS } from '../engine/badges.js'
import { GUARD_PRESETS } from '../engine/rules.js'
import { nextUnlock, collarName, resolveXP } from '../engine/progression.js'
import { VIBES, effectiveVibe } from '../engine/dialogue.js'
import { MOODS } from '../engine/fortune.js'
import { SIZE_NAMES } from '../engine/stage.js'
import { Ambience } from './ambience.js'

const UNDO_WINDOW = 45
const rgbOf = (c) => [c.r, c.g, c.b]

export function buildState(pet, rules, rt) {
  const earned = pet.prefs.badgeSet
  const nb = nextUp(pet)
  const done = pet.habitsDone
  const xp = resolveXP(pet.xp)
  const closed = rt?.lastClosed
  const undoLabel = closed && Date.now() - closed.at < UNDO_WINDOW * 1000 ? (closed.title || closed.url || 'a tab') : null
  const seen = rt?.monitorSeen || null
  const tier = pet.collarTier
  return {
    name: pet.name, species: pet.species, speciesName: speciesInfo(pet.species).name, coatIndex: pet.coatIndex, coats: { ...pet.prefs.data.coats },
    level: pet.level, levelTitle: pet.levelTitle, levelProgress: pet.levelProgress, xpInto: xp.into, xpNeeded: xp.needed,
    nextUnlock: nextUnlock(pet.level), collarTier: tier, collarName: tier > 0 ? collarName(tier) : '', collarColor: tier > 0 ? rgbOf(collarColor(tier)) : null,
    berries: pet.berries, streakDays: pet.streakDays, bestStreak: pet.bestStreakDays, ageDays: pet.ageDays, born: pet.born,
    emotion: pet.emotion, emotionLabel: emotionLabel(pet.emotion), emotionEmoji: emotionEmoji(pet.emotion),
    vitals: { hunger: pet.hunger, happiness: pet.happiness, energy: pet.energy, affection: pet.affection },
    act: pet.act, staying: pet.staying, perched: pet.perched, sizeLevel: pet.sizeLevel, sizeNames: SIZE_NAMES,
    focus: { today: pet.focusTodayMinutes, goal: pet.dailyGoal, progress: pet.goalProgress, sessions: pet.sessionsToday, seconds: pet.focusSeconds, inFlow: pet.inFlow, total: pet.totalFocusMinutes },
    activity: { label: pet.currentActivity, verdict: pet.lastVerdict, note: pet.presenceNote },
    timer: { remaining: pet.timerRemaining, total: pet.timerTotal, isBreak: pet.onBreak, running: pet.timerEndsAt !== null, intention: pet.intention },
    music: { ambience: pet.ambience, playing: pet.ambiencePlaying, volume: pet.prefs.get('ambienceVolume'), sounds: pet.prefs.get('sounds') },
    tasks: pet.tasks,
    habits: HABITS.map((h) => ({ id: h.id, emoji: h.emoji, title: h.title, auto: !!h.auto, done: done.has(h.id) })),
    habitRewards: { xp: HABIT_XP, berries: HABIT_BERRIES, bonus: HABIT_BONUS },
    badges: BADGES.map((b) => ({ id: b.id, emoji: b.emoji, title: b.title, detail: b.detail, earned: earned.has(b.id) })),
    nextBadge: nb ? { id: nb.id, emoji: nb.emoji, title: nb.title, detail: nb.detail, progress: badgeProgress(nb, pet), progressText: badgeProgressText(nb, pet) } : null,
    owned: [...pet.owned], decorOn: [...pet.decorOn], outfit: { ...pet.outfit },
    mood: pet.prefs.todayMood,
    vibe: pet.prefs.get('vibe'), effectiveVibe: effectiveVibe(pet.prefs),
    prefs: { ...pet.prefs.data, badges: undefined, habits: undefined, coats: undefined, petSpot: undefined },
    guards: GUARD_PRESETS.map((g) => ({ id: g.id, emoji: g.emoji, name: g.name, on: rules.isGuarded(g) })),
    blocks: rules.customBlocks,
    monitor: { seen, undoLabel },
  }
}

/** The stats window's data: every day on record, so any day of the calendar can be opened. */
export function buildStats(pet, rules) {
  const kinds = Object.fromEntries(rules.rules.map((r) => [r.name, r.mode]))
  const earned = pet.prefs.badgeSet
  const tier = pet.collarTier
  return {
    name: pet.name, species: pet.species, coatIndex: pet.coatIndex, outfit: { ...pet.outfit }, born: pet.born, ageDays: pet.ageDays,
    level: pet.level, levelTitle: pet.levelTitle, levelProgress: pet.levelProgress, xpInto: resolveXP(pet.xp).into, xpNeeded: resolveXP(pet.xp).needed,
    nextUnlock: nextUnlock(pet.level), collarTier: tier, collarName: tier > 0 ? collarName(tier) : '', collarColor: tier > 0 ? rgbOf(collarColor(tier)) : null,
    dailyGoal: pet.dailyGoal, streakDays: pet.streakDays, bestStreak: pet.bestStreakDays,
    dailyFocus: pet.dailyFocus, dailyDistraction: pet.dailyDistraction, dailySessions: pet.dailySessions, dailyTasks: pet.dailyTasks, dailyBarks: pet.dailyBarks,
    dailyAppTime: pet.dailyAppTime, moods: pet.moods, categoryTime: pet.categoryTime, ruleKinds: kinds,
    dailyAway: pet.dailyAway, focusByHour: pet.focusByHour, siteKinds: pet.siteKinds,
    totals: { focusMinutes: pet.totalFocusMinutes, mostFocusInADay: pet.mostFocusInADay, sessions: pet.totalSessions, tasks: pet.totalTasksDone, treats: pet.treatsEaten, barks: pet.barksGiven },
    badges: BADGES.map((b) => ({ id: b.id, emoji: b.emoji, title: b.title, detail: b.detail, earned: earned.has(b.id) })),
    moodTable: MOODS, theme: pet.prefs.get('theme'),
  }
}

const coatSwatch = (c) => ({ name: c.name, light: rgbOf(c.light), mid: rgbOf(c.mid), shade: rgbOf(c.shade) })

export const catalog = {
  species: SPECIES.map((s) => ({ id: s, name: speciesInfo(s).name, blurb: speciesInfo(s).blurb, emoji: speciesInfo(s).emoji, coats: coatsOf(s).map(coatSwatch) })),
  slots: SLOTS.map((s) => ({ id: s, title: SLOT_TITLES[s], items: accessoriesFor(s).map((a) => ({ id: a, title: accTitle(a), emoji: accEmoji(a), price: accPrice(a), slot: s })) })),
  forSale: ACCESSORIES.filter((a) => accPrice(a) > 0).map((a) => ({ id: a, title: accTitle(a), emoji: accEmoji(a), price: accPrice(a), slot: accSlot(a) })),
  decor: DECORS.map((d) => ({ id: d, title: decorTitle(d), emoji: decorEmoji(d), price: decorPrice(d), ambient: decorIsAmbient(d) })),
  themes: THEME_IDS.map((t) => ({ id: t, title: themeInfo(t).title, emoji: themeInfo(t).emoji, hot: themeInfo(t).hot.map((c) => c.slice()) })),
  vibes: Object.entries(VIBES).map(([id, v]) => ({ id, ...v })),
  moods: Object.entries(MOODS).map(([id, m]) => ({ id, ...m })),
  ambience: Ambience,
  guardPresets: GUARD_PRESETS.map((g) => ({ id: g.id, emoji: g.emoji, name: g.name })),
}

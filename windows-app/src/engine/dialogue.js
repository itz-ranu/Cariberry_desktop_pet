// Everything she says. Each animal has her own voice for every situation (voices.json, generated
// from the Mac app's Voices.swift): a kitten is a sassy diva, a puppy a hype best friend.
import voices from '../shared/voices.json' with { type: 'json' }
import vibeLines from '../shared/vibes.json' with { type: 'json' }
import { pick, fill } from './util.js'
import { speciesInfo } from '../shared/data.js'

const lastPick = {}

export const pool = (kind, species) => voices[species]?.[kind] ?? voices.cat[kind] ?? []

export function line(kind, species, vars = {}, name = '') {
  const all = pool(kind, species)
  if (!all.length) return ''
  let p = pick(all)
  if (all.length > 1 && p === lastPick[kind]) p = pick(all.filter((x) => x !== p))
  lastPick[kind] = p
  return fill(fill(p, { name }), vars)
}

export function persona(s) {
  return {
    cat: 'a sassy, dramatic kitten diva who acts aloof but secretly adores the user',
    dog: 'an over-the-moon enthusiastic puppy who LOVES the user and uses CAPS for excitement',
    bunny: 'a sweet, soft-spoken bunny who is gentle, bouncy and encouraging',
    fox: 'a sly, witty fox who loves clever plans, playful teasing and plot twists',
    panda: 'a sleepy, snack-loving panda who is calm, slow and endlessly comforting',
    hamster: 'a tiny, hyper, slightly anxious hamster who squeaks, loves seeds and runs on a wheel',
    axolotl: 'a wholesome, always-smiling axolotl who gives gentle affirmations and says glub',
    capybara: 'an unbothered, chill capybara who is relaxed, welcoming and says everything will be fine',
  }[s]
}

export function greeting(species, name) {
  const h = new Date().getHours()
  if (h >= 23 || h <= 4) return line('greetNight', species, {}, name)
  if (h <= 11) return line('greetMorning', species, {}, name)
  return line('greetDay', species, {}, name)
}

const BUILT_IN = new Set(['Reels & short-form video', 'Social media', 'Streaming & twitch', 'Music & media',
  'YouTube (might be learning, might not)', 'Games', 'Coding', 'Studying & writing'])

export function topicForRule(rule) {
  if (rule.startsWith('Blocked: ')) return rule.slice('Blocked: '.length)
  if (rule.startsWith('Guard: ')) return rule.slice('Guard: '.length)
  if (rule.includes('Reels')) return 'reels'
  if (rule.includes('Social')) return 'the feed'
  if (rule.includes('Streaming')) return 'this show'
  if (rule.includes('YouTube')) return 'YouTube'
  if (rule.includes('Games')) return 'the game'
  return 'that'
}

// ----------------------------------------------------------------- coaching vibes

export const VIBES = {
  own: { title: 'Her own voice', emoji: '🐾', blurb: 'Each animal scolds in her own personality.', patience: 1, gap: 1,
    example: '(depends on who she is: a kitten hisses, a capybara says “excuse me”)' },
  gentle: { title: 'Gentle Cozy', emoji: '🌸', blurb: 'Soft nudges. Longer to react, kinder words.', patience: 1.6, gap: 1.5,
    example: '“Bestie… maybe a quick break from reels? Let\'s finish that study goal 🥺🌸”' },
  sassy: { title: 'Sassy Bestie', emoji: '💅', blurb: 'Loving, witty roasting from your bestie.', patience: 1, gap: 1,
    example: '“Not another 30 minutes on Pinterest 💅 your essay isn\'t gonna write itself!”' },
  drill: { title: 'Drill Sergeant', emoji: '🫡', blurb: 'Loud, fast and relentless. No excuses.', patience: 0.55, gap: 0.6,
    example: '“BARK! 🐶 reels again?! Eyes UP! No treats until focus time is done!”' },
}

/** The vibe she's coaching in right now. On a day you said you were stressed or tired she goes gentle. */
export function effectiveVibe(prefs) {
  const v = prefs.get('vibe')
  const m = prefs.todayMood
  if (v !== 'gentle' && (m === 'stressed' || m === 'tired')) return 'gentle'
  return v
}

const NOISE = {
  dog: ['BARK', 'woof'], cat: ['HISS', 'mrow'], bunny: ['THUMP', 'thump'], fox: ['YIP', 'yip'], panda: ['GRR', 'grr'],
  hamster: ['SQUEAK', 'squeak'], axolotl: ['GLUB', 'glub'], capybara: ['EXCUSE ME', 'ahem'],
}
const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1).toLowerCase()

/** Rewrites a line written in a dog's voice ("BARK! woof 🐶") into hers. */
export function flavor(text, species) {
  if (species === 'dog') return text
  const [loud, soft] = NOISE[species]
  const e = speciesInfo(species).emoji
  return text.split('BARK').join(loud).split('Bark').join(cap(loud)).split('bark').join(soft)
    .split('WOOF').join(loud).split('Woof').join(cap(soft)).split('woof').join(soft)
    .split('🐶').join(e).split('🐕').join(e)
}

export function coach(kind, species, prefs, vars = {}) {
  const vibe = effectiveVibe(prefs)
  const lines = vibeLines[vibe]?.[kind]
  if (!lines?.length) return line(kind, species, vars)
  return flavor(fill(pick(lines), vars), species)
}

export function scold(rule, storedLines, species, count, prefs) {
  if (count >= 3) return coach('scoldHard', species, prefs, { x: topicForRule(rule) })
  if (!BUILT_IN.has(rule) && storedLines.length) {
    return flavor(storedLines[Math.min(storedLines.length - 1, (count - 1) % storedLines.length)], species)
  }
  return coach('scold', species, prefs, { x: topicForRule(rule) })
}

export function praise(rule, storedLines, species, prefs) {
  if (!BUILT_IN.has(rule) && storedLines.length) return flavor(pick(storedLines), species)
  return coach('praise', species, prefs)
}

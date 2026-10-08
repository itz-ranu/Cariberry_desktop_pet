// How you're feeling today, and the little note stuck to your desktop after you check in.
export const MOODS = {
  radiant: { title: 'Radiant', emoji: '✨' },
  cozy: { title: 'Cozy', emoji: '☕' },
  stressed: { title: 'Stressed', emoji: '💭' },
  tired: { title: 'Tired', emoji: '☁️' },
  excited: { title: 'Excited', emoji: '🎉' },
}
export const MOOD_IDS = Object.keys(MOODS)
export const needsGentleness = (m) => m === 'stressed' || m === 'tired'

import { pick } from './util.js'
import { speciesInfo } from '../shared/data.js'

/** What she says right after you pick it. */
export function moodReply(mood, species) {
  const name = speciesInfo(species).name.toLowerCase()
  const r = {
    radiant: ['you\'re GLOWING today ✨ let\'s make it count', 'radiant?! okay main character 💗', 'love that energy, bestie ✨'],
    cozy: ['cozy it is ☕ soft day, soft goals', `*curls up next to you* perfect weather for a ${name} 🧸`, 'cozy vibes only 🤍'],
    stressed: ['come here 🫂 one thing at a time, okay?', 'I\'m right here 💗 we\'ll go gently today', 'breathe in… out… I\'ve got you 🌿'],
    tired: ['rest counts as progress ☁️ small goals today', 'tired is allowed 🤍 let\'s keep it easy', 'water, a stretch, then one tiny task? 🌷'],
    excited: ['YES 🎉 what are we celebrating?!', 'excited?! I\'m vibrating 🎊', 'big energy day, let\'s go!! ✨'],
  }[mood]
  return pick(r)
}

const BY_MOOD = {
  radiant: ['you\'re the main character and the plot is going great', 'today, everything you touch turns a little more golden',
    'someone is quietly proud of you. (it\'s me.)', 'your energy is a free gift to everyone around you', 'a small win is already on its way to you'],
  cozy: ['soft hours are productive hours too', 'a warm drink and one gentle task. that\'s a whole day', 'you don\'t have to earn rest',
    'the cosiest version of you is also the most capable', 'go slow. the cosy things last longest'],
  stressed: ['you only have to do the next small thing', 'this feeling is weather, not climate. it will pass', 'you\'ve survived 100% of your hard days so far',
    'unclench your jaw. drop your shoulders. okay, better', 'done is better than perfect, and breaks are part of the work'],
  tired: ['your best today can look different, and that\'s okay', 'drink some water, then decide. you\'re doing fine',
    'even a tiny bit of progress still counts', 'rest is not laziness. it\'s maintenance', 'be as kind to yourself as you\'d be to a friend'],
  excited: ['ride this wave, it\'s yours', 'good things are circling you. say yes to one of them', 'your excitement is contagious. spread it kindly',
    'today is a day for starting the thing', 'celebrate before it\'s finished, you\'ve earned it'],
}
const COLOURS = ['lilac 💜', 'butter yellow 💛', 'mint 💚', 'blush pink 🩷', 'sky blue 💙', 'peach 🧡', 'cream 🤍']
const SNACKS = ['onigiri 🍙', 'strawberry mochi 🍓', 'a warm cookie 🍪', 'boba 🧋', 'toast with honey 🍯', 'clementines 🍊', 'iced matcha 🍵', 'pretzels 🥨']
const TIPS = ['25 minutes on, 5 minutes off. Start with just one', 'write down the one thing to do first', 'phone in another room, brain in this one',
  'water first, then work', 'do the hard thing before lunch', 'if it takes under two minutes, do it now', 'close the tabs you\'re not using',
  'stand up and stretch once an hour', 'a tidy desk is a tiny fresh start']

/** Deterministic per day + mood: the note doesn't change every time you open it. */
export function note(mood, dayKeyStr) {
  const days = Math.floor(new Date(dayKeyStr).getTime() / 86400000)
  const seed = days + [...mood].reduce((a, c) => a + c.charCodeAt(0), 0)
  const at = (a, salt) => a[Math.abs(seed + salt * 7919) % a.length]
  return {
    text: at(BY_MOOD[mood] || ['you\'re doing great'], 0),
    extras: `💡 study tip: ${at(TIPS, 3)}\nlucky colour: ${at(COLOURS, 1)} · lucky snack: ${at(SNACKS, 2)}`,
  }
}

// Chat that works with no internet: she answers in her own voice, and a few phrases do real things
// ("focus 25", "dance", "stay"). Ported from LocalChat in Chat.swift.
import { pick } from './util.js'
import * as Dlg from './dialogue.js'
import { moodReply } from './fortune.js'

/** Phrases that act on her instead of chatting. Returns the reply, or null if it isn't one. */
export function localCommand(text, pet) {
  const t = text.toLowerCase()
  const m = t.match(/focus(?: for)? (\d{1,3})/)
  if (m) {
    const mins = Math.min(Math.max(Number(m[1]), 1), 240)
    pet.startFocus(mins, pet.intention)
    return Dlg.line('timerStart', pet.species, { n: String(mins) }, pet.name)
  }
  if (t.includes('start a focus') || t === 'focus' || t.includes('study with me')) {
    pet.startFocus(25, pet.intention)
    return Dlg.line('timerStart', pet.species, { n: '25' }, pet.name)
  }
  if (t.includes('dance')) { pet.dance(); return Dlg.line('dance', pet.species, {}, pet.name) }
  if (t.includes('sit still') || t === 'stay' || t.includes('stay here')) {
    if (!pet.staying) pet.toggleStay()
    return Dlg.line('stay', pet.species, {}, pet.name)
  }
  if (t.includes('come here') || t.includes('come to me')) { pet.comeHere(); return Dlg.line('comeHere', pet.species, {}, pet.name) }
  if (!t.includes('feed me') && t.startsWith('feed')) { pet.feed(); return Dlg.line('fed', pet.species, {}, pet.name) }
  if (t.includes('go to sleep') || t.includes('nap')) { pet.nap(); return Dlg.line('sleepy', pet.species, {}, pet.name) }
  return null
}

const JOKES = [
  'why did the student eat their homework? the teacher said it was a piece of cake 🍰',
  'I told my laptop I needed a break. it said it\'d been waiting for me to say that 🔋',
  'what do you call a sleepy pet? a nap-stronaut 🚀💤',
]

export function localReply(text, pet) {
  const t = text.toLowerCase(), s = pet.species, name = pet.name
  const has = (words) => words.some((w) => t.includes(w))
  if (has(['hello', 'hi ', 'hey', 'good morning', 'good night']) || t === 'hi') return Dlg.line('greetDay', s, {}, name)
  if (has(['thank', 'thx', 'ty '])) return Dlg.line('petted', s, {}, name)
  if (has(['love you', 'ily', 'i love'])) return Dlg.line('petted', s, {}, name)
  if (has(['stressed', 'anxious', 'overwhelmed', 'panic', 'worried'])) return moodReply('stressed', s)
  if (has(['tired', 'exhausted', 'sleepy', 'drained'])) return moodReply('tired', s)
  if (has(['sad', 'lonely', 'cry', 'down', 'bad day'])) return moodReply('stressed', s) + ' 🫂'
  if (has(['hungry', 'snack', 'food'])) return Dlg.line('hungry', s, {}, name)
  if (has(['bored'])) return Dlg.line('bored', s, {}, name)
  if (has(['study', 'homework', 'exam', 'essay', 'assignment', 'deadline'])) {
    return Dlg.line('praise', s, {}, name) + '\nwant me to sit with you? say “focus 25” 📖'
  }
  if (has(['help', 'what can you do'])) {
    return 'I can chat, cheer you on, and do things: “focus 25”, “dance”, “stay”, “come here”. Connect a chat brain in Settings and I can help with homework and emails too 💗'
  }
  if (has(['water', 'drink'])) return Dlg.line('water', s, {}, name)
  if (has(['stretch'])) return Dlg.line('stretchRemind', s, {}, name)
  if (has(['joke'])) return pick(JOKES)
  return Dlg.line('chatter', s, {}, name)
}

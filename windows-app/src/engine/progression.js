// Levelling: a pet you've seen do everything gets closed after three days. XP turns "she's cute"
// into "she's mine, and she's come this far". Ported from Progression.swift.
export const Award = { focusMinute: 1, timerFinished: 25, fed: 5, treat: 3, played: 5, petted: 1, task: 3, dailyFirstFocus: 20 }

export const xpForNext = (level) => 80 + (Math.max(1, level) - 1) * 60
export const totalXPToReach = (level) => { let t = 0; for (let l = 1; l < level; l++) t += xpForNext(l); return t }

export function resolveXP(totalXP) {
  let level = 1, remaining = Math.max(0, totalXP)
  while (remaining >= xpForNext(level)) {
    remaining -= xpForNext(level)
    level += 1
    if (level > 999) break
  }
  return { level, into: remaining, needed: xpForNext(level) }
}

const NAMES = {
  dog: ['Newborn Pup', 'Clumsy Puppy', 'Good Dog', 'Legendary Hound'],
  cat: ['Newborn Kitten', 'Curious Kitten', 'Clever Cat', 'Legendary Feline'],
  bunny: ['Newborn Kit', 'Bouncy Bunny', 'Clever Bunny', 'Legendary Hare'],
  fox: ['Newborn Kit', 'Sneaky Kit', 'Clever Fox', 'Legendary Kitsune'],
  panda: ['Newborn Cub', 'Sleepy Cub', 'Bamboo Buddy', 'Legendary Panda'],
  hamster: ['Newborn Pup', 'Tiny Hammy', 'Cheeky Hamster', 'Legendary Hamster'],
  axolotl: ['Newborn Larva', 'Wiggly Smiler', 'Gilled Genius', 'Legendary Axolotl'],
  capybara: ['Newborn Capy', 'Chill Capy', 'Zen Capybara', 'Legendary Capybara'],
}
export function levelTitle(level, species) {
  const n = NAMES[species]
  if (level < 3) return n[0]
  if (level < 5) return n[1]
  if (level < 8) return n[2]
  if (level < 12) return 'Best Friend'
  if (level < 17) return 'Focus Buddy'
  if (level < 24) return 'Study Champion'
  if (level < 32) return n[3]
  return 'Soulmate ✨'
}

export const collarLevels = [3, 8, 14, 20, 28]
export const collarTier = (level) => collarLevels.filter((l) => level >= l).length
const COLLAR_NAMES = ['', 'leather collar', 'silver collar', 'gold collar', 'sapphire collar', 'amethyst collar']
export const collarName = (tier) => COLLAR_NAMES[Math.min(5, Math.max(1, tier))]
export function nextUnlock(level) {
  const next = collarLevels.find((l) => l > level)
  if (next === undefined) return null
  return `Level ${next}: ${collarName(collarLevels.indexOf(next) + 1)}`
}

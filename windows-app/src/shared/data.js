// The names, colours and numbers the pet is made of. Ported from Theme.swift.
import { rgb, Color } from './gfx.js'

export const Design = { width: 200, lift: 26, height: 168 + 26, ground: 152, centerX: 100 }

export const Fur = {
  ink: rgb(0.38, 0.34, 0.40),
  tongue: rgb(1.0, 0.58, 0.68),
  tongueDk: rgb(0.87, 0.40, 0.52),
  heart: rgb(0.93, 0.55, 0.78),
  alertAccent: rgb(0.91, 0.40, 0.45),
  warnAccent: rgb(0.95, 0.72, 0.40),
  blushAccent: rgb(0.95, 0.74, 0.76),
}

// ---------------------------------------------------------------- species & coats

class Coat {
  constructor(name, light, mid, shade, belly, patch, stripes = false) {
    this.name = name
    const c = (t) => rgb(t[0], t[1], t[2])
    this.light = c(light); this.mid = c(mid); this.shade = c(shade); this.belly = c(belly); this.patch = c(patch)
    this.stripes = stripes
    this.raw = [light, mid, shade, belly, patch]
  }
}

const COATS = {
  cat: [
    new Coat('Lilac', [0.98, 0.95, 1.0], [0.84, 0.78, 0.97], [0.66, 0.58, 0.88], [1, 0.98, 1.0], [0.66, 0.58, 0.88]),
    new Coat('Ginger', [1.0, 0.89, 0.72], [0.98, 0.72, 0.45], [0.84, 0.52, 0.28], [1, 0.95, 0.87], [0.84, 0.50, 0.26], true),
    new Coat('Cloud', [1, 1, 1], [0.95, 0.94, 0.97], [0.79, 0.78, 0.87], [1, 1, 1], [0.79, 0.78, 0.87]),
  ],
  dog: [
    new Coat('Biscuit', [1.0, 0.93, 0.80], [0.94, 0.79, 0.56], [0.80, 0.60, 0.39], [1, 0.97, 0.90], [0.72, 0.51, 0.32]),
    new Coat('Snow', [1, 0.99, 0.99], [0.97, 0.94, 0.94], [0.82, 0.74, 0.74], [1, 1, 1], [0.80, 0.68, 0.68]),
    new Coat('Cocoa', [0.86, 0.70, 0.56], [0.68, 0.50, 0.38], [0.52, 0.36, 0.27], [0.97, 0.89, 0.78], [0.40, 0.27, 0.20]),
  ],
  bunny: [
    new Coat('Snow', [1, 1, 1], [0.96, 0.94, 0.97], [0.82, 0.78, 0.89], [1, 1, 1], [0.82, 0.78, 0.89]),
    new Coat('Caramel', [1.0, 0.93, 0.83], [0.91, 0.75, 0.59], [0.77, 0.59, 0.45], [1, 0.97, 0.92], [0.77, 0.59, 0.45]),
    new Coat('Lavender', [0.97, 0.95, 1], [0.85, 0.81, 0.95], [0.69, 0.63, 0.87], [1, 0.99, 1], [0.69, 0.63, 0.87]),
  ],
  fox: [
    new Coat('Ember', [1.0, 0.84, 0.64], [0.98, 0.61, 0.31], [0.83, 0.43, 0.21], [1, 0.97, 0.93], [0.42, 0.29, 0.26]),
    new Coat('Arctic', [1, 1, 1], [0.89, 0.93, 0.98], [0.67, 0.75, 0.89], [1, 1, 1], [0.48, 0.53, 0.66]),
  ],
  panda: [
    new Coat('Classic', [1, 1, 1], [0.96, 0.96, 0.98], [0.80, 0.80, 0.87], [1, 1, 1], [0.30, 0.29, 0.35]),
    new Coat('Cocoa', [1, 0.98, 0.94], [0.97, 0.92, 0.86], [0.85, 0.76, 0.68], [1, 0.98, 0.95], [0.52, 0.36, 0.29]),
  ],
  hamster: [
    new Coat('Peach', [1.0, 0.94, 0.84], [0.99, 0.82, 0.60], [0.89, 0.64, 0.42], [1, 0.98, 0.95], [0.94, 0.72, 0.49]),
    new Coat('Mochi', [1, 1, 1], [0.95, 0.94, 0.96], [0.79, 0.78, 0.85], [1, 1, 1], [0.84, 0.79, 0.88]),
  ],
  axolotl: [
    new Coat('Strawberry', [1.0, 0.94, 0.96], [1.0, 0.80, 0.87], [0.94, 0.62, 0.74], [1, 0.97, 0.98], [0.98, 0.50, 0.62]),
    new Coat('Mint', [0.94, 1.0, 0.97], [0.76, 0.94, 0.87], [0.55, 0.79, 0.72], [0.98, 1, 0.99], [0.98, 0.56, 0.66]),
    new Coat('Lilac', [0.98, 0.95, 1.0], [0.87, 0.80, 0.97], [0.70, 0.60, 0.88], [1, 0.98, 1], [0.96, 0.52, 0.72]),
  ],
  capybara: [
    new Coat('Toast', [0.90, 0.75, 0.57], [0.76, 0.57, 0.40], [0.60, 0.42, 0.29], [0.93, 0.80, 0.63], [0.47, 0.31, 0.21]),
    new Coat('Honey', [0.99, 0.86, 0.62], [0.90, 0.69, 0.42], [0.74, 0.52, 0.28], [1.0, 0.91, 0.74], [0.58, 0.38, 0.20]),
  ],
}

export const SPECIES = ['cat', 'dog', 'bunny', 'fox', 'panda', 'hamster', 'axolotl', 'capybara']
const SPECIES_INFO = {
  cat: { name: 'Kitten', emoji: '🐱', blurb: 'Washes her face, purrs', voice: 'cat', pitch: 1 },
  dog: { name: 'Puppy', emoji: '🐶', blurb: 'Floppy ears, big wags', voice: 'dog', pitch: 1 },
  bunny: { name: 'Bunny', emoji: '🐰', blurb: 'Long ears, tiny hops', voice: 'squeak', pitch: 1 },
  fox: { name: 'Fox', emoji: '🦊', blurb: 'Bushy tail, cheeky', voice: 'dog', pitch: 1.35 },
  panda: { name: 'Panda', emoji: '🐼', blurb: 'Round, sleepy, huggable', voice: 'dog', pitch: 0.8 },
  hamster: { name: 'Hamster', emoji: '🐹', blurb: 'Pocket-sized, stuffs cheeks', voice: 'squeak', pitch: 1 },
  axolotl: { name: 'Axolotl', emoji: '🦎', blurb: 'Forever smiling, feathery gills', voice: 'squeak', pitch: 1 },
  capybara: { name: 'Capybara', emoji: '🦫', blurb: 'Calm. Unbothered. Loved by all', voice: 'squeak', pitch: 1 },
}
export const speciesInfo = (s) => SPECIES_INFO[s]
export const coatsOf = (s) => COATS[s]

// ---------------------------------------------------------------- emotions

export const EMOTIONS = {
  neutral: ['🐶', 'chilling'], happy: ['😊', 'happy'], love: ['💗', 'in love with you'], excited: ['🤩', 'SO excited'],
  sleepy: ['😴', 'sleepy'], hungry: ['🍖', 'hungry'], angry: ['😤', 'disappointed in you'], sad: ['🥺', 'a little sad'],
  playful: ['🎾', 'playful'], eating: ['😋', 'eating'], alert: ['👀', 'watching you'], dizzy: ['😵‍💫', 'wheee'],
  curious: ['🤔', 'curious about you'], shy: ['🙈', 'a little shy'], proud: ['🥹', 'so proud'], worried: ['😟', 'worried about you'],
  bored: ['😑', 'bored'], blissful: ['✨', 'perfectly happy'], moody: ['😒', 'in a mood'], cozy: ['☕️', 'all cozy'],
  hyped: ['🎉', 'so hyped'], vibing: ['🎧', 'vibing'],
}
export const emotionLabel = (e) => EMOTIONS[e][1]
export const emotionEmoji = (e) => EMOTIONS[e][0]

// ---------------------------------------------------------------- accessories

export const SLOTS = ['rug', 'aura', 'body', 'neck', 'face', 'head', 'hair', 'held']
export const SLOT_TITLES = {
  rug: 'Rug under her', aura: 'Aura', body: 'Clothes', neck: 'Around her neck',
  face: 'On her face', head: 'On her head', hair: 'In her hair', held: 'In her paws',
}

// id: [slot, title, emoji, price]
const ACC = {
  rugCoquette: ['rug', 'Ribbon rug', '🎀', 0], rugCottage: ['rug', 'Leaf rug', '🍃', 45],
  rugY2K: ['rug', 'Heart rug', '💖', 45], rugCyber: ['rug', 'Glow rug', '🔮', 45],
  auraSparkles: ['aura', 'Sparkles', '✨', 70], auraHearts: ['aura', 'Hearts', '💕', 70], auraStars: ['aura', 'Stars', '⭐️', 90],
  knitSweater: ['body', 'Knit sweater', '🧶', 50], hoodie: ['body', 'Hoodie', '👚', 60],
  angelWings: ['body', 'Angel wings', '🪽', 90], cape: ['body', 'Cape', '🦸‍♀️', 75],
  scarf: ['neck', 'Scarf', '🧣', 0], bandana: ['neck', 'Bandana', '🏴‍☠️', 0], pearls: ['neck', 'Pearls', '📿', 0],
  bell: ['neck', 'Bell', '🔔', 0], bowtie: ['neck', 'Bow tie', '🎩', 0],
  glasses: ['face', 'Glasses', '🤓', 0], sunglasses: ['face', 'Shades', '😎', 0],
  heartGlasses: ['face', 'Hearts', '😍', 0], lashes: ['face', 'Lashes', '💅', 0],
  crown: ['head', 'Crown', '👑', 0], headphones: ['head', 'Headphones', '🎧', 0], yuzu: ['head', 'Yuzu', '🍊', 0],
  beret: ['head', 'Beret', '🎨', 0], partyHat: ['head', 'Party hat', '🥳', 0], halo: ['head', 'Halo', '😇', 0],
  bow: ['hair', 'Bow', '🎀', 0], flower: ['hair', 'Flower', '🌼', 0], starClip: ['hair', 'Star clip', '⭐️', 0],
  boba: ['held', 'Boba', '🧋', 0], matcha: ['held', 'Matcha', '🍵', 40], book: ['held', 'Book', '📖', 0], console: ['held', 'Game', '🎮', 55],
}
export const ACCESSORIES = Object.keys(ACC)
export const accSlot = (a) => (a === 'none' ? 'head' : ACC[a][0])
export const accTitle = (a) => (a === 'none' ? 'None' : ACC[a][1])
export const accEmoji = (a) => (a === 'none' ? '✨' : ACC[a][2])
export const accPrice = (a) => (a === 'none' ? 0 : ACC[a][3])
export const accessoriesFor = (slot) => ACCESSORIES.filter((a) => ACC[a][0] === slot)

export const emptyOutfit = () => ({ rug: 'none', aura: 'none', body: 'none', neck: 'none', face: 'none', head: 'none', hair: 'none', held: 'none' })
export const outfitOf = (o = {}) => ({ ...emptyOutfit(), ...o })
export const outfitIsEmpty = (o) => SLOTS.every((s) => o[s] === 'none')

// ---------------------------------------------------------------- decor

const DECOR = {
  plant: ['Plant', '🪴', 100], lamp: ['Lamp', '🛋️', 90], books: ['Book stack', '📚', 70], fairyLights: ['Fairy lights', '✨', 150],
  teddy: ['Teddy', '🧸', 120], duck: ['Rubber duck', '🦆', 60], bobaCup: ['Mini boba', '🧋', 60], cocoa: ['Cocoa mug', '☕️', 60],
  sakura: ['Sakura', '🌸', 80], leaves: ['Autumn leaves', '🍂', 80], rainDrops: ['Cosy rain', '🌧️', 80], starSparkles: ['Starry night', '🌟', 110],
}
export const DECORS = Object.keys(DECOR)
export const decorTitle = (d) => DECOR[d][0]
export const decorEmoji = (d) => DECOR[d][1]
export const decorPrice = (d) => DECOR[d][2]
export const decorIsAmbient = (d) => ['sakura', 'leaves', 'rainDrops', 'starSparkles'].includes(d)

// ---------------------------------------------------------------- app themes (the panel's look)

const THEMES = {
  coquette: { title: 'Coquette Bows', emoji: '🎀', dark: false, accent: [0.80, 0.70, 0.97], second: [1.0, 0.74, 0.84], hot: [[0.96, 0.48, 0.70], [0.72, 0.54, 0.95]], top: [1.0, 0.968, 0.978], bottom: [0.965, 0.95, 0.995] },
  y2k: { title: 'Y2K Pink', emoji: '💿', dark: false, accent: [1.0, 0.55, 0.80], second: [0.58, 0.90, 1.0], hot: [[1.0, 0.32, 0.64], [0.56, 0.50, 1.0]], top: [1.0, 0.95, 0.98], bottom: [0.925, 0.945, 1.0] },
  cottagecore: { title: 'Cottagecore', emoji: '🍵', dark: false, accent: [0.62, 0.80, 0.58], second: [0.98, 0.88, 0.66], hot: [[0.46, 0.72, 0.50], [0.74, 0.82, 0.40]], top: [0.975, 0.985, 0.955], bottom: [0.925, 0.965, 0.915] },
  darkAcademia: { title: 'Dark Academia', emoji: '📜', dark: true, accent: [0.80, 0.60, 0.40], second: [0.72, 0.34, 0.38], hot: [[0.60, 0.24, 0.30], [0.78, 0.58, 0.34]], top: [0.145, 0.115, 0.108], bottom: [0.205, 0.15, 0.135] },
  boba: { title: 'Pastel Boba', emoji: '🧋', dark: false, accent: [0.86, 0.70, 0.56], second: [1.0, 0.80, 0.82], hot: [[0.80, 0.56, 0.42], [0.96, 0.66, 0.74]], top: [0.99, 0.965, 0.94], bottom: [0.97, 0.93, 0.905] },
  cyberPastel: { title: 'Cyber Pastel', emoji: '🔮', dark: false, accent: [0.72, 0.66, 1.0], second: [0.62, 0.95, 0.86], hot: [[0.48, 0.42, 1.0], [0.24, 0.88, 0.76]], top: [0.96, 0.955, 1.0], bottom: [0.915, 0.975, 0.965] },
}
export const THEME_IDS = Object.keys(THEMES)
export const themeInfo = (id) => THEMES[id] || THEMES.coquette

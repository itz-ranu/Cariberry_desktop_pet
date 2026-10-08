// The pet's brain: her moods, her little life, and what happens when you work. A port of Pet.swift
// with the macOS parts (windows, screens, AppleScript) pushed out to a `host` the app provides, so
// the whole thing runs under plain Node too. Coordinates: screen is y-up (paws = `position`),
// the scene (particles, bubbles) is y-down from the pet window's top-left.
import { now, rand, pick, clamp, clamp01, dayKey, addDays, parseDay, uuid } from './util.js'
import { Stage, STAGE, SCALES } from './stage.js'
import { Design, speciesInfo, coatsOf, accSlot, accPrice, accTitle, accEmoji, decorPrice, decorTitle, decorEmoji, decorIsAmbient, DECORS, outfitOf, SLOTS } from '../shared/data.js'
import { defaultPose, tapRaise } from '../shared/critter.js'
import * as Dlg from './dialogue.js'
import { Award, resolveXP, levelTitle, collarTier, collarLevels, collarName } from './progression.js'
import { BADGES, badgeEarned, HABITS, HABIT_XP, HABIT_BERRIES, HABIT_BONUS } from './badges.js'
import { MOODS, moodReply, needsGentleness } from './fortune.js'

const { sin, cos, abs, min, max, PI } = Math
const ease = (obj, key, target, rate, dt) => {
  obj[key] += (target - obj[key]) * min(1, dt * rate)
  if (abs(target - obj[key]) < 0.002) obj[key] = target
}
const TAP_DURATION = 1.3
const SHORT_FORM = ['Reels & short-form video', 'Guard: TikTok', 'Guard: Instagram']

export class Pet {
  /** `host` supplies the machine: screens, window spots, sounds, saving. See `NullHost`. */
  constructor(prefs, rules, host = new NullHost()) {
    this.prefs = prefs
    this.rules = rules
    this.host = host

    // vital stats, all 0...1
    this.hunger = 0.85; this.happiness = 0.8; this.energy = 0.9; this.affection = 0.5

    this.name = prefs.get('petName')
    this.species = prefs.get('species')
    this.coatIndex = prefs.coat(this.species)
    this.outfit = outfitOf(prefs.get('outfit'))
    this.staying = prefs.get('stay')
    this.sizeLevel = prefs.get('sizeLevel')
    Stage.setScale(SCALES[clamp(this.sizeLevel, 0, 2)])
    this.decorOn = new Set(prefs.get('decorOn'))
    this.berries = 0; this.owned = new Set(); this.berryRemainder = 0
    this.moods = {}
    this.bop = 0; this.bopUntil = 0
    this.danceAmt = 0; this.waveAmt = 0; this.lastNote = 0
    this.holdStill = false
    this.act = 'idle'; this.phase = 0
    this.facing = 1
    this.position = { x: 0, y: 0 }
    this.squash = 0; this.petting = 0
    this.look = { dx: 0, dy: 0 }; this.lookVis = { dx: 0, dy: 0 }
    this.nearCursor = false
    this.particles = []; this._pid = 0
    this.bubbleText = null; this.bubbleUntil = 0
    this.bowl = 0
    this.closeButtonAt = null; this.closeButtonPressed = false

    // focus coaching
    this.focusSeconds = 0; this.distractSeconds = 0
    this.totalFocusMinutes = 0
    this.currentActivity = '…'; this.lastVerdict = 'neutral'
    this.treatsEaten = 0; this.barksGiven = 0
    this.xp = 0; this.lastXPDay = ''
    this.born = Date.now()
    this.siteTime = {}; this.dailyFocus = {}; this.categoryTime = {}; this.dailyAppTime = {}
    this.dailyDistraction = {}; this.dailyBarks = {}; this.dailyTasks = {}; this.dailySessions = {}
    // seconds at the computer but idle, per day; focused minutes per hour of the day; and what each app counted as
    this.dailyAway = {}; this.focusByHour = {}; this.siteKinds = {}
    this.tasks = []
    this.presenceNote = ''

    // focus timer
    this.timerEndsAt = null; this.timerIsBreak = false; this.timerTotal = 0; this.lastTimerNudge = 0
    this.intention = ''

    this.moodOverride = null
    this.actUntil = 0; this.actStartedAt = 0
    this.walkTarget = null
    this.velocity = { x: 0, y: 0 }
    this.nextScold = 0; this.scoldCount = 0; this.lastPraise = 0
    this.nextMilestone = 10 * 60
    this.wasDistracted = false
    this.speedMultiplier = 1
    this.lastInteraction = now()
    this.calledOver = false
    this.followUntil = 0
    this.restY = null; this.perchX = 0
    this.cursor = { x: 0, y: 0 }

    // props and eased pose amounts
    this.propKind = 'none'; this.propAmt = 0
    this.gait = 0; this.gaitRate = 10
    this.walkAmt = 0; this.runAmt = 0; this.sitAmt = 0; this.sleepAmt = 0
    this.stretchAmt = 0; this.sniffAmt = 0; this.groomAmt = 0; this.scratchAmt = 0
    this.facingVis = 1
    this.blending = false

    // music
    this.ambience = prefs.get('ambience')
    this.ambienceManual = false; this.ambienceHushed = false
    this.musicSecondsPending = 0; this.lastMusicBeat = -1

    this.dailyGoal = prefs.get('dailyGoal')
    this.streakAnnouncedDay = ''
    this.lastWater = now(); this.lastStretch = now(); this.lastEyes = now(); this.lastReminderCheck = now()
    this.lastBadgeCheck = 0
    this.currentMood = prefs.todayMood
    this.lastMoodRefresh = now()

    // the close-a-Reels-tab choreography
    this.closing = false; this.closeToken = 0; this.homeSpot = null; this.homeOnFloor = true
    this.leapFrom = { x: 0, y: 0 }; this.leapTo = { x: 0, y: 0 }; this.leapStart = 0; this.leapDur = 0.85
  }

  // ------------------------------------------------------------------ derived

  get emotion() {
    if (this.moodOverride && this.moodOverride.until > now()) return this.moodOverride.emotion
    switch (this.act) {
      case 'carried': return 'dizzy'
      case 'sleep': return 'sleepy'
      case 'eat': return 'eating'
      case 'bark': return 'angry'
      case 'zoom': return 'playful'
      case 'love': return 'love'
      case 'tap': return 'alert'
      case 'dance': case 'wave': return 'happy'
      case 'leap': return 'excited'
    }
    if (this.petting > 0.15) return 'love'
    const calmAct = this.act === 'idle' || this.act === 'sit'
    if (this.hunger > 0.92 && this.happiness > 0.92 && this.energy > 0.85 && this.affection > 0.8 && calmAct) return 'blissful'
    if (this.hunger < 0.12 && this.happiness < 0.25) return 'worried'
    if (this.hunger < 0.25) return 'hungry'
    if (this.energy < 0.2) return 'sleepy'
    if (this.happiness < 0.3) return 'sad'
    if (this.nearCursor && calmAct) return 'curious'
    if (this.act === 'idle' && this.happiness < 0.7 && now() - this.lastInteraction > 200) return 'bored'
    if (now() < this.bopUntil && calmAct) return 'vibing'
    if (calmAct && this.currentMood) {
      switch (this.currentMood) {
        case 'cozy': case 'stressed': return 'cozy'
        case 'excited': return 'hyped'
        case 'tired': return this.energy < 0.7 ? 'sleepy' : 'cozy'
      }
    }
    if (this.happiness > 0.82 && this.affection > 0.6) return 'happy'
    if (this.happiness > 0.6) return 'happy'
    if (this.happiness < 0.5 && this.happiness >= 0.3) return 'moody'
    return 'neutral'
  }

  get level() { return resolveXP(this.xp).level }
  get levelTitle() { return levelTitle(this.level, this.species) }
  get levelProgress() { const r = resolveXP(this.xp); return r.needed > 0 ? min(1, r.into / r.needed) : 0 }
  get collarTier() { return collarTier(this.level) }
  get scale() { return SCALES[clamp(this.sizeLevel, 0, 2)] }
  get actElapsed() { return now() - this.actStartedAt }
  get perched() { return this.restY !== null }
  /** Where to save her: x, and y (or -1 for the floor), so she's where you left her after a restart. */
  get spot() { return { x: this.position.x, y: this.restY ?? -1 } }

  get pose() {
    return {
      ...defaultPose(),
      emotion: this.emotion, phase: this.phase, gait: this.gait, walk: this.walkAmt, run: this.runAmt, facing: this.facingVis,
      squash: this.squash, dangling: this.act === 'carried', look: this.lookVis, sit: this.sitAmt, sleep: this.sleepAmt,
      petting: this.petting, stretch: this.stretchAmt, sniff: this.sniffAmt, groom: this.groomAmt, scratch: this.scratchAmt,
      dance: this.danceAmt, wave: this.waveAmt, bop: this.bop, collarTier: this.collarTier,
      tapping: this.act === 'tap', tapPhase: this.act === 'tap' ? min(1, this.actElapsed / TAP_DURATION) : 0,
      outfit: this.outfit, perched: this.perched, prop: this.propKind, propAmt: this.propAmt,
    }
  }

  get timerRemaining() { return this.timerEndsAt === null ? null : max(0, this.timerEndsAt - now()) }
  get focusTimerRunning() { return this.timerEndsAt !== null && !this.timerIsBreak }
  get onBreak() { return this.timerEndsAt !== null && this.timerIsBreak }
  get ageDays() { return max(0, Math.floor((Date.now() - this.born) / 86400000)) }
  get inFlow() { return this.focusSeconds >= 20 * 60 }

  /** How often she needs redrawing. Every frame costs CPU, so she only gets what she needs: resting barely moves
   *  (a breath, a blink), a walk needs smooth legs, a drag or a bark needs the most. */
  get desiredFrameInterval() {
    if (this.act === 'sleep' && !this.blending) return 1 / 4
    switch (this.act) {
      case 'zoom': case 'fall': case 'carried': case 'bark': case 'tap': case 'leap': return 1 / 30
      case 'walk': return 1 / 18
      case 'dance': case 'groom': case 'scratch': case 'sniff': case 'wave': return 1 / 20
    }
    if (this.blending || this.particles.length || this.petting > 0.01) return 1 / 20
    switch (this.emotion) {
      case 'excited': case 'playful': case 'blissful': case 'angry': case 'eating': case 'love': case 'proud': case 'dizzy': return 1 / 16
      default: return 1 / 9
    }
  }

  // ------------------------------------------------------------------ screens

  get screens() { return this.host.screens() }
  get screen() {
    const s = this.screens
    return s.find((r) => this.position.x >= r.minX && this.position.x <= r.maxX) || s[0]
  }
  get groundY() { return this.screen.minY + 2 }
  get floorY() { return this.restY ?? this.groundY }
  get topY() { return this.screen.maxY - Design.height * this.scale + 40 }
  clampY(y) { return min(max(y, this.groundY), max(this.groundY, this.topY)) }
  get minX() { return this.screen.minX + 30 }
  get maxX() { return this.screen.maxX - 30 }

  placeAtStart() {
    const s = this.screens[0]
    this.position = { x: (s.minX + s.maxX) / 2, y: s.minY + 2 }
    const spot = this.prefs.get('petSpot')
    if (spot) {
      const sc = this.screens.find((r) => spot.x >= r.minX && spot.x <= r.maxX)
      if (sc) {
        this.position = { x: min(max(spot.x, sc.minX + 30), sc.maxX - 30), y: sc.minY + 2 }
        if (spot.y > this.position.y + 30 && this.prefs.get('placeAnywhere')) {
          this.restY = this.clampY(spot.y); this.perchX = this.position.x; this.position.y = this.restY
        }
      }
    }
  }

  goHome() {
    this.cancelCloseSequence()
    const s = this.screen
    this.restY = null; this.walkTarget = null
    this.position = { x: (s.minX + s.maxX) / 2, y: this.groundY }
    this.setAct('idle', 2)
    this.squash = 0.3
    this.say('home sweet home 🏠', 'happy', 2.4)
    this.emit('sparkle', 6, Stage.head, 40)
  }

  // ------------------------------------------------------------------ the frame

  tick(dt) {
    this.phase += dt
    this.decayStats(dt)
    this.updateAct(dt)
    this.updatePhysics(dt)
    this.updateBlends(dt)
    this.updateParticles(dt)
    this.updateTimer()
    this.updateReminders()
    this.updateMusicBop()
    if (this.ambiencePlaying) {
      this.musicSecondsPending += dt
      if (this.musicSecondsPending >= 60) {
        this.prefs.set('musicMinutes', this.prefs.get('musicMinutes') + this.musicSecondsPending / 60)
        this.musicSecondsPending = 0
      }
    }
    if (now() - this.lastMoodRefresh > 30) { this.lastMoodRefresh = now(); this.currentMood = this.prefs.todayMood }
    this.petting = max(0, this.petting - dt * 0.55)
    this.squash += (0 - this.squash) * min(1, dt * 9)
    if (this.bubbleUntil < now()) this.bubbleText = null
    if (this.moodOverride && this.moodOverride.until < now()) this.moodOverride = null
  }

  decayStats(dt) {
    this.hunger = max(0, this.hunger - dt / (60 * 90))
    this.energy = this.act === 'sleep' ? min(1, this.energy + dt / (60 * 6)) : max(0, this.energy - dt / (60 * 150))
    if (this.act === 'zoom') this.energy = max(0, this.energy - dt / 120)
    let target = 0.55 + this.affection * 0.25
    if (this.hunger < 0.2) target -= 0.35
    if (this.energy < 0.15) target -= 0.15
    this.happiness += (target - this.happiness) * min(1, dt / 240)
    this.affection = max(0, this.affection - dt / (60 * 60 * 8))
    this.happiness = clamp01(this.happiness)
  }

  setAct(a, seconds) {
    this.act = a
    this.actUntil = now() + seconds
    this.actStartedAt = now()
    if (a !== 'walk' && a !== 'zoom') this.walkTarget = null
    if (a === 'sleep') this.emit('zzz', 1, Stage.aura, 6)
  }

  updateAct(dt) {
    if (this.act === 'carried' || this.act === 'fall' || this.act === 'leap') return
    const t0 = now()
    if (this.isFollowing) this.follow()
    if (this.act === 'dance' && t0 - this.lastNote > 0.5) { this.lastNote = t0; this.emit('note', 1, Stage.aura, 34) }

    if (this.walkTarget !== null) {
      const dx = this.walkTarget - this.position.x
      if (abs(dx) < 6) {
        this.walkTarget = null
        if (this.act === 'walk') {
          if (this.calledOver) {
            this.calledOver = false
            this.say(Dlg.line('arrived', this.species, {}, this.name), null, 2.4)
            this.moodOverride = { emotion: 'shy', until: now() + 2.2 }
          }
          this.setAct('idle', rand(1.5, 4))
        }
      } else {
        this.facing = dx > 0 ? 1 : -1
        const speed = (this.act === 'zoom' ? 420 : 78) * this.speedMultiplier
        this.position.x += speed * dt * this.facing
      }
    }

    if (this.holdStill && !this.isFollowing) {
      this.walkTarget = null
      if (this.act === 'walk') this.setAct('idle', 2)
    }
    if (this.isFollowing) return
    if (!(now() > this.actUntil)) return

    switch (this.act) {
      case 'bark': case 'love': case 'eat': case 'zoom': case 'scratch': case 'stretch': case 'sniff': case 'groom': case 'tap': case 'dance': case 'wave':
        this.bowl = 0
        this.setAct('idle', rand(1, 3))
        return
    }

    // autonomous choices
    if (this.energy < 0.16) {
      this.setAct('sleep', rand(25, 60))
      this.say(Dlg.line('sleepy', this.species, {}, this.name), 'sleepy', 4)
      return
    }
    if (this.act === 'sleep' && this.energy > 0.6) {
      this.setAct('idle', 2)
      this.say(Dlg.line('wokeUp', this.species, {}, this.name), 'happy', 3)
      return
    }
    if (this.act === 'sleep') { this.actUntil = now() + 20; return }

    if (this.hunger < 0.12 && this.happiness < 0.25 && Math.random() < 0.4) {
      this.say(Dlg.line('worried', this.species, {}, this.name), 'worried', 5)
      this.host.onWhine(); this.setAct('idle', 6)
      return
    }
    if (this.hunger < 0.22 && Math.random() < 0.35) {
      this.say(Dlg.line('hungry', this.species, {}, this.name), 'hungry', 5)
      this.host.onWhine(); this.setAct('idle', 6)
      return
    }

    if (this.focusTimerRunning) {
      const r = Math.random()
      if (r < 0.08) this.setAct('stretch', 2.6)
      else if (r < 0.16 && this.species !== 'dog') this.performSignatureMove()
      else this.setAct('sit', rand(10, 22))
      return
    }
    if (this.onBreak && Math.random() < 0.7) { this.setAct('sit', rand(8, 16)); return }

    const roll = Math.random()
    if (roll < 0.40) {
      if (this.prefs.get('roams') && !this.holdStill && !this.staying) this.wander()
      else this.setAct('sit', rand(4, 10))
    } else if (roll < 0.56) this.setAct('sit', rand(4, 10))
    else if (roll < 0.64) this.setAct('scratch', 2.0)
    else if (roll < 0.70) { this.setAct('stretch', 2.6); this.say(Dlg.line('stretch', this.species, {}, this.name), 'happy', 2.4) }
    else if (roll < 0.75) {
      if (this.species !== 'dog') this.performSignatureMove()
      else { this.setAct('sniff', 2.2); this.say(Dlg.line('sniff', this.species, {}, this.name), 'curious', 2.0) }
    } else if (roll < 0.80) { this.setAct('sniff', 2.2); this.say(Dlg.line('sniff', this.species, {}, this.name), 'curious', 2.0) }
    else if (roll < 0.88) {
      this.setAct('idle', 3)
      const e = this.emotion
      const kind = e === 'bored' ? 'bored' : e === 'blissful' ? 'blissful' : e === 'curious' ? 'curious' : 'chatter'
      this.say(Dlg.line(kind, this.species, {}, this.name), e, 3.5)
    } else this.setAct('idle', rand(2, 6))
  }

  updatePhysics(dt) {
    switch (this.act) {
      case 'fall': {
        this.velocity.y -= 2600 * dt
        this.position.y += this.velocity.y * dt
        this.position.x += this.velocity.x * dt
        if (this.position.y <= this.floorY) {
          this.position.y = this.floorY
          const impact = min(1, abs(this.velocity.y) / 1400)
          this.squash = impact
          this.velocity = { x: 0, y: 0 }
          this.setAct('idle', 1.2)
          if (impact > 0.35) {
            this.emit('star', 5, Stage.p(94, Design.ground), 40)
            this.host.onYip()
            this.say(Dlg.line('landed', this.species, {}, this.name), 'dizzy', 2)
            this.moodOverride = { emotion: 'dizzy', until: now() + 1.4 }
          }
        }
        break
      }
      case 'carried': break
      case 'leap': {
        const t = now() - this.leapStart
        if (t < 0) { this.squash = 0.5; this.position = { ...this.leapFrom } }
        else {
          const u = min(1, t / this.leapDur)
          const e = u * u * (3 - 2 * u)
          const arc = sin(u * PI) * (46 + abs(this.leapTo.y - this.leapFrom.y) * 0.25)
          this.position.x = this.leapFrom.x + (this.leapTo.x - this.leapFrom.x) * e
          this.position.y = this.leapFrom.y + (this.leapTo.y - this.leapFrom.y) * e + arc
          this.squash = -0.32 * sin(u * PI)
          if (now() - this.lastNote > 0.09) { this.lastNote = now(); this.emit('sparkle', 1, Stage.p(64, 130), 14) }
        }
        break
      }
      default: {
        const target = this.floorY
        if (abs(this.position.y - target) > 0.5) this.position.y += (target - this.position.y) * min(1, dt * 7)
        else this.position.y = target
      }
    }
    if (this.act !== 'carried') this.position.x = min(max(this.position.x, this.minX), this.maxX)
  }

  updateParticles(dt) {
    if (!this.particles.length) return
    for (const p of this.particles) {
      p.life -= dt
      p.x += p.vx * dt; p.y += p.vy * dt; p.rot += p.spin * dt
      if (p.kind === 'crumb') p.vy += 420 * dt
      if (p.kind === 'confetti') { p.vy += 230 * dt; p.vx *= 0.992; p.spin = p.spin < 0 ? -9 : 9 }
      if (p.kind === 'heart') p.vx = sin(p.life * 5) * 18
      if (p.kind === 'bubble') p.vx = sin(p.life * 7) * 14
    }
    this.particles = this.particles.filter((p) => p.life > 0)
  }

  updateBlends(dt) {
    const keys = ['walkAmt', 'runAmt', 'sitAmt', 'sleepAmt', 'stretchAmt', 'sniffAmt', 'groomAmt', 'scratchAmt', 'facingVis', 'propAmt', 'danceAmt', 'waveAmt']
    const before = keys.map((k) => this[k]).concat([this.lookVis.dx, this.lookVis.dy])
    const walking = ((this.act === 'walk' || this.act === 'zoom') && this.walkTarget !== null) || this.act === 'leap'
    const speed = this.act === 'zoom' ? 420 : 78 * this.speedMultiplier
    ease(this, 'walkAmt', walking ? 1 : 0, 9, dt)
    ease(this, 'runAmt', !walking ? 0 : min(1, max(0, (speed - 110) / 260)), 5, dt)
    ease(this, 'gaitRate', 8 + speed * 0.035, 4, dt)
    this.gait += dt * this.gaitRate * this.walkAmt

    ease(this, 'sitAmt', (this.act === 'sit' || this.act === 'groom' || this.act === 'scratch') ? 1 : 0, 5, dt)
    ease(this, 'sleepAmt', this.act === 'sleep' ? 1 : 0, 2.6, dt)
    ease(this, 'stretchAmt', this.act === 'stretch' ? 1 : 0, 4, dt)
    ease(this, 'sniffAmt', this.act === 'sniff' ? 1 : 0, 6, dt)
    ease(this, 'groomAmt', this.act === 'groom' ? 1 : 0, 5, dt)
    ease(this, 'scratchAmt', this.act === 'scratch' ? 1 : 0, 7, dt)
    ease(this, 'danceAmt', this.act === 'dance' ? 1 : 0, 8, dt)
    ease(this, 'waveAmt', this.act === 'wave' ? 1 : 0, 9, dt)
    ease(this, 'facingVis', this.facing, 13, dt)

    this.bop = max(0, this.bop - dt * 5)

    const held = { boba: 'boba', matcha: 'matcha', book: 'book', console: 'console' }[this.outfit.held] || 'none'
    const want = this.sitAmt > 0.5 ? (this.focusTimerRunning ? 'book' : (this.onBreak ? 'boba' : held)) : 'none'
    if (want === this.propKind) ease(this, 'propAmt', want === 'none' ? 0 : 1, 6, dt)
    else { ease(this, 'propAmt', 0, 9, dt); if (this.propAmt < 0.04) this.propKind = want }
    ease(this.lookVis, 'dx', this.look.dx, 10, dt)
    ease(this.lookVis, 'dy', this.look.dy, 10, dt)

    const after = keys.map((k) => this[k]).concat([this.lookVis.dx, this.lookVis.dy])
    // "still moving" means moving at a pace you could see: the last few percent of an ease crawl for seconds
    this.blending = before.some((v, i) => Math.abs(v - after[i]) > (i >= keys.length ? 0.3 : 0.25) * Math.max(dt, 0.001))
  }

  wander() {
    const lo = this.perched ? max(this.minX, this.perchX - 170) : this.minX
    const hi = this.perched ? min(this.maxX, this.perchX + 170) : this.maxX
    this.walkTarget = rand(lo, max(lo, hi))
    this.speedMultiplier = rand(0.75, 1.3)
    this.setAct('walk', 30)
  }

  performSignatureMove() {
    this.setAct('groom', 3.2)
    this.say(Dlg.line('groom', this.species, {}, this.name), 'happy', 2.8)
  }

  // ------------------------------------------------------------------ closing a Reels tab herself

  get isFollowing() { return now() < this.followUntil }

  /** She leaps up onto your browser window, presses a big ✕ herself, the tab closes on the same
   *  beat, and she leaps back to wherever she was. */
  performCloseTap() {
    if (this.act === 'tap' || this.closing) return
    if (this.host.reduceMotion()) {
      this.say(Dlg.coach('tapClose', this.species, this.prefs), 'alert', 2)
      setTimeout(() => this.host.onCloseReelsTab(), 500)
      return
    }
    this.walkTarget = null
    this.followUntil = 0
    const token = ++this.closeToken
    const spot = this.host.windowSpot()
    if (!spot) { this.tapTheButton(token, () => {}); return }
    this.closing = true
    this.homeSpot = { ...this.position }
    this.homeOnFloor = this.restY === null
    this.say(Dlg.coach('tapClose', this.species, this.prefs), 'alert', 3)
    this.leap({ x: spot.x, y: this.clampY(spot.y) }, token, () => this.tapTheButton(token, () => this.celebrateAndGoHome(token)))
  }

  leap(dest, token, done) {
    this.leapFrom = { ...this.position }
    this.leapTo = dest
    this.leapDur = min(1.1, max(0.6, 0.55 + Math.hypot(dest.x - this.position.x, dest.y - this.position.y) / 1800))
    this.leapStart = now() + 0.22
    this.facing = dest.x >= this.position.x ? 1 : -1
    this.setAct('leap', 30)
    this.host.onYip()
    setTimeout(() => {
      if (this.closeToken !== token) return
      this.position = { ...dest }
      this.restY = dest.y > this.groundY + 30 ? dest.y : null
      this.perchX = dest.x
      this.squash = 0.7
      this.emit('star', 4, Stage.p(94, Design.ground), 34)
      this.host.onTapSound()
      this.setAct('idle', 3)
      done()
    }, (0.22 + this.leapDur) * 1000)
  }

  tapTheButton(token, done) {
    this.setAct('tap', TAP_DURATION)
    this.moodOverride = { emotion: 'alert', until: now() + TAP_DURATION }
    const target = Stage.p(128, 124)
    const pressAt = TAP_DURATION * 0.5
    this.look = { dx: 0.85, dy: 0.2 }
    const later = (s, fn) => setTimeout(() => { if (this.closeToken === token) fn() }, s * 1000)
    later(pressAt * 0.35, () => { this.closeButtonAt = target })
    later(pressAt, () => {
      this.closeButtonPressed = true
      this.host.onTapSound()
      this.emit('sparkle', 5, target, 26); this.emit('star', 3, target, 18)
    })
    later(pressAt + 0.18, () => { this.closeButtonPressed = false; this.closeButtonAt = null; this.host.onCloseReelsTab() })
    later(TAP_DURATION + 0.35, done)
  }

  celebrateAndGoHome(token) {
    if (this.closeToken !== token || !this.closing) return
    this.setAct('dance', 2)
    setTimeout(() => {
      if (this.closeToken !== token) return
      if (!this.homeSpot) { this.closing = false; return }
      const dest = { x: this.homeSpot.x, y: this.homeOnFloor ? this.groundY : this.homeSpot.y }
      this.leap(dest, token, () => { this.closing = false; this.homeSpot = null })
    }, 1300)
  }

  cancelCloseSequence() {
    this.closeToken++
    this.closing = false
    this.closeButtonAt = null
    this.closeButtonPressed = false
  }

  // ------------------------------------------------------------------ rewards

  addXP(amount) {
    if (!(amount > 0)) return
    const before = this.level
    this.xp += amount
    if (this.level > before) this.celebrateLevelUp(this.level)
  }

  celebrateLevelUp(newLevel) {
    this.setAct('love', 4)
    this.say(Dlg.line('levelUp', this.species, { n: String(newLevel) }, this.name), null, 5)
    this.moodOverride = { emotion: 'proud', until: now() + 4 }
    this.emit('star', 10, Stage.aura, 70); this.emit('sparkle', 10, Stage.aura, 60); this.emit('heart', 6, Stage.aura, 40)
    this.happiness = min(1, this.happiness + 0.2)
    this.host.onYip()
    if (collarLevels.includes(newLevel)) {
      const name = collarName(collarTier(newLevel))
      setTimeout(() => {
        this.say(Dlg.line('newCollar', this.species, { item: name }, this.name), 'blissful', 5)
        this.emit('sparkle', 12, Stage.head, 50)
        this.host.onYip()
      }, 5000)
    }
  }

  addBerries(amount) {
    this.berryRemainder += amount
    const whole = Math.trunc(this.berryRemainder)
    if (whole > 0) { this.berries += whole; this.berryRemainder -= whole }
  }

  // ------------------------------------------------------------------ speech and particles

  stayPut() {
    if (this.act !== 'walk' || this.calledOver) return
    this.walkTarget = null
    this.setAct('idle', rand(2, 5))
  }

  say(text, mood = null, seconds = 3.5) {
    this.bubbleText = text
    this.bubbleUntil = now() + seconds
    if (mood) this.moodOverride = { emotion: mood, until: now() + seconds }
  }

  emit(kind, count, at, spread = 24) {
    for (let i = 0; i < count; i++) {
      const vx = rand(-spread, spread)
      let vy, life = rand(0.9, 1.7), size = rand(12, 20)
      switch (kind) {
        case 'heart': vy = rand(-70, -34); size = rand(13, 23); break
        case 'zzz': vy = -26; life = 2.6; size = rand(15, 22); break
        case 'sparkle': vy = rand(-60, -10); size = rand(9, 16); break
        case 'crumb': vy = rand(-160, -70); size = rand(4, 7); life = 1.1; break
        case 'anger': vy = rand(-50, -20); size = rand(14, 20); life = 0.9; break
        case 'star': vy = rand(-90, -30); size = rand(10, 16); life = 0.8; break
        case 'note': vy = rand(-60, -30); size = rand(14, 20); break
        case 'sweat': vy = rand(-40, -10); size = 12; life = 0.8; break
        case 'bubble': vy = rand(-50, -22); size = rand(6, 13); life = 1.4; break
        case 'confetti': vy = rand(-190, -90); size = rand(6, 10); life = rand(1.6, 2.4); break
      }
      size *= 0.82
      this.particles.push({ id: this._pid++, kind, x: at.x + rand(-34, 34), y: at.y + rand(-14, 4), vx, vy, life, maxLife: life, size, rot: rand(-0.3, 0.3), spin: rand(-1.4, 1.4) })
    }
  }

  // ------------------------------------------------------------------ interactions

  petMe() {
    this.lastInteraction = now()
    this.petting = min(1, this.petting + 0.55)
    this.happiness = min(1, this.happiness + 0.045)
    this.affection = min(1, this.affection + 0.03)
    this.energy = min(1, this.energy + 0.004)
    this.emit('heart', 3, Stage.aura, 26)
    if (this.act === 'sleep') this.setAct('idle', 2)
    if (Math.random() < 0.32) {
      this.addXP(Award.petted)
      this.say(Dlg.line('petted', this.species, {}, this.name), 'love', 2.4)
      this.host.onYip()
    }
    this.moodOverride = { emotion: 'love', until: now() + 1.6 }
  }

  feed(treat = false) {
    if (this.act === 'carried') return
    this.lastInteraction = now()
    if (this.hunger >= 0.95) { this.say(Dlg.line('full', this.species, {}, this.name), 'bored', 2.5); return }
    this.treatsEaten += 1
    this.addXP(treat ? Award.treat : Award.fed)
    this.bowl = 1
    this.setAct('eat', treat ? 3.0 : 5.5)
    this.hunger = min(1, this.hunger + (treat ? 0.22 : 0.5))
    this.happiness = min(1, this.happiness + 0.12)
    this.affection = min(1, this.affection + 0.05)
    this.energy = min(1, this.energy + 0.08)
    this.say(Dlg.line(treat ? 'treat' : 'fed', this.species, {}, this.name), 'eating', 3)
    this.host.onMunch()
    this.emit('crumb', 8, Stage.mouth, 60)
    this.emit('heart', 2, Stage.aura, 20)
  }

  play() {
    if (this.act === 'carried') return
    this.lastInteraction = now()
    if (this.staying) { this.dance(); return }
    this.setAct('zoom', 7)
    this.walkTarget = rand(this.minX, this.maxX)
    this.speedMultiplier = 1
    this.happiness = min(1, this.happiness + 0.2)
    this.affection = min(1, this.affection + 0.05)
    this.addXP(Award.played)
    this.say(Dlg.line('play', this.species, {}, this.name), 'playful', 3)
    this.emit('sparkle', 10, Stage.body, 70)
    this.host.onYip()
  }

  // ------------------------------------------------------------------ looks

  chooseSpecies(kind) {
    if (kind === this.species) return
    this.species = kind
    this.coatIndex = this.prefs.coat(kind)
    this.prefs.set('species', kind)
    this.say(Dlg.line('switched', kind, {}, this.name), 'excited', 3)
    this.emit('sparkle', 10, Stage.head, 50)
    this.host.onYip()
  }
  chooseCoat(i) {
    if (i === this.coatIndex || !coatsOf(this.species)[i]) return
    this.coatIndex = i
    this.prefs.setCoat(this.species, i)
    this.say(Dlg.line('dressUp', this.species, {}, this.name), 'happy', 2.4)
    this.emit('sparkle', 6, Stage.head, 40)
  }
  rename(n) {
    n = n.trim().slice(0, 24)
    if (!n || n === this.name) return
    this.name = n
    this.prefs.set('petName', n)
    this.say(`I'm ${n}! ${speciesInfo(this.species).emoji}`, 'excited', 3)
    this.host.save()
  }

  owns(a) { return accPrice(a) === 0 || this.owned.has(a) }
  ownsDecor(d) { return this.owned.has('decor.' + d) }

  wear(a) {
    if (a === 'none') return
    const slot = accSlot(a)
    if (!this.owns(a)) { this.say(`that one's in the Sanctuary 🍓 ${accPrice(a)} berries`, 'shy', 2.8); return }
    if (this.outfit[slot] === a) {
      this.outfit[slot] = 'none'
      this.say(Dlg.line('undress', this.species, {}, this.name), 'neutral', 2.2)
    } else {
      this.outfit[slot] = a
      this.say(Dlg.line('dressUp', this.species, {}, this.name), 'happy', 2.8)
      this.emit('sparkle', 8, Stage.head, 44)
    }
    this.prefs.set('outfit', { ...this.outfit })
    this.checkBadges()
  }
  clearOutfit() {
    if (SLOTS.every((s) => this.outfit[s] === 'none')) return
    this.outfit = outfitOf()
    this.prefs.set('outfit', { ...this.outfit })
    this.say(Dlg.line('undress', this.species, {}, this.name), 'neutral', 2.2)
  }

  buy(a) {
    if (this.owns(a)) return true
    const price = accPrice(a)
    if (this.berries < price) { this.say(`you need ${price - this.berries} more berries 🍓 keep focusing!`, 'shy', 2.8); return false }
    this.berries -= price
    this.owned.add(a)
    this.celebratePurchase(accEmoji(a), accTitle(a))
    this.host.save()
    return true
  }
  buyDecor(d) {
    if (this.ownsDecor(d)) return true
    const price = decorPrice(d)
    if (this.berries < price) { this.say(`you need ${price - this.berries} more berries 🍓 keep focusing!`, 'shy', 2.8); return false }
    this.berries -= price
    this.owned.add('decor.' + d)
    if (decorIsAmbient(d)) for (const o of DECORS) if (decorIsAmbient(o)) this.decorOn.delete(o)      // one kind of weather at a time
    this.decorOn.add(d)
    this.prefs.set('decorOn', [...this.decorOn].sort())
    this.celebratePurchase(decorEmoji(d), decorTitle(d))
    this.host.save()
    return true
  }
  toggleDecor(d) {
    if (!this.ownsDecor(d)) return
    if (this.decorOn.has(d)) this.decorOn.delete(d)
    else {
      if (decorIsAmbient(d)) for (const o of DECORS) if (decorIsAmbient(o)) this.decorOn.delete(o)
      this.decorOn.add(d)
    }
    this.prefs.set('decorOn', [...this.decorOn].sort())
  }
  celebratePurchase(emoji, title) {
    this.host.onBell()
    this.say(`${emoji} ${title.toLowerCase()}!! it's mine now`, 'excited', 3)
    this.emit('confetti', 14, Stage.aura, 70)
    this.host.onYip()
  }

  // ------------------------------------------------------------------ mood check-in

  get needsCheckIn() { return this.prefs.get('dailyCheckIn') && !this.prefs.todayMood }
  setMood(m) {
    this.prefs.setTodayMood(m)
    this.currentMood = m
    this.moods[dayKey()] = m
    this.addBerries(5)
    this.host.onBell()
    this.lastInteraction = now()
    this.say(moodReply(m, this.species), m === 'stressed' || m === 'tired' ? 'cozy' : 'happy', 5)
    this.emit('heart', 5, Stage.aura, 34)
    if (m === 'stressed') this.comeHere()
    this.host.onYip()
    this.host.save()
  }

  // ------------------------------------------------------------------ music

  /** Called on each beat of the music she's listening to: she nods her head along. */
  beat(strength) {
    if (this.act === 'carried' || this.act === 'sleep') return
    this.bop = max(this.bop, min(1, strength))
    this.bopUntil = now() + 3
    if (this.act === 'idle' && now() > this.actUntil - 0.2) this.setAct('sit', 3)
    if (Math.random() < 0.12) this.emit('note', 1, Stage.aura, 30)
  }
  updateMusicBop() {
    const b = this.host.musicBeat()
    if (b === null) { this.lastMusicBeat = -1; return }
    if (b === this.lastMusicBeat) return
    this.lastMusicBeat = b
    this.beat(b % 4 === 0 ? 0.95 : 0.55)
  }

  get ambiencePlaying() {
    return this.ambience !== 'off' && !this.ambienceHushed && (this.focusTimerRunning || this.ambienceManual)
  }
  chooseAmbience(a) {
    this.ambience = a
    this.prefs.set('ambience', a)
    this.ambienceManual = a !== 'off'
    this.ambienceHushed = false
    this.refreshAmbience()
  }
  toggleAmbienceNow() {
    if (this.ambiencePlaying) { this.ambienceManual = false; this.ambienceHushed = true }
    else {
      if (this.ambience === 'off') { this.ambience = 'lofi'; this.prefs.set('ambience', 'lofi') }
      this.ambienceManual = true; this.ambienceHushed = false
    }
    this.refreshAmbience()
  }
  /** The header's quick-mute: silences her voice (barks, purrs, clicks). The music keeps its own play button. */
  toggleMute() {
    this.prefs.toggle('sounds')
    if (this.prefs.get('sounds')) this.host.onClick()
  }
  refreshAmbience() { this.host.setAmbience(this.ambience, this.ambiencePlaying, this.prefs.get('ambienceVolume')) }

  // ------------------------------------------------------------------ misc interactions

  chooseSize(level) {
    if (level === this.sizeLevel) return
    this.sizeLevel = level
    Stage.setScale(SCALES[clamp(level, 0, 2)])
    this.prefs.set('sizeLevel', level)
    this.position.y = this.groundY
    this.say(['tiny but mighty 🐾', 'perfect 🐾', 'BIG energy 💪'][clamp(level, 0, 2)], 'happy', 2.2)
    this.host.sizeChanged()
  }
  toggleStay() {
    this.staying = !this.staying
    this.prefs.set('stay', this.staying)
    if (this.staying) {
      this.walkTarget = null; this.followUntil = 0
      this.say(Dlg.line('stay', this.species, {}, this.name), 'happy', 2.8)
      this.setAct('sit', 4)
    } else {
      this.say(Dlg.line('unstay', this.species, {}, this.name), 'excited', 2.6)
      this.setAct('idle', 1)
    }
    this.host.onYip()
  }
  dance() {
    if (this.act === 'carried' || this.act === 'sleep') return
    this.lastInteraction = now()
    this.walkTarget = null
    this.setAct('dance', 6)
    this.say(Dlg.line('dance', this.species, {}, this.name), 'happy', 3)
    this.happiness = min(1, this.happiness + 0.1)
    this.affection = min(1, this.affection + 0.03)
    this.emit('sparkle', 6, Stage.aura, 50)
    this.host.onYip()
  }
  wave() {
    if (this.act !== 'idle' && this.act !== 'sit') return
    this.setAct('wave', 2.6)
    this.say(Dlg.line('wave', this.species, {}, this.name), 'happy', 2.4)
  }
  nap() { this.setAct('sleep', 60); this.say(Dlg.line('sleepy', this.species, {}, this.name), 'sleepy', 3) }
  comeHere() {
    if (this.act === 'carried') return
    this.lastInteraction = now()
    this.calledOver = true
    this.followUntil = now() + 8
    if (this.act === 'sleep') this.setAct('idle', 1)
    this.say(Dlg.line('comeHere', this.species, {}, this.name), 'excited', 2.5)
    this.host.onYip()
  }
  follow() {
    const dx = this.cursor.x - this.position.x
    const side = dx >= 0 ? -1 : 1
    if (abs(dx) > 110) {
      this.walkTarget = min(max(this.cursor.x + side * 70, this.minX), this.maxX)
      this.speedMultiplier = 2.4
      if (this.act !== 'walk') this.setAct('walk', 30)
    } else {
      if (this.act === 'walk') {
        this.walkTarget = null
        if (this.calledOver) {
          this.calledOver = false
          this.say(Dlg.line('arrived', this.species, {}, this.name), null, 2.4)
          this.moodOverride = { emotion: 'shy', until: now() + 2.2 }
          this.emit('heart', 3, Stage.aura, 26)
        }
      }
      if (this.act !== 'sit') this.setAct('sit', 2); else this.actUntil = now() + 1
      this.facing = dx >= 0 ? 1 : -1
    }
    if (this.prefs.get('placeAnywhere')) {
      const y = this.clampY(this.cursor.y - 26)
      this.restY = y > this.groundY + 30 ? y : null
      this.perchX = this.position.x
    }
  }
  beginCarry() {
    this.cancelCloseSequence()
    this.lastInteraction = now()
    this.setAct('carried', 999)
    this.say(Dlg.line('picked', this.species, {}, this.name), 'dizzy', 1.6)
    this.host.onYip()
  }
  carry(p) {
    const sc = this.screens.find((r) => p.x >= r.minX && p.x <= r.maxX) || this.screen
    const lo = sc.minY + 2
    const hi = max(lo, sc.maxY - Design.height * this.scale + 40)
    this.position = { x: p.x, y: min(max(p.y, lo), hi) }
    this.act = 'carried'
  }
  drop(v = { x: 0, y: 0 }) {
    if (this.prefs.get('placeAnywhere')) {
      const y = this.clampY(this.position.y)
      if (y > this.groundY + 30) {
        this.restY = y; this.perchX = this.position.x; this.position.y = y
        this.velocity = { x: 0, y: 0 }
        this.setAct('idle', 1.6)
        this.squash = 0.4
        this.emit('sparkle', 6, Stage.p(94, Design.ground), 36)
        this.say(Dlg.line('placed', this.species, {}, this.name), 'happy', 2.4)
        this.host.onYip()
        return
      }
    }
    this.restY = null
    this.velocity = { x: max(-500, min(500, v.x)), y: max(-900, min(500, v.y)) }
    this.setAct('fall', 99)
    this.happiness = max(0, this.happiness - 0.01)
  }

  // ------------------------------------------------------------------ focus timer

  startTimer(minutes, isBreak = false) {
    this.timerTotal = minutes * 60
    this.timerEndsAt = now() + this.timerTotal
    this.timerIsBreak = isBreak
    this.lastTimerNudge = now()
    if (isBreak) {
      this.say(Dlg.line('breakStart', this.species, {}, this.name), 'playful', 5)
      this.setAct('sit', 20)
    } else {
      this.resetFocusStreak()
      this.ambienceHushed = false
      this.say(Dlg.line('timerStart', this.species, { n: String(Math.trunc(minutes)) }, this.name), 'alert', 5)
      this.setAct('sit', 20)
    }
    this.refreshAmbience()
    this.host.onYip()
    this.host.save()
  }
  startFocus(minutes, intention = '') { this.intention = intention; this.startTimer(minutes) }
  stopTimer() {
    if (this.timerEndsAt === null) return
    const wasBreak = this.timerIsBreak
    this.timerEndsAt = null; this.timerIsBreak = false
    this.say(wasBreak ? Dlg.line('breakOver', this.species, {}, this.name) : 'timer stopped… we\'ll go again soon 🥺', wasBreak ? 'happy' : 'sad', 3)
    this.refreshAmbience()
    this.host.save()
  }
  updateTimer() {
    if (this.timerEndsAt === null) return
    const left = this.timerEndsAt - now()
    if (left <= 0) { this.finishTimer(); return }
    if (!this.timerIsBreak && left > 70 && now() - this.lastTimerNudge > 300) {
      this.lastTimerNudge = now()
      this.say(`${Math.ceil(left / 60)} min left — still with me? 💗`, 'love', 4)
      this.emit('heart', 3, Stage.aura, 22)
    }
  }
  finishTimer() {
    const wasBreak = this.timerIsBreak
    const minutes = Math.trunc(this.timerTotal / 60)
    this.timerEndsAt = null; this.timerIsBreak = false
    this.refreshAmbience()
    if (wasBreak) {
      this.say(Dlg.line('breakOver', this.species, {}, this.name), 'excited', 5)
      this.setAct('idle', 2)
      this.host.onYip()
      this.host.save()
      return
    }
    const today = dayKey()
    this.dailySessions[today] = (this.dailySessions[today] || 0) + 1
    this.addBerries(10)
    this.checkBadges()
    this.happiness = min(1, this.happiness + 0.25)
    this.affection = min(1, this.affection + 0.15)
    this.addXP(Award.timerFinished)
    this.emit('confetti', 16, Stage.aura, 80)
    this.setAct('love', 6)
    this.say(Dlg.line('timerDone', this.species, { n: String(minutes) }, this.name), null, 7)
    this.moodOverride = { emotion: 'proud', until: now() + 3.5 }
    this.emit('heart', 12, Stage.aura, 60); this.emit('sparkle', 8, Stage.aura, 70)
    this.host.onYip()
    this.host.sessionFinished?.(minutes)
    this.host.save()
    // roll straight into a short break so the rhythm keeps going
    setTimeout(() => { if (this.timerEndsAt === null) this.startTimer(5, true) }, 7000)
  }

  // ------------------------------------------------------------------ focus coaching

  /** Looks at one moment of your day. `dt` is how many seconds actually passed since the last look
   *  (zero straight after a sleep or a stall, so a closed laptop never earns focus), `idle` is how
   *  long since you last touched the keyboard or mouse. Being away only stops the *good* time
   *  counting: a distraction still counts, because staring at a reel without touching anything is
   *  exactly the thing she's here to catch. */
  observe(v, dt, idle = 0) {
    if (!(dt > 0)) return
    const grace = this.focusTimerRunning ? 300 : 150
    const resting = idle > grace && v.kind !== 'distraction'
    this.presenceNote = resting ? `resting: no keys or mouse for ${Math.trunc(idle / 60)} min` : ''
    const credit = resting ? 0 : dt
    const today = dayKey()

    this.currentActivity = v.label
    this.lastVerdict = v.kind
    if (v.kind !== 'neutral' && v.siteKey) this.siteTime[v.siteKey] = (this.siteTime[v.siteKey] || 0) + credit
    const cat = v.ruleName === '—' ? 'Other' : v.ruleName
    this.categoryTime[cat] = (this.categoryTime[cat] || 0) + credit
    if (v.siteKey) {
      const day = (this.dailyAppTime[today] ||= {})
      day[v.siteKey] = (day[v.siteKey] || 0) + credit
      this.siteKinds[v.siteKey] = v.kind
    }
    if (resting) this.dailyAway[today] = (this.dailyAway[today] || 0) + dt
    if (resting && v.kind === 'work') return

    switch (v.kind) {
      case 'distraction': {
        this.focusSeconds = 0
        if (this.onBreak) { this.distractSeconds = 0; return }
        if (this.prefs.inQuietHours) { this.distractSeconds = 0; return }
        this.distractSeconds += dt
        this.dailyDistraction[today] = (this.dailyDistraction[today] || 0) + dt
        this.wasDistracted = true
        const vibe = Dlg.VIBES[Dlg.effectiveVibe(this.prefs)]
        const r = { ...v, delay: v.delay * vibe.patience }
        if (Dlg.effectiveVibe(this.prefs) === 'gentle') r.severity = 1
        if (Dlg.effectiveVibe(this.prefs) === 'drill') r.severity = 2
        if (this.focusTimerRunning) {
          r.delay = max(6, r.delay * 0.4)
          if (Dlg.effectiveVibe(this.prefs) !== 'gentle') r.severity = max(2, r.severity)
        }
        if (this.distractSeconds > r.delay && now() >= this.nextScold) this.scold(r)
        break
      }
      case 'work': {
        if (this.wasDistracted && this.distractSeconds > 12) {
          this.say(Dlg.coach('backToWork', this.species, this.prefs), 'happy', 4)
          this.emit('sparkle', 8, Stage.aura, 40)
          this.happiness = min(1, this.happiness + 0.08)
          this.host.onYip()
        }
        this.wasDistracted = false
        this.distractSeconds = 0
        this.scoldCount = 0
        this.nextScold = 0
        this.focusSeconds += dt
        this.creditFocus(dt)
        if (this.focusSeconds >= this.nextMilestone) {
          this.adore(Math.trunc(this.nextMilestone / 60))
          this.nextMilestone += this.nextMilestone < 1800 ? 900 : 1800
        } else if (now() - this.lastPraise > 210 && this.act === 'idle') {
          this.lastPraise = now()
          this.say(Dlg.praise(v.ruleName, v.lines, this.species, this.prefs), 'love', 4)
          this.emit('heart', 3, Stage.aura, 22)
        }
        break
      }
      default:
        this.distractSeconds = max(0, this.distractSeconds - dt * 0.7)
        this.focusSeconds = max(0, this.focusSeconds - dt * 0.25)
        // a session you started is focus, even in an app no rule knows (a PDF, a notes app). Only while
        // you're really there, and never on a break.
        if (this.focusTimerRunning && !resting) this.creditFocus(dt)
    }
  }

  /** One place that turns seconds of real focus into minutes in every total: lifetime, today, the hour of
   *  day it happened in, plus the XP, berries and goal/streak checks that go with it. */
  creditFocus(dt) {
    const today = dayKey()
    this.totalFocusMinutes += dt / 60
    this.dailyFocus[today] = (this.dailyFocus[today] || 0) + dt / 60
    const hour = new Date().getHours()
    this.focusByHour[hour] = (this.focusByHour[hour] || 0) + dt / 60
    this.affection = min(1, this.affection + dt / 3600)
    if (this.lastXPDay !== today) { this.lastXPDay = today; this.addXP(Award.dailyFirstFocus) }
    const flow = this.inFlow ? 1.5 : 1
    this.addXP(Award.focusMinute * flow * dt / 60)
    this.addBerries(flow * dt / 60)
    this.checkGoalAndStreak()
  }

  scold(v) {
    this.barksGiven += 1
    const today = dayKey()
    this.dailyBarks[today] = (this.dailyBarks[today] || 0) + 1
    this.scoldCount += 1
    this.setAct('bark', v.severity >= 2 ? 3.4 : 2.4)
    this.walkTarget = null
    this.happiness = max(0, this.happiness - 0.03)
    const line = Dlg.scold(v.ruleName, v.lines, this.species, this.scoldCount, this.prefs)
    this.say(line, 'angry', v.severity >= 2 ? 5 : 4)
    this.emit('anger', v.severity >= 2 ? 6 : 3, Stage.aura, 45)
    if (v.severity >= 2) this.host.onBark(); else this.host.onWhine()
    // one warning bark first, then, if it's still a Reels tab and she hasn't been left alone, she closes it herself
    if (this.scoldCount === 2 && this.prefs.get('autoCloseReels') && SHORT_FORM.includes(v.ruleName)) {
      setTimeout(() => this.performCloseTap(), 1100)
    }
    const gap = max(25, 55 - this.scoldCount * 10) * Dlg.VIBES[Dlg.effectiveVibe(this.prefs)].gap
    this.nextScold = now() + gap
  }

  adore(minutes) {
    this.setAct('love', 5)
    this.happiness = min(1, this.happiness + 0.15)
    this.affection = min(1, this.affection + 0.12)
    this.say(Dlg.line('milestone', this.species, { n: String(minutes) }, this.name), 'love', 6)
    this.emit('heart', 10, Stage.aura, 55); this.emit('sparkle', 6, Stage.body, 60)
    this.host.onYip()
  }
  resetFocusStreak() { this.focusSeconds = 0; this.nextMilestone = 10 * 60 }
  noteScreenOff() { this.presenceNote = 'paused: screen is locked' }

  // ------------------------------------------------------------------ daily goal, streak and history

  get focusTodayMinutes() { return this.dailyFocus[dayKey()] || 0 }
  get goalProgress() { return min(1, this.focusTodayMinutes / max(1, this.dailyGoal)) }
  get sessionsToday() { return this.dailySessions[dayKey()] || 0 }
  get streakDays() {
    let day = dayKey()
    if ((this.dailyFocus[day] || 0) < 5) day = addDays(day, -1)
    let n = 0
    while ((this.dailyFocus[day] || 0) >= 5) { n += 1; day = addDays(day, -1) }
    return n
  }
  get bestStreakDays() {
    let best = 0, run = 0, prev = null
    for (const d of Object.keys(this.dailyFocus).filter((k) => this.dailyFocus[k] >= 5).sort()) {
      run = prev && addDays(prev, 1) === d ? run + 1 : 1
      best = max(best, run)
      prev = d
    }
    return best
  }
  get mostFocusInADay() { return max(0, ...Object.values(this.dailyFocus)) }
  get daysAtGoal() { return Object.values(this.dailyFocus).filter((v) => v >= this.dailyGoal).length }
  get totalSessions() { return Object.values(this.dailySessions).reduce((a, b) => a + b, 0) }
  get totalTasksDone() { return Object.values(this.dailyTasks).reduce((a, b) => a + b, 0) }
  get angelDays() { return Object.entries(this.dailyFocus).filter(([d, v]) => v >= 60 && !(this.dailyBarks[d] || 0)).length }

  setGoal(minutes) { this.dailyGoal = clamp(minutes, 10, 480); this.prefs.set('dailyGoal', this.dailyGoal) }

  checkGoalAndStreak() {
    const today = dayKey()
    if (now() - this.lastBadgeCheck > 45) { this.checkBadges(); this.autoCompleteHabits(); this.noteTimeOfDay() }
    if (this.focusTodayMinutes >= 5 && this.streakAnnouncedDay !== today) {
      this.streakAnnouncedDay = today
      const n = this.streakDays
      if (n >= 2) {
        this.say(Dlg.line('streak', this.species, { n: String(n) }, this.name), 'proud', 4.5)
        this.emit('sparkle', 8, Stage.aura, 50)
      }
    }
    if (this.focusTodayMinutes >= this.dailyGoal && this.prefs.get('goalDay') !== today) {
      this.prefs.set('goalDay', today)
      this.setAct('love', 6)
      this.say(Dlg.line('goalDone', this.species, { n: timeText(this.dailyGoal) }, this.name), null, 7)
      this.moodOverride = { emotion: 'proud', until: now() + 4 }
      this.emit('confetti', 24, Stage.aura, 100); this.emit('heart', 8, Stage.aura, 60)
      this.addXP(30); this.addBerries(25)
      this.host.onYip()
    }
  }

  // ------------------------------------------------------------------ badges and habits

  /** Awards any badge whose milestone has been reached. The very first check counts what you'd
   *  already done, quietly, so nothing old is announced in a pile. */
  checkBadges() {
    this.lastBadgeCheck = now()
    const earned = this.prefs.badgeSet
    const fresh = BADGES.filter((b) => !earned.has(b.id) && badgeEarned(b, this))
    if (!fresh.length) { this.prefs.set('badgesSeeded', true); return }
    fresh.forEach((b) => earned.add(b.id))
    this.prefs.set('badges', [...earned].sort())
    const seeded = this.prefs.get('badgesSeeded')
    this.prefs.set('badgesSeeded', true)
    if (!seeded) return
    this.addBerries(15 * fresh.length)
    const b = fresh[0]
    this.setAct('love', 4)
    this.say(`new badge ${b.emoji} ${b.title}!${fresh.length > 1 ? ` (+${fresh.length - 1} more!)` : ''}`, 'proud', 5.5)
    this.host.onBell()
    this.emit('confetti', 18, Stage.aura, 80)
    this.host.onYip()
    fresh.forEach((badge, i) => setTimeout(() => this.host.onBadge(badge), i * 5500))
  }

  get habitsDone() { return new Set(this.prefs.get('habits')[dayKey()] || []) }
  toggleHabit(id) {
    const done = this.habitsDone
    if (done.has(id)) { done.delete(id); this.saveHabits(done); return }
    this.completeHabit(id)
  }
  saveHabits(set) { this.prefs.set('habits', { ...this.prefs.get('habits'), [dayKey()]: [...set].sort() }) }
  completeHabit(id) {
    const done = this.habitsDone
    const h = HABITS.find((x) => x.id === id)
    if (done.has(id) || !h) return
    done.add(id)
    this.saveHabits(done)
    this.addXP(HABIT_XP)
    this.addBerries(HABIT_BERRIES)
    this.host.onBell()
    this.emit('sparkle', 6, Stage.aura, 44)
    if (done.size === HABITS.length) {
      this.prefs.set('perfectHabitDays', this.prefs.get('perfectHabitDays') + 1)
      this.addBerries(HABIT_BONUS)
      this.setAct('love', 4)
      this.emit('confetti', 16, Stage.aura, 80)
      this.say(`every little habit done 🌷 that's +${HABIT_BONUS} 🍓 just for taking care of you`, 'proud', 6)
      this.checkBadges()
    } else {
      this.say(`${h.emoji} ${h.title.toLowerCase()}, done! +${HABIT_XP} xp`, 'happy', 3)
    }
    this.host.save()
  }
  autoCompleteHabits() {
    for (const h of HABITS) if (h.auto && !this.habitsDone.has(h.id) && h.auto(this)) this.completeHabit(h.id)
  }
  noteTimeOfDay() {
    const h = new Date().getHours()
    if (h >= 5 && h < 8 && !this.prefs.get('earlyBird')) this.prefs.set('earlyBird', true)
    if ((h >= 23 || h < 4) && !this.prefs.get('nightOwl')) this.prefs.set('nightOwl', true)
  }

  // ------------------------------------------------------------------ to-dos

  addTask(title) {
    const t = title.trim()
    if (!t || this.tasks.length >= 40) return
    this.tasks.push({ id: uuid(), title: t.slice(0, 80), done: false, created: Date.now() })
    this.host.save()
  }
  toggleTask(id) {
    const task = this.tasks.find((t) => t.id === id)
    if (!task) return
    task.done = !task.done
    const today = dayKey()
    this.dailyTasks[today] = max(0, (this.dailyTasks[today] || 0) + (task.done ? 1 : -1))
    this.host.save()
    if (!task.done) return
    this.lastInteraction = now()
    this.addXP(Award.task)
    this.addBerries(3)
    this.host.onBell()
    this.emit('sparkle', 6, Stage.aura, 40)
    this.host.onYip()
    if (this.tasks.every((t) => t.done) && this.tasks.length >= 2) {
      this.setAct('love', 4)
      this.say(Dlg.line('allDone', this.species, {}, this.name), null, 5)
      this.emit('confetti', 20, Stage.aura, 90)
    } else this.say(Dlg.line('taskDone', this.species, {}, this.name), 'proud', 2.6)
    this.checkBadges()
  }
  removeTask(id) { this.tasks = this.tasks.filter((t) => t.id !== id); this.host.save() }
  clearDoneTasks() { this.tasks = this.tasks.filter((t) => !t.done); this.host.save() }

  // ------------------------------------------------------------------ gentle reminders

  updateReminders() {
    const t = now()
    if (t - this.lastReminderCheck <= 5) return
    this.lastReminderCheck = t
    if (!this.prefs.get('reminders') || this.prefs.inQuietHours || this.act === 'sleep' || this.act === 'carried' || this.bubbleText) return
    if (t - this.lastWater > 50 * 60) {
      this.lastWater = t
      this.say(Dlg.line('water', this.species, {}, this.name), 'happy', 5)
      this.emit('bubble', 5, Stage.aura, 30)
      this.host.onYip()
    } else if (t - this.lastStretch > 40 * 60) {
      this.lastStretch = t
      this.say(Dlg.line('stretchRemind', this.species, {}, this.name), 'happy', 5)
      if (!this.focusTimerRunning) this.setAct('stretch', 2.6)
      this.host.onYip()
    } else if (this.focusTimerRunning && t - this.lastEyes > 20 * 60) {
      this.lastEyes = t
      this.say(Dlg.line('eyes', this.species, {}, this.name), 'happy', 5)
      this.host.onYip()
    }
  }

  humanIsAway(away) {
    if (away && this.act !== 'sleep' && this.act !== 'carried') this.setAct('sleep', 300)
    else if (!away && this.act === 'sleep' && this.energy > 0.35) {
      this.lastWater = now(); this.lastStretch = now(); this.lastEyes = now()
      this.setAct('wave', 2.6)
      this.say(Dlg.line('wokeUp', this.species, {}, this.name), 'excited', 3)
    }
  }

  // ------------------------------------------------------------------ saving

  snapshot() {
    return {
      name: this.name, hunger: this.hunger, happiness: this.happiness, energy: this.energy, affection: this.affection,
      totalFocusMinutes: this.totalFocusMinutes, treatsEaten: this.treatsEaten, barksGiven: this.barksGiven, born: this.born,
      lastSeen: Date.now(), siteTime: this.siteTime, dailyFocus: this.dailyFocus, categoryTime: this.categoryTime, xp: this.xp,
      lastXPDay: this.lastXPDay, dailyAppTime: this.dailyAppTime,
      timerEndsAt: this.timerEndsAt === null ? null : this.timerEndsAt * 1000, timerIsBreak: this.timerIsBreak, timerTotal: this.timerTotal,
      tasks: this.tasks, dailySessions: this.dailySessions, dailyDistraction: this.dailyDistraction, dailyBarks: this.dailyBarks,
      dailyTasks: this.dailyTasks, berries: this.berries, owned: [...this.owned], moods: this.moods,
      dailyAway: this.dailyAway, focusByHour: this.focusByHour, siteKinds: this.siteKinds,
    }
  }

  /** Each field on its own, so adding a field later never costs anyone their save, and a field of the wrong kind
   *  (a hand-edited or damaged file) is ignored instead of poisoning the sums that read it later. */
  restore(s = {}) {
    const num = (v, d) => (typeof v === 'number' && Number.isFinite(v) ? v : d)
    const map = (v) => (v && typeof v === 'object' && !Array.isArray(v) ? v : {})
    this.name = this.prefs.get('petName')
    this.hunger = num(s.hunger, 0.85); this.happiness = num(s.happiness, 0.8)
    this.energy = num(s.energy, 0.9); this.affection = num(s.affection, 0.5)
    this.totalFocusMinutes = num(s.totalFocusMinutes, 0); this.treatsEaten = num(s.treatsEaten, 0); this.barksGiven = num(s.barksGiven, 0)
    this.born = num(s.born, Date.now())
    this.siteTime = map(s.siteTime); this.dailyFocus = map(s.dailyFocus); this.categoryTime = map(s.categoryTime)
    this.xp = num(s.xp, 0); this.lastXPDay = typeof s.lastXPDay === 'string' ? s.lastXPDay : ''; this.dailyAppTime = map(s.dailyAppTime)
    this.tasks = Array.isArray(s.tasks) ? s.tasks.filter((t) => t && typeof t.title === 'string') : []
    this.dailySessions = map(s.dailySessions); this.dailyDistraction = map(s.dailyDistraction)
    this.dailyBarks = map(s.dailyBarks); this.dailyTasks = map(s.dailyTasks)
    this.owned = new Set(Array.isArray(s.owned) ? s.owned : []); this.moods = map(s.moods)
    this.dailyAway = map(s.dailyAway); this.focusByHour = map(s.focusByHour); this.siteKinds = map(s.siteKinds)
    // a welcome gift, plus a berry for every focused minute you'd already put in
    this.berries = typeof s.berries === 'number' ? s.berries : 40 + Math.trunc(this.totalFocusMinutes)
    // a timer still genuinely running resumes where it was; one that finished while closed is dropped
    if (s.timerEndsAt && s.timerEndsAt > Date.now()) {
      this.timerEndsAt = s.timerEndsAt / 1000; this.timerIsBreak = !!s.timerIsBreak; this.timerTotal = num(s.timerTotal, 0)
    }
    // she's been alone while the app was closed: a little hungrier, a little sleepier
    const away = clamp((Date.now() - num(s.lastSeen, Date.now())) / 1000, 0, 60 * 60 * 12)
    this.hunger = max(0.1, this.hunger - away / (60 * 60 * 6))
  }
}

export function timeText(minutes) {
  const m = Math.round(minutes)
  if (m < 60) return `${m}m`
  const h = Math.floor(m / 60), r = m % 60
  return r === 0 ? `${h}h` : `${h}h ${r}m`
}

/** What the pet needs from the machine she runs on. The app replaces every one of these. */
export class NullHost {
  screens() { return [{ minX: 0, maxX: 1440, minY: 0, maxY: 860 }] }
  windowSpot() { return null }
  reduceMotion() { return false }
  musicBeat() { return null }
  setAmbience() {}
  sizeChanged() {}
  save() {}
  onBark() {} onYip() {} onBell() {} onMunch() {} onWhine() {} onClick() {} onTapSound() {}
  onCloseReelsTab() {}
  onBadge() {}
}

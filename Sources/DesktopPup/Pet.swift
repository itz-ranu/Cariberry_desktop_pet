import AppKit
import SwiftUI

// MARK: - Scene geometry

/// The window is bigger than the pet so speech bubbles and particles have room.
enum Stage {
    static let size = CGSize(width: 270, height: 236)

    /// Settings ▸ Pets ▸ Size. Medium is about a quarter smaller than the original
    /// scale: she should keep you company, not take over the bottom of the screen.
    static let scales: [CGFloat] = [0.42, 0.52, 0.68]
    static let sizeNames = ["Small", "Medium", "Large"]
    /// Mutated only by `Pet.sizeLevel`, which is the single place that changes it.
    nonisolated(unsafe) static var dogScale: CGFloat = scales[1]

    static var dogOrigin: CGPoint {
        CGPoint(x: (size.width - Design.width * dogScale) / 2,
                y: size.height - Design.height * dogScale)
    }
    /// Convert a point in the pet's art space to scene (view) coordinates.
    static func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: dogOrigin.x + x * dogScale, y: dogOrigin.y + (y + Design.lift) * dogScale)
    }
    static var head: CGPoint { p(122, 50) }
    /// Where mood particles are born: just above the ears, clear of the face.
    static var aura: CGPoint { p(124, -14) }
    static var body: CGPoint { p(86, 110) }
    static var mouth: CGPoint { p(150, 84) }
    /// How far the paws sit above the bottom edge of the window.
    static var pawInset: CGFloat { size.height - (dogOrigin.y + (Design.ground + Design.lift) * dogScale) }
    /// Region of the window that swallows clicks: everything else falls through
    /// to whatever is underneath. In AppKit coordinates (origin bottom-left).
    static var hitRect: CGRect {
        let pad: CGFloat = 8
        let left = dogOrigin.x + 30 * dogScale - pad
        let right = dogOrigin.x + 178 * dogScale + pad
        let topDown = dogOrigin.y + 2 * dogScale                // top of the (tallest) ears
        let bottomDown = dogOrigin.y + (Design.ground + Design.lift) * dogScale
        return CGRect(x: left,
                      y: size.height - bottomDown - pad,
                      width: right - left,
                      height: (bottomDown - topDown) + pad * 2)
    }
}

// MARK: - Particles

struct Particle: Identifiable {
    enum Kind { case heart, zzz, sparkle, crumb, anger, star, note, sweat, bubble, confetti }
    let id = UUID()
    var kind: Kind
    var pos: CGPoint
    var vel: CGVector
    var life: Double
    var maxLife: Double
    var size: Double
    var rot: Double = 0
    var spin: Double = 0
}

// MARK: - Activity verdicts (produced by ActivityMonitor)

enum ActivityKind { case work, distraction, neutral }

struct Verdict {
    var kind: ActivityKind
    var label: String          // "Instagram Reels", "Xcode", ... (page title when there is one)
    var siteKey: String        // stable grouping key for stats: domain, or app name
    var ruleName: String
    var delay: Double          // seconds of tolerance before the pup reacts
    var lines: [String]
    var severity: Int          // 1 = gentle nudge, 2 = full bark
}

// MARK: - The pup's brain

/// Ticks once per drawn frame. Only the pet's own canvas observes it, so a frame redraws
/// that canvas and nothing else (the rest of the scene only updates when something
/// visible actually changes).
final class FrameClock: ObservableObject {
    @Published var frame = 0
}

@MainActor
final class Pet: ObservableObject {
    let clock = FrameClock()
    /// True while any eased pose amount is still moving: needs smooth frames until it settles.
    /// A body amount (walk, sit, turn...) is still easing: needs smooth frames until it settles.
    private var blending = false
    /// Only her eyes are still easing toward the cursor: needs far fewer frames than a body move.
    private var lookBlending = false
    /// While the cursor is moving near her she keeps a lively pace, so she tracks it without lag.
    var attentionUntil: CFTimeInterval = 0

    enum Act: Equatable {
        case idle, walk, sit, sleep, eat, bark, love, zoom, carried, fall, scratch
        case leap     // the jump up to a browser window and back
        case stretch, sniff
        case dance, wave      // for fun: a little dance, and a hello wave
        case groom    // cat's signature move
        case tap      // reaching out to tap the Reels close button herself
    }

    // Vital stats, all 0...1. Deliberately NOT @Published: they change every animation
    // tick, and publishing them made SwiftUI re-lay-out the whole scene 30+ times a
    // second for nothing (it cost ~25% of a CPU core while she sat still). The control
    // panel and stats window re-read them on their own slow timers, and `touch()` below
    // refreshes them straight after you press something.
    var hunger: Double = 0.85       // 1 = full belly
    var happiness: Double = 0.8
    var energy: Double = 0.9
    var affection: Double = 0.5

    @Published var name: String = "Cariberry"
    @Published var species: Species = .cat
    @Published var coatIndex: Int = 0
    @Published var outfit = Outfit()
    /// "Stay": she sits where she is and doesn't wander until told she may.
    @Published var staying = false
    // The Sanctuary: berries are earned by focusing and spent on rugs, clothes and decor.
    var berries = 0
    var owned: Set<String> = []
    @Published var decorOn: Set<String> = []
    private var berryRemainder = 0.0
    // The mood journal, and the pulse of any music she's listening to.
    var moods: [Date: String] = [:]
    /// Today's mood, cached: `emotion` is read several times per frame, so it can't hit the
    /// preferences each time. Refreshed on check-in and every half minute (for midnight).
    private(set) var currentMood: Mood? = Prefs.todayMood
    private var lastMoodRefresh = Date()
    var bop = 0.0
    private var bopUntil = Date.distantPast
    private var danceAmt = 0.0, waveAmt = 0.0
    private var lastNote = Date.distantPast
    /// 0 = Small, 1 = Medium, 2 = Large: see `Stage.scales`.
    @Published var sizeLevel: Int = 1 {
        didSet { Stage.dogScale = Stage.scales[min(max(sizeLevel, 0), Stage.scales.count - 1)] }
    }
    var scale: CGFloat { Stage.scales[min(max(sizeLevel, 0), Stage.scales.count - 1)] }
    /// Set while the control panel is open so she stops wandering off from under it.
    var holdStill = false
    @Published private(set) var act: Act = .idle
    private(set) var phase: Double = 0
    @Published var facing: Double = 1
    var position: CGPoint = .zero              // paw centre, screen coords (y up)
    var squash: Double = 0
    var petting: Double = 0
    var look: CGVector = .zero
    var nearCursor: Bool = false               // your cursor is right next to her
    @Published var particles: [Particle] = []
    @Published var bubbleText: String? = nil
    @Published var bowl: Double = 0            // 0 = no bowl, else fullness
    /// Where the little close-button prop floats while she's tapping it, and
    /// whether it's mid-press right now. SceneView draws it; nil = not showing.
    @Published var closeButtonAt: CGPoint? = nil
    @Published var closeButtonPressed: Bool = false

    // focus coaching
    private(set) var focusSeconds: Double = 0
    private(set) var distractSeconds: Double = 0
    var totalFocusMinutes: Double = 0
    var currentActivity: String = "…"
    var lastVerdict: ActivityKind = .neutral
    var treatsEaten: Int = 0
    var barksGiven: Int = 0
    /// Lifetime XP. `level` is derived from it, never stored separately, so the two
    /// can't drift apart.
    var xp: Double = 0
    var lastXPDay: Date = .distantPast
    var born: Date = Date()
    var siteTime: [String: Double] = [:]   // domain/app -> seconds spent, lifetime
    var dailyFocus: [Date: Double] = [:]   // start-of-day -> minutes focused
    var categoryTime: [String: Double] = [:]   // rule name -> seconds, every kind included
    /// start-of-day -> domain/app -> seconds spent, *every* app she's watched you in,
    /// distraction or work or neither. This is the one that actually answers "what
    /// did I do all day": `siteTime` above only ever counted apps a rule recognised,
    /// so anything neutral (Finder, Mail, an app with no rule) was invisible.
    var dailyAppTime: [Date: [String: Double]] = [:]
    /// start-of-day -> seconds you sat at the computer without touching it. Shown as "away".
    var dailyAway: [Date: Double] = [:]
    /// hour of the day (0...23) -> lifetime minutes focused then: "you focus best around 3 PM".
    var focusByHour: [Int: Double] = [:]
    /// app/site -> "work" | "distraction" | "neutral", as she last saw it, so the stats can colour each app.
    var siteKinds: [String: String] = [:]

    // focus timer (pomodoro)
    @Published var timerEndsAt: Date?
    @Published var timerIsBreak = false
    // not private: App.swift/PetWindow.swift read and write this for persistence,
    // same as lastXPDay below, so a running focus timer survives a quit and relaunch
    // instead of silently vanishing
    var timerTotal: TimeInterval = 0
    private var lastTimerNudge: Date = .distantPast

    var moodOverride: (Emotion, Date)?
    private var bubbleUntil: Date = .distantPast
    private var actUntil: Date = .distantPast
    private var actStartedAt: Date = .distantPast
    private var walkTarget: CGFloat?
    private var velocity: CGVector = .zero
    private var nextScold: Date = .distantPast
    private var scoldCount = 0
    private var lastPraise: Date = .distantPast
    private var nextMilestone: Double = 10 * 60
    private var wasDistracted = false
    private var speedMultiplier: Double = 1
    private var lastInteraction: Date = Date()
    private var calledOver = false
    /// How long the reach-tap-retract animation takes, start to finish. `pose`
    /// divides `actElapsed` by this to get `tapPhase`, and `performCloseTap` times
    /// the button appearing/pressing off fractions of it, so this is the one place
    /// that governs the whole gesture's pacing.
    private let tapDuration: Double = 1.3

    // MARK: Focus state
    @Published var tasks: [FocusTask] = []
    @Published var dailySessions: [Date: Int] = [:]
    // per-day history for the stats window (plain, like the other stats: see the note above)
    var dailyDistraction: [Date: Double] = [:]
    var dailyBarks: [Date: Int] = [:]
    var dailyTasks: [Date: Int] = [:]
    private var lastBadgeCheck = Date.distantPast
    /// What she's working on right now: shown in her bubble and on the timer.
    @Published var intention: String = ""
    @Published var ambience: Ambience = .lofi
    /// The study sound was started by hand (rather than by a running timer).
    @Published var ambienceManual = false
    /// She was told to be quiet while a timer runs: stops the timer from restarting the music.
    @Published var ambienceHushed = false
    private var lastMusicBeat = -1
    /// Why focus time isn't counting right now ("" while it is): shown on the Home card.
    private(set) var presenceNote = ""
    /// You've been in uninterrupted flow for 20 minutes: XP and berries get a boost.
    var inFlow: Bool { focusSeconds >= 20 * 60 }
    @Published var dailyGoal: Int = Prefs.dailyGoal
    /// Set by the window controller so list edits are saved straight away.
    var onNeedsSave: (() -> Void)?
    /// Called when a badge is earned, so a little card can slide in.
    var onBadge: ((Badge) -> Void)?
    private var musicSecondsPending = 0.0
    private var streakAnnouncedDay: Date = .distantPast
    private var lastWater = Date(), lastStretch = Date(), lastEyes = Date()
    private var lastReminderCheck = Date()

    // MARK: Placement
    /// Screen y of her paws when she's been put somewhere above the floor; nil = the floor.
    var restY: CGFloat?
    /// Where she was put, so a wander stays near it instead of crossing the whole screen.
    var perchX: CGFloat = 0
    /// The cursor, in screen coordinates: refreshed every frame by the window controller.
    var cursor: CGPoint = .zero
    private var followUntil: Date = .distantPast
    var isFollowing: Bool { Date() < followUntil }

    // MARK: Props
    private var propKind: Prop = .none
    private var propAmt = 0.0

    // Eased animation amounts: see `updateBlends`. Pose reads them each frame.
    private(set) var gait: Double = 0
    private var gaitRate: Double = 10
    private var walkAmt = 0.0, runAmt = 0.0, sitAmt = 0.0, sleepAmt = 0.0
    private var stretchAmt = 0.0, sniffAmt = 0.0, groomAmt = 0.0, scratchAmt = 0.0
    private var facingVis: Double = 1

    var onBark: (() -> Void)?
    var onYip: (() -> Void)?
    var onBell: (() -> Void)?
    var onMunch: (() -> Void)?
    var onWhine: (() -> Void)?
    /// Settings ▸ Auto-close Reels tabs. Fired from `performCloseTap()` right as her
    /// paw lands on the button, after the reach animation has played. Pet has no
    /// direct access to AppleScript/ActivityMonitor, so this is wired up in
    /// App.swift the same way the sound hooks above are.
    var onCloseReelsTab: (() -> Void)?
    /// A little UI-click blip for the moment her paw lands on the close button.
    var onTapSound: (() -> Void)?

    /// Asks any open panel to re-read the plain (unpublished) stats right now.
    func touch() { objectWillChange.send() }

    // MARK: Derived

    var emotion: Emotion {
        if let (e, until) = moodOverride, until > Date() { return e }
        switch act {
        case .carried: return .dizzy
        case .sleep:   return .sleepy
        case .eat:     return .eating
        case .bark:    return .angry
        case .zoom:    return .playful
        case .love:    return .love
        case .tap:     return .alert
        case .dance, .wave: return .happy
        case .leap: return .excited
        default: break
        }
        if petting > 0.15 { return .love }

        // everything lined up at once: rare, and worth celebrating
        if hunger > 0.92 && happiness > 0.92 && energy > 0.85 && affection > 0.8
            && (act == .idle || act == .sit) {
            return .blissful
        }

        // properly neglected: worse than plain hungry or sad on their own
        if hunger < 0.12 && happiness < 0.25 { return .worried }

        if hunger < 0.25 { return .hungry }
        if energy < 0.2 { return .sleepy }
        if happiness < 0.3 { return .sad }

        // your cursor parked right next to her while she's just sitting there
        if nearCursor && (act == .idle || act == .sit) { return .curious }

        // ignored for a long stretch while awake and not thrilled about it
        if act == .idle && happiness < 0.7 && Date().timeIntervalSince(lastInteraction) > 200 {
            return .bored
        }

        // listening to music: nodding along
        if Date() < bopUntil && (act == .idle || act == .sit) { return .vibing }

        // the mood you checked in with colours her baseline
        if act == .idle || act == .sit, let m = currentMood {
            switch m {
            case .cozy, .stressed: return .cozy
            case .excited: return .hyped
            case .tired: return energy < 0.7 ? .sleepy : .cozy
            case .radiant: break
            }
        }

        if happiness > 0.82 && affection > 0.6 { return .happy }
        if happiness > 0.6 { return .happy }
        if happiness < 0.5 && happiness >= 0.3 { return .moody }
        return .neutral
    }

    var level: Int { Progression.resolve(totalXP: xp).level }
    var levelTitle: String { Progression.title(level: level, species: species) }
    /// 0...1 through the current level.
    var levelProgress: Double {
        let r = Progression.resolve(totalXP: xp)
        return r.needed > 0 ? min(1, r.into / r.needed) : 0
    }
    var xpIntoLevel: Double { Progression.resolve(totalXP: xp).into }
    var xpForThisLevel: Double { Progression.resolve(totalXP: xp).needed }
    var collarTier: Int { Progression.collarTier(level: level) }

    /// Seconds since the current act began: used to ease animations in/out cleanly
    /// instead of them starting or stopping mid-cycle at full speed.
    private var actElapsed: Double { Date().timeIntervalSince(actStartedAt) }

    var pose: Pose {
        Pose(emotion: emotion,
             phase: phase,
             gait: gait,
             walk: walkAmt,
             run: runAmt,
             facing: facingVis,
             squash: squash,
             dangling: act == .carried,
             look: lookVis,
             sit: sitAmt,
             sleep: sleepAmt,
             petting: petting,
             stretch: stretchAmt,
             sniff: sniffAmt,
             groom: groomAmt,
             scratch: scratchAmt,
             dance: danceAmt,
             wave: waveAmt,
             bop: bop,
             collarTier: collarTier,
             tapping: act == .tap,
             tapPhase: act == .tap ? min(1, actElapsed / tapDuration) : 0,
             outfit: outfit,
             perched: perched,
             prop: propKind,
             propAmt: propAmt)
    }

    private var lookVis: CGVector = .zero

    /// Glides every pose amount toward its target so sitting down, turning round and
    /// breaking into a trot are movements instead of cuts.
    private func updateBlends(_ dt: Double) {
        let before = [walkAmt, runAmt, sitAmt, sleepAmt, stretchAmt, sniffAmt, groomAmt, scratchAmt,
                      facingVis, propAmt, danceAmt, waveAmt]
        let lookBefore = [Double(lookVis.dx), Double(lookVis.dy)]
        defer {
            // "still moving" means moving at a pace you could see: the last few percent of an exponential ease
            // crawl for seconds, and drawing every frame of that tail is pure waste
            let after = [walkAmt, runAmt, sitAmt, sleepAmt, stretchAmt, sniffAmt, groomAmt, scratchAmt,
                         facingVis, propAmt, danceAmt, waveAmt]
            let pace = zip(before, after).map { abs($0 - $1) }.max() ?? 0
            blending = pace > 0.25 * max(dt, 0.001)
            let lookPace = zip(lookBefore, [Double(lookVis.dx), Double(lookVis.dy)]).map { abs($0 - $1) }.max() ?? 0
            lookBlending = lookPace > 0.3 * max(dt, 0.001)
        }
        let walking = ((act == .walk || act == .zoom) && walkTarget != nil) || act == .leap
        let speed = (act == .zoom ? 420.0 : 78.0 * speedMultiplier)
        ease(&walkAmt, to: walking ? 1 : 0, rate: 9, dt: dt)
        ease(&runAmt, to: !walking ? 0 : min(1, max(0, (speed - 110) / 260)), rate: 5, dt: dt)
        ease(&gaitRate, to: 8 + speed * 0.035, rate: 4, dt: dt)
        gait += dt * gaitRate * walkAmt

        ease(&sitAmt, to: (act == .sit || act == .groom || act == .scratch) ? 1 : 0, rate: 5, dt: dt)
        ease(&sleepAmt, to: act == .sleep ? 1 : 0, rate: 2.6, dt: dt)
        ease(&stretchAmt, to: act == .stretch ? 1 : 0, rate: 4, dt: dt)
        ease(&sniffAmt, to: act == .sniff ? 1 : 0, rate: 6, dt: dt)
        ease(&groomAmt, to: act == .groom ? 1 : 0, rate: 5, dt: dt)
        ease(&scratchAmt, to: act == .scratch ? 1 : 0, rate: 7, dt: dt)
        ease(&danceAmt, to: act == .dance ? 1 : 0, rate: 8, dt: dt)
        ease(&waveAmt, to: act == .wave ? 1 : 0, rate: 9, dt: dt)
        ease(&facingVis, to: facing, rate: 13, dt: dt)

        bop = max(0, bop - dt * 5)

        // the book and the boba: only once she's actually sitting, and one fades out
        // before the other fades in
        let held: Prop
        switch outfit.held {
        case .boba: held = .boba
        case .matcha: held = .matcha
        case .book: held = .book
        case .console: held = .console
        default: held = .none
        }
        let want: Prop = sitAmt > 0.5 ? (focusTimerRunning ? .book : (onBreak ? .boba : held)) : .none
        if want == propKind {
            ease(&propAmt, to: want == .none ? 0 : 1, rate: 6, dt: dt)
        } else {
            ease(&propAmt, to: 0, rate: 9, dt: dt)
            if propAmt < 0.04 { propKind = want }
        }
        var lx = Double(lookVis.dx), ly = Double(lookVis.dy)
        ease(&lx, to: Double(look.dx), rate: 10, dt: dt)
        ease(&ly, to: Double(look.dy), rate: 10, dt: dt)
        lookVis = CGVector(dx: lx, dy: ly)
    }

    /// How often she needs redrawing. Every frame costs a little CPU, so she only gets as many as she needs:
    /// resting barely moves (a breath, a blink, a flick of an ear), a walk needs smooth legs, and a drag or a
    /// bark needs the most. Eased off further when the Mac is on battery saver, hot or already busy, and
    /// nothing is drawn at all while she can't be seen.
    var desiredFrameInterval: Double {
        if drawPaused { return 1.0 / 3 }
        return baseFrameInterval / Throttle.factor
    }

    /// True while her window is covered or off screen: she keeps living (so she's in the right place when
    /// you look again) but nothing is drawn.
    var drawPaused = false

    private var baseFrameInterval: Double {
        switch act {
        case .zoom, .fall, .carried, .bark, .tap, .leap: return 1.0 / 30
        case .walk: return 1.0 / 12
        case .dance: return 1.0 / 20
        case .groom, .scratch, .sniff, .wave: return 1.0 / 12
        default: break
        }
        if blending || petting > 0.01 { return 1.0 / 15 }
        if !particles.isEmpty { return 1.0 / 15 }
        if lookBlending || CACurrentMediaTime() < attentionUntil { return 1.0 / 12 }
        switch emotion {
        case .excited, .playful, .blissful, .angry, .eating, .love, .proud, .dizzy: return 1.0 / 16
        default: break
        }
        if act == .sleep { return species.stillWhenResting ? 1.0 / 2 : 1.0 / 3 }
        // resting. A long tail needs a few more frames to wave smoothly than a pom does, and anything that
        // sways or twinkles (an aura, wings, a scarf, a book, a drink) does too.
        switch species {
        case .cat, .dog, .fox, .axolotl: return 1.0 / 9
        default: break
        }
        if outfit.aura != .none || outfit.body != .none || outfit.neck != .none || propKind != .none { return 1.0 / 7 }
        // calm: a breath, a blink, an ear flick. They barely move, so a few frames a second look just as
        // smooth, with extra frames only around the moments something actually happens.
        let t = phase
        if species.stillWhenResting { return 1.0 / (Loop.eventPace(at: t) ?? 2) }
        let aroundBlink = (t + 0.3).truncatingRemainder(dividingBy: Loop.blinkEvery) < 0.75
        let aroundFlick = (t + 0.3).truncatingRemainder(dividingBy: Loop.period / 2) < 0.9
        let aroundBlep = t.truncatingRemainder(dividingBy: Loop.period) < 1.3
        return (aroundBlink || aroundFlick || aroundBlep) ? 1.0 / 12 : 1.0 / 3
    }
    private var tapPhaseActive: Bool { act == .tap }

    var timerRemaining: TimeInterval? {
        timerEndsAt.map { max(0, $0.timeIntervalSinceNow) }
    }
    var focusTimerRunning: Bool { timerEndsAt != nil && !timerIsBreak }
    var onBreak: Bool { timerEndsAt != nil && timerIsBreak }

    var ageDays: Int { max(0, Calendar.current.dateComponents([.day], from: born, to: Date()).day ?? 0) }

    var statusLine: String {
        if let b = bubbleText, bubbleUntil > Date() { return b }
        return "\(name) is \(emotion.label)"
    }

    // MARK: Screen helpers

    var screen: NSScreen {
        NSScreen.screens.first { $0.frame.contains(position) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// The screens' rectangles, read at most once a second. Asking a screen for its frame is a trip to the window
    /// server, and she needs the floor and the walls on every tick.
    private struct ScreenGeo { var frame: CGRect; var visible: CGRect }
    private var geo: [ScreenGeo] = []
    private var geoStamp: CFTimeInterval = 0
    private var geoMain = ScreenGeo(frame: .zero, visible: .zero)

    private var screenGeo: ScreenGeo {
        let now = CACurrentMediaTime()
        if geo.isEmpty || now - geoStamp > 1 {
            geoStamp = now
            geo = NSScreen.screens.map { ScreenGeo(frame: $0.frame, visible: $0.visibleFrame) }
            if let m = NSScreen.main ?? NSScreen.screens.first { geoMain = ScreenGeo(frame: m.frame, visible: m.visibleFrame) }
        }
        return geo.first { $0.frame.contains(position) } ?? geoMain
    }
    /// Drops the remembered rectangles (a display was plugged in, or the Dock moved).
    func screensChanged() { geo = [] }

    var groundY: CGFloat { screenGeo.visible.minY + 2 }
    var floorY: CGFloat { restY ?? groundY }
    var perched: Bool { restY != nil }
    /// The highest she can sit and still be fully on screen.
    var topY: CGFloat { screenGeo.visible.maxY - (Design.height * scale) + 40 }
    func clampY(_ y: CGFloat) -> CGFloat { min(max(y, groundY), max(groundY, topY)) }
    var minX: CGFloat { screenGeo.visible.minX + 30 }
    var maxX: CGFloat { screenGeo.visible.maxX - 30 }

    func placeAtStart() {
        let s = NSScreen.main ?? NSScreen.screens[0]
        position = CGPoint(x: s.visibleFrame.midX, y: s.visibleFrame.minY + 2)
        // back where you left her, if that spot still exists
        if let spot = Prefs.petSpot {
            let x = CGFloat(spot.x), y = CGFloat(spot.y)
            if let sc = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: x, y: max(y, $0.visibleFrame.minY + 2))) }) {
                position = CGPoint(x: min(max(x, sc.visibleFrame.minX + 30), sc.visibleFrame.maxX - 30), y: sc.visibleFrame.minY + 2)
                if y > position.y + 30 && Prefs.placeAnywhere {
                    restY = clampY(y)
                    perchX = position.x
                    position.y = restY!
                }
            }
        }
    }

    /// Sends her back to the middle of the floor.
    func goHome() {
        cancelCloseSequence()
        let s = screen
        restY = nil
        walkTarget = nil
        position = CGPoint(x: s.visibleFrame.midX, y: groundY)
        setAct(.idle, for: 2)
        squash = 0.3
        say("home sweet home 🏠", .happy, 2.4)
        emit(.sparkle, count: 6, at: Stage.head, spread: 40)
    }

    /// Where to save her: x, and y or -1 for the floor.
    var spot: (x: Double, y: Double) { (Double(position.x), restY.map { Double($0) } ?? -1) }

    // MARK: Main loop

    func tick(_ dt: Double) {
        phase += dt
        decayStats(dt)
        updateAct(dt)
        // she can rest for a second between ticks, but motion is only ever integrated in small steps, so waking
        // up never makes her jump
        let step = min(dt, 0.1)
        updatePhysics(step)
        updateBlends(step)
        updateParticles(step)
        if !drawPaused { clock.frame &+= 1 }

        updateTimer()
        updateReminders()
        updateMusicBop()
        if ambiencePlaying {
            musicSecondsPending += dt
            if musicSecondsPending >= 60 { Prefs.musicMinutes += musicSecondsPending / 60; musicSecondsPending = 0 }
        }
        if Date().timeIntervalSince(lastMoodRefresh) > 30 { lastMoodRefresh = Date(); currentMood = Prefs.todayMood }
        petting = max(0, petting - dt * 0.55)
        squash += (0 - squash) * min(1, dt * 9)
        // only when there is something to clear: every write to a @Published value re-renders everything watching it
        if bubbleText != nil, bubbleUntil < Date() { bubbleText = nil }
        if let (_, until) = moodOverride, until < Date() { moodOverride = nil }
    }

    private func decayStats(_ dt: Double) {
        let h = dt / (60 * 90)           // empty belly in ~90 min of use
        hunger = max(0, hunger - h)
        energy = act == .sleep ? min(1, energy + dt / (60 * 6)) : max(0, energy - dt / (60 * 150))
        if act == .zoom { energy = max(0, energy - dt / 120) }
        var target = 0.55 + affection * 0.25
        if hunger < 0.2 { target -= 0.35 }
        if energy < 0.15 { target -= 0.15 }
        happiness += (target - happiness) * min(1, dt / 240)
        affection = max(0, affection - dt / (60 * 60 * 8))
        happiness = min(1, max(0, happiness))
    }

    private func updateAct(_ dt: Double) {
        guard act != .carried, act != .fall, act != .leap else { return }

        if isFollowing { follow() }
        if act == .dance, Date().timeIntervalSince(lastNote) > 0.5 {
            lastNote = Date()
            emit(.note, count: 1, at: Stage.aura, spread: 34)
        }

        if let t = walkTarget {
            let dx = t - position.x
            if abs(dx) < 6 {
                walkTarget = nil
                if act == .walk {
                    if calledOver {
                        calledOver = false
                        say(Dialogue.line(.arrived, species), nil, 2.4)
                        moodOverride = (.shy, Date().addingTimeInterval(2.2))
                    }
                    setAct(.idle, for: Double.random(in: 1.5...4))
                }
            } else {
                let dir: Double = dx > 0 ? 1 : -1
                if facing != dir { facing = dir }
                let speed = (act == .zoom ? 420.0 : 78.0) * speedMultiplier
                position.x += CGFloat(speed * dt) * CGFloat(facing)
            }
        }

        if holdStill && !isFollowing {
            walkTarget = nil
            if act == .walk { setAct(.idle, for: 2) }
        }
        // while she's coming to you, nothing else gets a say
        if isFollowing { return }
        guard Date() > actUntil else { return }

        switch act {
        case .bark, .love, .eat, .zoom, .scratch, .stretch, .sniff, .groom, .tap, .dance, .wave:
            bowl = 0
            setAct(.idle, for: Double.random(in: 1...3))
            return
        default: break
        }

        // Autonomous choices
        if energy < 0.16 {
            setAct(.sleep, for: Double.random(in: 25...60))
            say(Dialogue.line(.sleepy, species), .sleepy, 4)
            return
        }
        if act == .sleep && energy > 0.6 {
            setAct(.idle, for: 2)
            say(Dialogue.line(.wokeUp, species), .happy, 3)
            return
        }
        if act == .sleep { actUntil = Date().addingTimeInterval(20); return }

        if hunger < 0.12 && happiness < 0.25 && Double.random(in: 0...1) < 0.4 {
            say(Dialogue.line(.worried, species), .worried, 5)
            onWhine?()
            setAct(.idle, for: 6)
            return
        }
        if hunger < 0.22 && Double.random(in: 0...1) < 0.35 {
            say(Dialogue.line(.hungry, species), .hungry, 5)
            onWhine?()
            setAct(.idle, for: 6)
            return
        }

        if focusTimerRunning {
            // she studies beside you: mostly sitting with her book, with the odd stretch
            // or face-wash so she's never frozen
            let r = Double.random(in: 0...1)
            if r < 0.08 { setAct(.stretch, for: 2.6) }
            else if r < 0.16 && species != .dog { performSignatureMove() }
            else { setAct(.sit, for: Double.random(in: 10...22)) }
            return
        }
        if onBreak && Double.random(in: 0...1) < 0.7 {
            setAct(.sit, for: Double.random(in: 8...16))   // sipping her boba
            return
        }

        let roll = Double.random(in: 0...1)
        switch roll {
        case ..<0.34:
            if Prefs.roams && !holdStill && !staying {
                wander()
            } else {
                setAct(.sit, for: Double.random(in: 4...10))
            }
        case ..<0.54:
            setAct(.sit, for: Double.random(in: 4...10))
        case ..<0.64:
            setAct(.scratch, for: 2.0)
        case ..<0.70:
            setAct(.stretch, for: 2.6)
            say(Dialogue.line(.stretch, species), .happy, 2.4)
        case ..<0.75:
            // everyone but the dog washes her face; the dog sniffs around instead,
            // same as the bucket right below this one
            if species != .dog {
                performSignatureMove()
            } else {
                setAct(.sniff, for: 2.2)
                say(Dialogue.line(.sniff, species), .curious, 2.0)
            }
        case ..<0.80:
            setAct(.sniff, for: 2.2)
            say(Dialogue.line(.sniff, species), .curious, 2.0)
        case ..<0.88:
            setAct(.idle, for: 3)
            let kind: Dialogue.Line
            switch emotion {
            case .bored:    kind = .bored
            case .blissful: kind = .blissful
            case .curious:  kind = .curious
            default:        kind = .chatter
            }
            say(Dialogue.line(kind, species), emotion, 3.5)
        default:
            setAct(.idle, for: Double.random(in: 2...6))
        }
    }

    private func updatePhysics(_ dt: Double) {
        switch act {
        case .fall:
            velocity.dy -= 2600 * dt
            position.y += velocity.dy * dt
            position.x += velocity.dx * dt
            if position.y <= floorY {
                position.y = floorY
                let impact = min(1, abs(velocity.dy) / 1400)
                squash = impact
                velocity = .zero
                setAct(.idle, for: 1.2)
                if impact > 0.35 {
                    emit(.star, count: 5, at: Stage.p(94, Design.ground), spread: 40)
                    onYip?()
                    say(Dialogue.line(.landed, species), .dizzy, 2)
                    moodOverride = (.dizzy, Date().addingTimeInterval(1.4))
                }
            }
        case .carried:
            break
        case .leap:
            let t = Date().timeIntervalSince(leapStart)
            if t < 0 {
                squash = 0.5                                        // crouched, about to spring
                position = leapFrom
            } else {
                let u = min(1, t / leapDur)
                let e = u * u * (3 - 2 * u)
                let arc = sin(u * .pi) * (46 + abs(leapTo.y - leapFrom.y) * 0.25)
                position.x = leapFrom.x + (leapTo.x - leapFrom.x) * e
                position.y = leapFrom.y + (leapTo.y - leapFrom.y) * e + arc
                squash = -0.32 * sin(u * .pi)                       // stretched out in flight
                if Date().timeIntervalSince(lastNote) > 0.09 {
                    lastNote = Date()
                    emit(.sparkle, count: 1, at: Stage.p(64, 130), spread: 14)
                }
            }
        default:
            // glide to her resting height instead of snapping, so being called over or
            // put down on a cushion is a soft move rather than a teleport
            let target = floorY
            if abs(position.y - target) > 0.5 {
                position.y += (target - position.y) * CGFloat(min(1, dt * 7))
            } else {
                position.y = target
            }
        }
        if act != .carried {
            position.x = min(max(position.x, minX), maxX)
        }
    }

    private func updateParticles(_ dt: Double) {
        guard !particles.isEmpty else { return }
        for i in particles.indices {
            particles[i].life -= dt
            particles[i].pos.x += particles[i].vel.dx * dt
            particles[i].pos.y += particles[i].vel.dy * dt
            particles[i].rot += particles[i].spin * dt
            if particles[i].kind == .crumb { particles[i].vel.dy += 420 * dt }
            if particles[i].kind == .confetti {
                particles[i].vel.dy += 230 * dt                 // gravity, but floaty
                particles[i].vel.dx *= 0.992
                particles[i].spin = particles[i].spin.sign == .minus ? -9 : 9
            }
            if particles[i].kind == .heart { particles[i].vel.dx = sin(particles[i].life * 5) * 18 }
            if particles[i].kind == .bubble { particles[i].vel.dx = sin(particles[i].life * 7) * 14 }
        }
        particles.removeAll { $0.life <= 0 }
    }

    // MARK: Acts

    private func setAct(_ a: Act, for seconds: Double) {
        act = a
        actUntil = Date().addingTimeInterval(seconds)
        actStartedAt = Date()
        if a != .walk && a != .zoom { walkTarget = nil }
        if a == .sleep { emitZzzSoon() }
    }

    private func wander() {
        let lo = perched ? max(minX, perchX - 170) : minX
        let hi = perched ? min(maxX, perchX + 170) : maxX
        let target = CGFloat.random(in: lo...max(lo, hi))
        walkTarget = target
        speedMultiplier = Double.random(in: 0.75...1.3)
        setAct(.walk, for: 30)
    }

    /// The face-wash: every species but the dog, see the call site.
    private func performSignatureMove() {
        setAct(.groom, for: 3.2)
        say(Dialogue.line(.groom, species), .happy, 2.8)
    }

    /// Settings ▸ Auto-close Reels tabs: she reaches up, taps a little close button
    /// that pops in near her paw, and only *then* is `onCloseReelsTab` actually
    /// fired — so the real tab close lands on the same beat as the visible tap
    /// instead of happening instantly while she's still mid-reach.
    // MARK: Closing a Reels tab herself

    private var closing = false
    /// Every step of the sequence checks this, so grabbing her or sending her home
    /// cancels the rest instead of leaving callbacks firing at a pet who's elsewhere.
    private var closeToken = UUID()
    private var homeSpot: CGPoint?
    private var homeOnFloor = true
    private var leapFrom = CGPoint.zero, leapTo = CGPoint.zero
    private var leapStart = Date.distantPast
    private var leapDur = 0.85

    /// Settings ▸ Auto-close Reels tabs. She leaps up onto the top of your browser window,
    /// presses a big ✕ button herself, the tab closes on the same beat, and she leaps back
    /// to wherever she was. (The close itself still targets the real tab through the
    /// browser's own scripting: see `ActivityMonitor.closeCurrentTab`: so it can't misclick.)
    func performCloseTap() {
        guard act != .tap, !closing else { return }

        // macOS Settings ▸ Accessibility ▸ Reduce Motion: skip the choreography entirely
        // rather than just speeding it up: the point of that setting is fewer moving
        // things on screen, not faster ones
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            say(Dialogue.coach(.tapClose, species), .alert, 2)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.onCloseReelsTab?()
            }
            return
        }

        walkTarget = nil
        followUntil = .distantPast
        closeToken = UUID()
        let token = closeToken

        guard let spot = browserWindowSpot() else {
            // no window to find: just reach up and tap where she is
            tapTheButton(token: token) {}
            return
        }
        closing = true
        homeSpot = position
        homeOnFloor = restY == nil
        say(Dialogue.coach(.tapClose, species), .alert, 3)
        leap(to: CGPoint(x: spot.x, y: clampY(spot.y)), token: token) { [weak self] in
            self?.tapTheButton(token: token) { self?.celebrateAndGoHome(token: token) }
        }
    }

    /// Where she should stand to reach the tab bar: on the top edge of the front-most
    /// window of whatever app you're in (window frames need no special permission).
    private func browserWindowSpot() -> CGPoint? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        for w in info {
            guard (w[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let width = b["Width"], width > 320 else { continue }
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            let topEdge = primaryHeight - y                       // AppKit y of the window's top edge
            let stand = CGPoint(x: x + min(190, width * 0.3), y: topEdge - 14)
            let sc = NSScreen.screens.first { $0.frame.contains(stand) } ?? NSScreen.screens.first
            guard let vis = sc?.visibleFrame else { return stand }
            return CGPoint(x: min(max(stand.x, vis.minX + 30), vis.maxX - 30), y: stand.y)
        }
        return nil
    }

    /// A proper jump: crouch, spring along an arc stretched out in flight, land with a squash.
    private func leap(to dest: CGPoint, token: UUID, then done: @escaping () -> Void) {
        leapFrom = position
        leapTo = dest
        leapDur = min(1.1, max(0.6, 0.55 + hypot(dest.x - position.x, dest.y - position.y) / 1800))
        leapStart = Date().addingTimeInterval(0.22)               // the crouch before takeoff
        facing = dest.x >= position.x ? 1 : -1
        setAct(.leap, for: 30)
        onYip?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22 + leapDur) { [weak self] in
            guard let self, self.closeToken == token else { return }
            self.position = dest
            self.restY = dest.y > self.groundY + 30 ? dest.y : nil
            self.perchX = dest.x
            self.squash = 0.7
            self.emit(.star, count: 4, at: Stage.p(94, Design.ground), spread: 34)
            self.onTapSound?()
            self.setAct(.idle, for: 3)
            done()
        }
    }

    private func tapTheButton(token: UUID, done: @escaping () -> Void) {
        setAct(.tap, for: tapDuration)
        moodOverride = (.alert, Date().addingTimeInterval(tapDuration))

        // right in front of her raised paw, where `tapRaise` swings it at the peak
        let target = Stage.p(128, 124)
        let pressAt = tapDuration * 0.5   // the middle of tapRaise's held peak

        // she looks at the button before her paw ever gets there: PetWindow's
        // mouse-follow leaves `look` alone while act == .tap, see updateLook()
        look = CGVector(dx: 0.85, dy: 0.2)

        DispatchQueue.main.asyncAfter(deadline: .now() + pressAt * 0.35) { [weak self] in
            guard let self, self.closeToken == token else { return }
            self.closeButtonAt = target
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + pressAt) { [weak self] in
            guard let self, self.closeToken == token else { return }
            self.closeButtonPressed = true
            self.onTapSound?()
            self.emit(.sparkle, count: 5, at: target, spread: 26)
            self.emit(.star, count: 3, at: target, spread: 18)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + pressAt + 0.18) { [weak self] in
            guard let self, self.closeToken == token else { return }
            self.closeButtonPressed = false
            self.closeButtonAt = nil
            self.onCloseReelsTab?()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + tapDuration + 0.35) { [weak self] in
            guard let self, self.closeToken == token else { return }
            done()
        }
    }

    /// The tab is gone: a little happy dance, then back to where she was.
    private func celebrateAndGoHome(token: UUID) {
        guard closeToken == token, closing else { return }
        setAct(.dance, for: 2)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in
            guard let self, self.closeToken == token else { return }
            guard let home = self.homeSpot else { self.closing = false; return }
            let dest = CGPoint(x: home.x, y: self.homeOnFloor ? self.groundY : home.y)
            self.leap(to: dest, token: token) { [weak self] in
                self?.closing = false
                self?.homeSpot = nil
            }
        }
    }

    /// Anything that takes control of her (a drag, "send her home") ends the sequence.
    private func cancelCloseSequence() {
        closeToken = UUID()
        closing = false
        closeButtonAt = nil
        closeButtonPressed = false
    }

    /// Every XP award goes through here so levelling up is caught in exactly one
    /// place, no matter what earned it.
    func addXP(_ amount: Double) {
        guard amount > 0 else { return }
        let before = level
        xp += amount
        let after = level
        if after > before { celebrateLevelUp(to: after) }
    }

    private func celebrateLevelUp(to newLevel: Int) {
        setAct(.love, for: 4)
        say(Dialogue.line(.levelUp, species, ["n": "\(newLevel)"]), nil, 5)
        moodOverride = (.proud, Date().addingTimeInterval(4))
        emit(.star, count: 10, at: Stage.aura, spread: 70)
        emit(.sparkle, count: 10, at: Stage.aura, spread: 60)
        emit(.heart, count: 6, at: Stage.aura, spread: 40)
        happiness = min(1, happiness + 0.2)
        onYip?()

        // a new collar is a bigger deal than a plain level, so it gets its own beat
        if Progression.collarLevels.contains(newLevel) {
            let tier = Progression.collarTier(level: newLevel)
            let name = Progression.collarName(tier: tier)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.say(Dialogue.line(.newCollar, self.species, ["item": name]), .blissful, 5)
                    self.emit(.sparkle, count: 12, at: Stage.head, spread: 50)
                    self.onYip?()
                }
            }
        }
    }

    /// Cuts short a wander already in progress: used when "roam around" gets
    /// switched off, so staying put takes effect immediately instead of waiting
    /// for whatever walk she's mid-stride on to finish on its own.
    func stayPut() {
        guard act == .walk, !calledOver else { return }
        walkTarget = nil
        setAct(.idle, for: Double.random(in: 2...5))
    }

    func say(_ text: String, _ mood: Emotion? = nil, _ seconds: Double = 3.5) {
        bubbleText = text
        bubbleUntil = Date().addingTimeInterval(seconds)
        if let m = mood { moodOverride = (m, Date().addingTimeInterval(seconds)) }
    }

    func emit(_ kind: Particle.Kind, count: Int, at p: CGPoint, spread: Double = 24) {
        for _ in 0..<count {
            let vx = Double.random(in: -spread...spread)
            let vy: Double
            var life = Double.random(in: 0.9...1.7)
            var size = Double.random(in: 12...20)
            switch kind {
            case .heart:  vy = Double.random(in: -70 ... -34); size = Double.random(in: 13...23)
            case .zzz:    vy = -26; life = 2.6; size = Double.random(in: 15...22)
            case .sparkle: vy = Double.random(in: -60 ... -10); size = Double.random(in: 9...16)
            case .crumb:  vy = Double.random(in: -160 ... -70); size = Double.random(in: 4...7); life = 1.1
            case .anger:  vy = Double.random(in: -50 ... -20); size = Double.random(in: 14...20); life = 0.9
            case .star:   vy = Double.random(in: -90 ... -30); size = Double.random(in: 10...16); life = 0.8
            case .note:   vy = Double.random(in: -60 ... -30); size = Double.random(in: 14...20)
            case .sweat:  vy = Double.random(in: -40 ... -10); size = 12; life = 0.8
            case .bubble: vy = Double.random(in: -50 ... -22); size = Double.random(in: 6...13); life = 1.4
            case .confetti: vy = Double.random(in: -190 ... -90); size = Double.random(in: 6...10); life = Double.random(in: 1.6...2.4)
            }
            size *= 0.82
            particles.append(Particle(kind: kind,
                                      pos: CGPoint(x: p.x + Double.random(in: -34...34),
                                                   y: p.y + Double.random(in: -14...4)),
                                      vel: CGVector(dx: vx, dy: vy),
                                      life: life, maxLife: life, size: size,
                                      rot: Double.random(in: -0.3...0.3),
                                      spin: Double.random(in: -1.4...1.4)))
        }
    }

    private func emitZzzSoon() {
        emit(.zzz, count: 1, at: Stage.aura, spread: 6)
    }

    // MARK: Interactions

    func petMe() {
        lastInteraction = Date()
        petting = min(1, petting + 0.55)
        happiness = min(1, happiness + 0.045)
        affection = min(1, affection + 0.03)
        energy = min(1, energy + 0.004)
        emit(.heart, count: 3, at: Stage.aura, spread: 26)
        if act == .sleep { setAct(.idle, for: 2) }
        if Double.random(in: 0...1) < 0.32 {
            addXP(Progression.Award.petted)
            say(Dialogue.line(.petted, species), .love, 2.4)
            onYip?()
        }
        moodOverride = (.love, Date().addingTimeInterval(1.6))
    }

    /// She has a real ceiling: once she's full, feeding again does nothing but make
    /// her groan. Stops "feed" from being a free, unlimited happiness/affection button.
    func feed(treat: Bool = false) {
        guard act != .carried else { return }
        lastInteraction = Date()
        if hunger >= 0.95 {
            say(Dialogue.line(.full, species), .bored, 2.5)
            return
        }
        treatsEaten += 1
        addXP(treat ? Progression.Award.treat : Progression.Award.fed)
        bowl = 1
        setAct(.eat, for: treat ? 3.0 : 5.5)
        hunger = min(1, hunger + (treat ? 0.22 : 0.5))
        happiness = min(1, happiness + 0.12)
        affection = min(1, affection + 0.05)
        energy = min(1, energy + 0.08)
        say(Dialogue.line(treat ? .treat : .fed, species), .eating, 3)
        onMunch?()
        emit(.crumb, count: 8, at: Stage.mouth, spread: 60)
        emit(.heart, count: 2, at: Stage.aura, spread: 20)
    }

    func play() {
        guard act != .carried else { return }
        lastInteraction = Date()
        // told to stay? then she celebrates on the spot instead of tearing across the screen
        if staying { dance(); return }
        setAct(.zoom, for: 7)
        walkTarget = CGFloat.random(in: minX...maxX)
        speedMultiplier = 1
        happiness = min(1, happiness + 0.2)
        affection = min(1, affection + 0.05)
        addXP(Progression.Award.played)
        say(Dialogue.line(.play, species), .playful, 3)
        emit(.sparkle, count: 10, at: Stage.body, spread: 70)
        onYip?()
    }

    // MARK: Looks

    func chooseSpecies(_ kind: Species) {
        guard kind != species else { return }
        species = kind
        coatIndex = Prefs.coat(for: kind)
        Prefs.species = kind
        say(Dialogue.line(.switched, kind), .excited, 3)
        emit(.sparkle, count: 10, at: Stage.head, spread: 50)
        onYip?()
    }

    func chooseCoat(_ index: Int) {
        guard index != coatIndex, species.coats.indices.contains(index) else { return }
        coatIndex = index
        Prefs.setCoat(index, for: species)
        say(Dialogue.line(.dressUp, species), .happy, 2.4)
        emit(.sparkle, count: 6, at: Stage.head, spread: 40)
    }

    /// Puts something on (or takes it off, if she's already wearing it). One item per slot.
    func wear(_ a: Accessory) {
        guard a != .none else { return }
        let slot = a.slot
        guard owns(a) else {
            say("that one's in the Sanctuary 🍓 \(a.price) berries", .shy, 2.8)
            return
        }
        if outfit[slot] == a {
            outfit[slot] = .none
            say(Dialogue.line(.undress, species), .neutral, 2.2)
        } else {
            outfit[slot] = a
            say(Dialogue.line(.dressUp, species), .happy, 2.8)
            emit(.sparkle, count: 8, at: Stage.head, spread: 44)
        }
        Prefs.outfit = outfit
        checkBadges()
    }

    // MARK: Sanctuary

    func owns(_ a: Accessory) -> Bool { a.price == 0 || owned.contains(a.rawValue) }
    func owns(_ d: Decor) -> Bool { owned.contains("decor." + d.rawValue) }

    /// Spends berries on an item. Returns false (and says why) if she can't afford it.
    @discardableResult
    func buy(_ a: Accessory) -> Bool {
        guard !owns(a) else { return true }
        guard berries >= a.price else {
            say("you need \(a.price - berries) more berries 🍓 keep focusing!", .shy, 2.8)
            return false
        }
        berries -= a.price
        owned.insert(a.rawValue)
        celebratePurchase(a.emoji, a.title)
        onNeedsSave?()
        return true
    }

    @discardableResult
    func buy(_ d: Decor) -> Bool {
        guard !owns(d) else { return true }
        guard berries >= d.price else {
            say("you need \(d.price - berries) more berries 🍓 keep focusing!", .shy, 2.8)
            return false
        }
        berries -= d.price
        owned.insert("decor." + d.rawValue)
        decorOn.insert(d.rawValue)
        Prefs.decorOn = decorOn
        celebratePurchase(d.emoji, d.title)
        onNeedsSave?()
        return true
    }

    func toggleDecor(_ d: Decor) {
        guard owns(d) else { return }
        if decorOn.contains(d.rawValue) {
            decorOn.remove(d.rawValue)
        } else {
            if d.isAmbient { for other in Decor.allCases where other.isAmbient { decorOn.remove(other.rawValue) } }
            decorOn.insert(d.rawValue)
        }
        Prefs.decorOn = decorOn
    }

    private func celebratePurchase(_ emoji: String, _ title: String) {
        onBell?()
        say("\(emoji) \(title.lowercased())!! it's mine now", .excited, 3)
        emit(.confetti, count: 14, at: Stage.aura, spread: 70)
        onYip?()
    }

    /// Berries trickle in as you do things: a minute of focus, a ticked-off task, a goal.
    func addBerries(_ amount: Double) {
        berryRemainder += amount
        let whole = Int(berryRemainder)
        if whole > 0 { berries += whole; berryRemainder -= Double(whole) }
    }

    // MARK: Mood check-in

    var todayMoodValue: Mood? { Prefs.todayMood }
    var needsCheckIn: Bool { Prefs.dailyCheckIn && Prefs.todayMood == nil }

    /// Records how you feel and lets her react: she's softer on hard days and cuddles closer
    /// when you're stressed.
    func setMood(_ m: Mood) {
        Prefs.todayMood = m
        currentMood = m
        moods[Calendar.current.startOfDay(for: Date())] = m.rawValue
        addBerries(5)
        onBell?()
        lastInteraction = Date()
        say(m.reply(species), m == .stressed || m == .tired ? .cozy : .happy, 5)
        emit(.heart, count: 5, at: Stage.aura, spread: 34)
        if m == .stressed { comeHere() }
        onYip?()
        onNeedsSave?()
    }

    // MARK: Music

    /// Called on each beat of whatever music is playing: she nods her head along.
    func beat(strength: Double) {
        guard act != .carried, act != .sleep else { return }
        bop = max(bop, min(1, strength))
        bopUntil = Date().addingTimeInterval(3)
        if act == .idle, Date() > actUntil.addingTimeInterval(-0.2) { setAct(.sit, for: 3) }
        if Double.random(in: 0...1) < 0.12 { emit(.note, count: 1, at: Stage.aura, spread: 30) }
    }

    func clearOutfit() {
        guard !outfit.isEmpty else { return }
        outfit = Outfit()
        Prefs.outfit = outfit
        say(Dialogue.line(.undress, species), .neutral, 2.2)
    }

    func chooseSize(_ level: Int) {
        guard level != sizeLevel else { return }
        sizeLevel = level
        Prefs.sizeLevel = level
        position.y = groundY
        say(["tiny but mighty 🐾", "perfect 🐾", "BIG energy 💪"][min(max(level, 0), 2)], .happy, 2.2)
    }

    /// Sit still: she stays exactly where she is until you let her roam again.
    func toggleStay() {
        staying.toggle()
        Prefs.stay = staying
        if staying {
            walkTarget = nil
            followUntil = .distantPast
            say(Dialogue.line(.stay, species), .happy, 2.8)
            setAct(.sit, for: 4)
        } else {
            say(Dialogue.line(.unstay, species), .excited, 2.6)
            setAct(.idle, for: 1)
        }
        onYip?()
    }

    func dance() {
        guard act != .carried, act != .sleep else { return }
        lastInteraction = Date()
        walkTarget = nil
        setAct(.dance, for: 6)
        say(Dialogue.line(.dance, species), .happy, 3)
        happiness = min(1, happiness + 0.1)
        affection = min(1, affection + 0.03)
        emit(.sparkle, count: 6, at: Stage.aura, spread: 50)
        onYip?()
    }

    func wave() {
        guard act == .idle || act == .sit else { return }
        setAct(.wave, for: 2.6)
        say(Dialogue.line(.wave, species), .happy, 2.4)
    }

    func nap() {
        setAct(.sleep, for: 60)
        say(Dialogue.line(.sleepy, species), .sleepy, 3)
    }

    /// "Come here": she runs to your cursor and keeps following it for a few seconds, then
    /// sits beside it. (It used to run to wherever the cursor was at the instant of the
    /// click, which was the button you'd just pressed.)
    func comeHere() {
        guard act != .carried else { return }
        lastInteraction = Date()
        calledOver = true
        followUntil = Date().addingTimeInterval(8)
        if act == .sleep { setAct(.idle, for: 1) }
        say(Dialogue.line(.comeHere, species), .excited, 2.5)
        onYip?()
    }

    private func follow() {
        let dx = cursor.x - position.x
        let side: CGFloat = dx >= 0 ? -1 : 1            // stop on the side she came from
        let far = abs(dx) > 110
        if far {
            walkTarget = min(max(cursor.x + side * 70, minX), maxX)
            speedMultiplier = 2.4
            if act != .walk { setAct(.walk, for: 30) }
        } else {
            if act == .walk {
                walkTarget = nil
                if calledOver {
                    calledOver = false
                    say(Dialogue.line(.arrived, species), nil, 2.4)
                    moodOverride = (.shy, Date().addingTimeInterval(2.2))
                    emit(.heart, count: 3, at: Stage.aura, spread: 26)
                }
            }
            if act != .sit { setAct(.sit, for: 2) } else { actUntil = Date().addingTimeInterval(1) }
            let dir: Double = dx >= 0 ? 1 : -1
            if facing != dir { facing = dir }
        }
        // with free placement she comes up to wherever your cursor is, not just along the floor
        if Prefs.placeAnywhere {
            let y = clampY(cursor.y - 26)
            restY = y > groundY + 30 ? y : nil
            perchX = position.x
        }
    }

    func beginCarry() {
        cancelCloseSequence()
        lastInteraction = Date()
        setAct(.carried, for: 999)
        say(Dialogue.line(.picked, species), .dizzy, 1.6)
        onYip?()
    }

    func carry(to p: CGPoint, velocity v: CGVector) {
        // clamp against whichever display she's being dragged over, not the one she left
        let sc = NSScreen.screens.first { $0.frame.contains(p) } ?? screen
        let lo = sc.visibleFrame.minY + 2
        let hi = max(lo, sc.visibleFrame.maxY - (Design.height * scale) + 40)
        position = CGPoint(x: p.x, y: min(max(p.y, lo), hi))
        velocity = v
        act = .carried
    }

    func drop(velocity v: CGVector) {
        // "place her anywhere": let go and she stays right there, on a cushion. Let go
        // close to the floor and she settles onto it instead.
        if Prefs.placeAnywhere {
            let y = clampY(position.y)
            if y > groundY + 30 {
                restY = y
                perchX = position.x
                position.y = y
                velocity = .zero
                setAct(.idle, for: 1.6)
                squash = 0.4
                emit(.sparkle, count: 6, at: Stage.p(94, Design.ground), spread: 36)
                say(Dialogue.line(.placed, species), .happy, 2.4)
                onYip?()
                return
            }
        }
        restY = nil
        velocity = CGVector(dx: max(-500, min(500, v.dx)), dy: max(-900, min(500, v.dy)))
        setAct(.fall, for: 99)
        happiness = max(0, happiness - 0.01)
    }

    // MARK: Focus timer

    func startTimer(minutes: Double, isBreak: Bool = false) {
        timerTotal = minutes * 60
        timerEndsAt = Date().addingTimeInterval(timerTotal)
        timerIsBreak = isBreak
        lastTimerNudge = Date()
        if isBreak {
            say(Dialogue.line(.breakStart, species), .playful, 5)
            setAct(.sit, for: 20)
        } else {
            resetFocusStreak()
            ambienceHushed = false
            say(Dialogue.line(.timerStart, species, ["n": "\(Int(minutes))"]), .alert, 5)
            setAct(.sit, for: 20)
        }
        refreshAmbience()
        onYip?()
    }

    /// Starts a focus session with a stated intention: the one thing you're doing.
    func startFocus(minutes: Double, intention what: String) {
        intention = what
        startTimer(minutes: minutes)
    }

    func stopTimer() {
        guard timerEndsAt != nil else { return }
        let wasBreak = timerIsBreak
        timerEndsAt = nil
        timerIsBreak = false
        say(wasBreak ? Dialogue.line(.breakOver, species) : "timer stopped… we'll go again soon 🥺",
            wasBreak ? .happy : .sad, 3)
        refreshAmbience()
    }

    private func updateTimer() {
        guard let end = timerEndsAt else { return }
        let left = end.timeIntervalSinceNow
        if left <= 0 { finishTimer(); return }
        // a quiet check-in every 5 minutes so she isn't silent the whole session
        if !timerIsBreak, left > 70, Date().timeIntervalSince(lastTimerNudge) > 300 {
            lastTimerNudge = Date()
            say("\(Int(ceil(left / 60))) min left — still with me? 💗", .love, 4)
            emit(.heart, count: 3, at: Stage.aura, spread: 22)
        }
    }

    private func finishTimer() {
        let wasBreak = timerIsBreak
        let minutes = Int(timerTotal / 60)
        timerEndsAt = nil
        timerIsBreak = false
        refreshAmbience()

        if wasBreak {
            say(Dialogue.line(.breakOver, species), .excited, 5)
            setAct(.idle, for: 2)
            onYip?()
            return
        }

        dailySessions[Calendar.current.startOfDay(for: Date()), default: 0] += 1
        addBerries(10)
        checkBadges()
        happiness = min(1, happiness + 0.25)
        affection = min(1, affection + 0.15)
        addXP(Progression.Award.timerFinished)
        emit(.confetti, count: 16, at: Stage.aura, spread: 80)
        setAct(.love, for: 6)
        say(Dialogue.line(.timerDone, species, ["n": "\(minutes)"]), nil, 7)
        moodOverride = (.proud, Date().addingTimeInterval(3.5))   // proud first, melts into love after
        emit(.heart, count: 12, at: Stage.aura, spread: 60)
        emit(.sparkle, count: 8, at: Stage.aura, spread: 70)
        onYip?()

        // roll straight into a short break so the rhythm keeps going
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.timerEndsAt == nil else { return }
                self.startTimer(minutes: 5, isBreak: true)
            }
        }
    }

    // MARK: Focus coaching

    /// Looks at one moment of your day. `dt` is how many seconds actually passed since the last
    /// look (zero straight after a sleep or a stall, so a closed laptop never earns focus), and
    /// `idle` is how long since you last touched the keyboard or mouse.
    ///
    /// Being away only stops the *good* time counting: work, and the time spent in each app.
    /// A distraction still counts, because staring at a reel without touching anything is
    /// exactly the thing she's here to catch.
    func observe(_ v: Verdict, dt: Double, idle: Double = 0) {
        guard dt > 0 else { return }
        let grace = focusTimerRunning ? 300.0 : 150.0      // reading and thinking is still work
        let resting = idle > grace && v.kind != .distraction
        presenceNote = resting ? "resting: no keys or mouse for \(Int(idle / 60)) min" : ""
        let credit = resting ? 0 : dt

        currentActivity = v.label
        lastVerdict = v.kind
        if v.kind != .neutral && !v.siteKey.isEmpty {
            siteTime[v.siteKey, default: 0] += credit
        }
        // unlike siteTime this includes neutral time too, under "Other": the focus/
        // distraction ratio needs the full picture, not just the flagged categories
        categoryTime[v.ruleName == "—" ? "Other" : v.ruleName, default: 0] += credit

        // every app she's watched you in today, distraction or work or neither. This
        // is what a "what did I actually do today" report needs: siteTime above only
        // ever recorded apps a rule flagged, so Finder, Mail, anything with no rule
        // at all was invisible in "Where your time went" no matter how long it ran.
        if !v.siteKey.isEmpty {
            let today = Calendar.current.startOfDay(for: Date())
            dailyAppTime[today, default: [:]][v.siteKey, default: 0] += credit
            siteKinds[v.siteKey] = v.kind == .work ? "work" : (v.kind == .distraction ? "distraction" : "neutral")
        }
        if resting { dailyAway[Calendar.current.startOfDay(for: Date()), default: 0] += dt }
        // you stepped away from your work: nothing to count, and nothing to un-count either
        if resting && v.kind == .work { return }

        switch v.kind {
        case .distraction:
            focusSeconds = 0
            if onBreak {          // she earned you this break, so no barking
                distractSeconds = 0
                return
            }
            if Prefs.inQuietHours {   // quiet hours: she notices, but stays quiet
                distractSeconds = 0
                return
            }
            distractSeconds += dt
            dailyDistraction[Calendar.current.startOfDay(for: Date()), default: 0] += dt
            wasDistracted = true
            // during a focus timer her patience is much shorter
            var rule = v
            let vibe = Dialogue.effectiveVibe
            rule.delay = v.delay * vibe.patience
            if vibe == .gentle { rule.severity = 1 }
            if vibe == .drill { rule.severity = 2 }
            if focusTimerRunning {
                rule.delay = max(6, rule.delay * 0.4)
                if vibe != .gentle { rule.severity = max(2, rule.severity) }
            }
            if distractSeconds > rule.delay && Date() >= nextScold {
                scold(rule)
            }

        case .work:
            if wasDistracted && distractSeconds > 12 {
                say(Dialogue.coach(.backToWork, species), .happy, 4)
                emit(.sparkle, count: 8, at: Stage.aura, spread: 40)
                happiness = min(1, happiness + 0.08)
                onYip?()
            }
            wasDistracted = false
            distractSeconds = 0
            scoldCount = 0
            nextScold = .distantPast
            focusSeconds += dt
            creditFocus(dt)

            if focusSeconds >= nextMilestone {
                adore(minutes: Int(nextMilestone / 60), lines: v.lines)
                nextMilestone += (nextMilestone < 1800 ? 900 : 1800)
            } else if Date().timeIntervalSince(lastPraise) > 210 && act == .idle {
                lastPraise = Date()
                say(Dialogue.praise(rule: v.ruleName, storedLines: v.lines, species: species), .love, 4)
                emit(.heart, count: 3, at: Stage.aura, spread: 22)
            }

        case .neutral:
            distractSeconds = max(0, distractSeconds - dt * 0.7)
            focusSeconds = max(0, focusSeconds - dt * 0.25)
            // a session you started is focus, even in an app no rule knows (a PDF, a notes app, a
            // whiteboard). Only while you're really there, and never on a break.
            if focusTimerRunning && !resting { creditFocus(dt) }
        }
    }

    /// One place that turns seconds of real focus into minutes in every total: lifetime, today, the
    /// hour of day it happened in, plus the XP, berries and goal/streak checks that go with it.
    private func creditFocus(_ dt: Double) {
        let now = Date()
        let today = Calendar.current.startOfDay(for: now)
        totalFocusMinutes += dt / 60
        dailyFocus[today, default: 0] += dt / 60
        focusByHour[Calendar.current.component(.hour, from: now), default: 0] += dt / 60
        affection = min(1, affection + dt / 3600)

        // a small bonus for showing up at all today, then a steady drip per minute
        if lastXPDay != today {
            lastXPDay = today
            addXP(Progression.Award.dailyFirstFocus)
        }
        let flow = inFlow ? 1.5 : 1.0
        addXP(Progression.Award.focusMinute * flow * dt / 60)
        addBerries(flow * dt / 60)
        checkGoalAndStreak()
    }

    private func scold(_ v: Verdict) {
        barksGiven += 1
        dailyBarks[Calendar.current.startOfDay(for: Date()), default: 0] += 1
        scoldCount += 1
        setAct(.bark, for: v.severity >= 2 ? 3.4 : 2.4)
        walkTarget = nil
        happiness = max(0, happiness - 0.03)

        let line = Dialogue.scold(rule: v.ruleName, storedLines: v.lines, species: species, count: scoldCount)
        say(line, .angry, v.severity >= 2 ? 5 : 4)
        emit(.anger, count: v.severity >= 2 ? 6 : 3, at: Stage.aura, spread: 45)
        if v.severity >= 2 { onBark?() } else { onWhine?() }

        // one warning bark first, then: if it's still a Reels tab and she hasn't
        // been left alone, she closes it herself. `== 2` (not `>=`) so this only
        // ever fires once per escalation streak, not every 25s if it keeps failing.
        // Let the bark itself play out for a beat before she launches into the
        // reach-and-tap animation, instead of the two acts colliding on one frame.
        let shortForm = ["Reels & short-form video", "Guard: TikTok", "Guard: Instagram"]
        if scoldCount == 2, Prefs.autoCloseReels, shortForm.contains(v.ruleName) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
                self?.performCloseTap()
            }
        }

        // escalate: 45s, then 35s, then every 25s until they behave
        let gap = max(25.0, 55.0 - Double(scoldCount) * 10) * Dialogue.effectiveVibe.gap
        nextScold = Date().addingTimeInterval(gap)
    }

    private func adore(minutes: Int, lines: [String]) {
        setAct(.love, for: 5)
        happiness = min(1, happiness + 0.15)
        affection = min(1, affection + 0.12)
        say(Dialogue.line(.milestone, species, ["n": "\(minutes)"]), .love, 6)
        emit(.heart, count: 10, at: Stage.aura, spread: 55)
        emit(.sparkle, count: 6, at: Stage.body, spread: 60)
        onYip?()
    }

    func resetFocusStreak() {
        focusSeconds = 0
        nextMilestone = 10 * 60
    }

    // MARK: Daily goal, streak and to-dos

    var focusTodayMinutes: Double { dailyFocus[Calendar.current.startOfDay(for: Date())] ?? 0 }
    var goalProgress: Double { min(1, focusTodayMinutes / Double(max(1, dailyGoal))) }
    var sessionsToday: Int { dailySessions[Calendar.current.startOfDay(for: Date())] ?? 0 }

    /// Days in a row with at least five focused minutes. Today counts once it has them;
    /// until then the run is measured up to yesterday, so a fresh morning doesn't read 0.
    var streakDays: Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: Date())
        if (dailyFocus[day] ?? 0) < 5, let y = cal.date(byAdding: .day, value: -1, to: day) { day = y }
        var n = 0
        while (dailyFocus[day] ?? 0) >= 5 {
            n += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return n
    }

    // MARK: History helpers (for stats and badges)

    var bestStreakDays: Int {
        let cal = Calendar.current
        var best = 0, run = 0
        var prev: Date?
        for d in dailyFocus.filter({ $0.value >= 5 }).keys.sorted() {
            if let p = prev, cal.date(byAdding: .day, value: 1, to: p) == d { run += 1 } else { run = 1 }
            best = max(best, run)
            prev = d
        }
        return best
    }
    var mostFocusInADay: Double { dailyFocus.values.max() ?? 0 }
    var daysAtGoal: Int { dailyFocus.values.filter { $0 >= Double(dailyGoal) }.count }
    var totalSessions: Int { dailySessions.values.reduce(0, +) }
    var totalTasksDone: Int { dailyTasks.values.reduce(0, +) }

    /// Awards any badge whose milestone has been reached. The first ever check just counts
    /// what you'd already done, quietly: otherwise updating would announce a dozen at once.
    func checkBadges() {
        lastBadgeCheck = Date()
        var earned = Prefs.badges
        let fresh = Badges.all.filter { !earned.contains($0.id) && $0.isEarned(self) }
        guard !fresh.isEmpty else { Prefs.badgesSeeded = true; return }
        fresh.forEach { earned.insert($0.id) }
        Prefs.badges = earned
        if Prefs.badgesSeeded { addBerries(Double(15 * fresh.count)) }
        guard Prefs.badgesSeeded else { Prefs.badgesSeeded = true; return }
        let b = fresh[0]
        let more = fresh.count > 1 ? " (+\(fresh.count - 1) more!)" : ""
        setAct(.love, for: 4)
        say("new badge \(b.emoji) \(b.title)!\(more)", .proud, 5.5)
        onBell?()
        emit(.confetti, count: 18, at: Stage.aura, spread: 80)
        onYip?()
        for (i, badge) in fresh.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 5.5) { [weak self] in self?.onBadge?(badge) }
        }
    }

    /// Days with an hour of focus and no barking at all.
    var angelDays: Int {
        dailyFocus.filter { $0.value >= 60 && (dailyBarks[$0.key] ?? 0) == 0 }.count
    }

    // MARK: Daily habits

    var habitsDone: Set<String> { Habits.done() }

    func toggleHabit(_ id: String) {
        var done = Habits.done()
        if done.contains(id) { done.remove(id); Habits.set(done); objectWillChange.send(); return }
        complete(habit: id)
    }

    private func complete(habit id: String) {
        var done = Habits.done()
        guard !done.contains(id), let h = Habits.all.first(where: { $0.id == id }) else { return }
        done.insert(id)
        Habits.set(done)
        addXP(Habits.xp)
        addBerries(Double(Habits.berries))
        onBell?()
        emit(.sparkle, count: 6, at: Stage.aura, spread: 44)
        if done.count == Habits.all.count {
            Habits.perfectDays += 1
            addBerries(Double(Habits.bonusBerries))
            setAct(.love, for: 4)
            emit(.confetti, count: 16, at: Stage.aura, spread: 80)
            say("every little habit done 🌷 that's +\(Habits.bonusBerries) 🍓 just for taking care of you", .proud, 6)
            checkBadges()
        } else {
            say("\(h.emoji) \(h.title.lowercased()), done! +\(Int(Habits.xp)) xp", .happy, 3)
        }
        objectWillChange.send()
        onNeedsSave?()
    }

    /// Habits that tick themselves ("focus for 25 minutes") once you've done the thing.
    private func autoCompleteHabits() {
        let done = Habits.done()
        for h in Habits.all where !done.contains(h.id) {
            if let auto = h.auto, auto(self) { complete(habit: h.id) }
        }
    }

    /// Noting the hours you focus at, for the "Early bird" and "Night owl" badges.
    private func noteTimeOfDay() {
        let h = Calendar.current.component(.hour, from: Date())
        if h >= 5 && h < 8 { if !Prefs.earlyBird { Prefs.earlyBird = true } }
        if h >= 23 || h < 4 { if !Prefs.nightOwl { Prefs.nightOwl = true } }
    }

    func setGoal(_ minutes: Int) {
        dailyGoal = min(480, max(10, minutes))
        Prefs.dailyGoal = dailyGoal
    }

    private func checkGoalAndStreak() {
        let today = Calendar.current.startOfDay(for: Date())
        if Date().timeIntervalSince(lastBadgeCheck) > 45 { checkBadges(); autoCompleteHabits(); noteTimeOfDay() }
        if focusTodayMinutes >= 5, streakAnnouncedDay != today {
            streakAnnouncedDay = today
            let n = streakDays
            if n >= 2 {
                say(Dialogue.line(.streak, species, ["n": "\(n)"]), .proud, 4.5)
                emit(.sparkle, count: 8, at: Stage.aura, spread: 50)
            }
        }
        if focusTodayMinutes >= Double(dailyGoal), Prefs.goalDay != today {
            Prefs.goalDay = today
            setAct(.love, for: 6)
            say(Dialogue.line(.goalDone, species, ["n": Focus.timeText(Double(dailyGoal))]), nil, 7)
            moodOverride = (.proud, Date().addingTimeInterval(4))
            emit(.confetti, count: 24, at: Stage.aura, spread: 100)
            emit(.heart, count: 8, at: Stage.aura, spread: 60)
            addXP(30)
            addBerries(25)
            onYip?()
        }
    }

    func addTask(_ title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, tasks.count < 40 else { return }
        tasks.append(FocusTask(title: String(t.prefix(80))))
        onNeedsSave?()
    }

    func toggleTask(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].done.toggle()
        let today = Calendar.current.startOfDay(for: Date())
        dailyTasks[today] = max(0, (dailyTasks[today] ?? 0) + (tasks[i].done ? 1 : -1))
        onNeedsSave?()
        guard tasks[i].done else { return }
        defer { checkBadges() }
        lastInteraction = Date()
        addXP(Progression.Award.task)
        addBerries(3)
        onBell?()
        emit(.sparkle, count: 6, at: Stage.aura, spread: 40)
        onYip?()
        if tasks.allSatisfy(\.done), tasks.count >= 2 {
            setAct(.love, for: 4)
            say(Dialogue.line(.allDone, species), nil, 5)
            emit(.confetti, count: 20, at: Stage.aura, spread: 90)
        } else {
            say(Dialogue.line(.taskDone, species), .proud, 2.6)
        }
    }

    func removeTask(_ id: UUID) {
        tasks.removeAll { $0.id == id }
        onNeedsSave?()
    }

    func clearDoneTasks() {
        tasks.removeAll(where: \.done)
        onNeedsSave?()
    }

    // MARK: Study sound

    var ambiencePlaying: Bool {
        ambience != .off && Prefs.sounds && !ambienceHushed && (focusTimerRunning || ambienceManual)
    }

    /// Picks a station and starts it straight away.
    func chooseAmbience(_ a: Ambience) {
        ambience = a
        Prefs.ambience = a
        ambienceManual = a != .off
        ambienceHushed = false
        if a != .off, !Prefs.sounds { Prefs.sounds = true }     // choosing music means you want to hear it
        refreshAmbience()
    }

    /// The one big play button: starts the last station, or pauses it.
    func toggleAmbienceNow() {
        if ambiencePlaying {
            ambienceManual = false
            ambienceHushed = true
        } else {
            if ambience == .off { ambience = .lofi; Prefs.ambience = .lofi }
            if !Prefs.sounds { Prefs.sounds = true }
            ambienceManual = true
            ambienceHushed = false
        }
        refreshAmbience()
    }

    /// The header's quick-mute: silences her voice *and* the music, and brings both back.
    func toggleMute() {
        Prefs.sounds.toggle()
        if Prefs.sounds { SoundKit.shared.click() }
        refreshAmbience()
    }

    /// Plays the study sound while a focus timer runs, or when it was started by hand.
    func refreshAmbience() {
        SoundKit.shared.ambience(ambience, playing: ambiencePlaying, volume: Prefs.ambienceVolume)
        objectWillChange.send()
    }

    /// Her head-bob locks onto the beat of her own music. (To bop to *other* apps' music see
    /// `beat(strength:)`, which `MusicBeatDetector` drives.)
    private func updateMusicBop() {
        guard let b = SoundKit.shared.musicBeat() else { lastMusicBeat = -1; return }
        guard b != lastMusicBeat else { return }
        lastMusicBeat = b
        beat(strength: b % 4 == 0 ? 0.95 : 0.55)
    }

    // MARK: Gentle reminders

    /// A water break, a stretch, and the 20-20-20 eye rest: said kindly, never during
    /// quiet hours, and never while she's asleep or being carried.
    private func updateReminders() {
        let now = Date()
        guard now.timeIntervalSince(lastReminderCheck) > 5 else { return }
        lastReminderCheck = now
        guard Prefs.reminders, !Prefs.inQuietHours, act != .sleep, act != .carried, bubbleText == nil else { return }

        if now.timeIntervalSince(lastWater) > 50 * 60 {
            lastWater = now
            say(Dialogue.line(.water, species), .happy, 5)
            emit(.bubble, count: 5, at: Stage.aura, spread: 30)
            onYip?()
        } else if now.timeIntervalSince(lastStretch) > 40 * 60 {
            lastStretch = now
            say(Dialogue.line(.stretchRemind, species), .happy, 5)
            if !focusTimerRunning { setAct(.stretch, for: 2.6) }
            onYip?()
        } else if focusTimerRunning && now.timeIntervalSince(lastEyes) > 20 * 60 {
            lastEyes = now
            say(Dialogue.line(.eyes, species), .happy, 5)
            onYip?()
        }
    }

    func noteScreenOff() { presenceNote = "paused: screen is locked" }

    func humanIsAway(_ away: Bool) {
        if away && act != .sleep && act != .carried {
            setAct(.sleep, for: 300)
        } else if !away && act == .sleep && energy > 0.35 {
            lastWater = Date(); lastStretch = Date(); lastEyes = Date()
            setAct(.wave, for: 2.6)
            say(Dialogue.line(.wokeUp, species), .excited, 3)
        }
    }
}

// MARK: - Easing off

/// How hard to ease off drawing: 1 is normal, lower on battery saver, a hot Mac, or one that is already
/// busy. Re-read every few seconds, never per frame.
@MainActor
enum Throttle {
    private(set) static var factor = 1.0

    static func refresh() {
        let p = ProcessInfo.processInfo
        var f = 1.0
        if p.isLowPowerModeEnabled { f = min(f, 0.6) }
        switch p.thermalState {
        case .serious, .critical: f = min(f, 0.45)
        case .fair: f = min(f, 0.75)
        default: break
        }
        var load = [Double](repeating: 0, count: 1)
        if getloadavg(&load, 1) == 1 {
            let perCore = load[0] / Double(max(1, p.activeProcessorCount))
            if perCore > 0.9 { f = min(f, 0.6) } else if perCore > 0.6 { f = min(f, 0.8) }
        }
        factor = f
    }
}

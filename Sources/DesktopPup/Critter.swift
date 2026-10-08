import SwiftUI

// One renderer for every animal. A species only decides its ears, tail, nose and a
// few face markings; the skeleton, the animation and the expressions are shared, so
// every pet moves with the same polish and a new species costs a few dozen lines.
//
// Design space is 200 x 168 with the paws on y = 152, facing right. `Design.lift`
// extra rows of headroom sit above that for tall ears and hops.

/// Her idle animation repeats every `period` seconds: every wave in the art turns a whole number of half-turns in
/// that time, and every event (blink, ear flick, tongue) happens on a fixed beat inside it. That makes her frames a
/// finite set, which is what lets them be drawn once, kept, and replayed instead of redrawn.
enum Loop {
    static let period = 4 * Double.pi
    /// A drawn frame is snapped to this grid (`steps` frames per period, about 12 a second).
    static let steps = 150
    static var step: Double { period / Double(steps) }
    static let blinkEvery = period / 4
    /// At rest the clock moves this many grid steps at a time (every half second)...
    static let coarse = 6
    /// ...except while a blink or an ear flick is happening, which need the fine grid to read.
    static func eventActive(at t: Double) -> Bool {
        t.truncatingRemainder(dividingBy: blinkEvery) < 0.46 || t.truncatingRemainder(dividingBy: period / 2) < 0.34
    }
    /// How lively her frames need to be right now at rest: the pace to tick at from just before a blink or an ear
    /// flick starts until it ends (they are over in a fraction of a second), a gentler one for a tongue blep, and
    /// none at all otherwise.
    static func eventPace(at t: Double) -> Double? {
        if (t + 0.12).truncatingRemainder(dividingBy: blinkEvery) < 0.55 || (t + 0.12).truncatingRemainder(dividingBy: period / 2) < 0.45 { return 12 }
        if (t + 0.2).truncatingRemainder(dividingBy: period) < 1.4 { return 6 }
        return nil
    }
}

struct CritterView: View {
    var species: Species
    var coat: Int = 0
    var pose: Pose
    /// Drawn straight at this size instead of drawing big and shrinking it: the pet on
    /// screen is about a quarter the area of her design space, so this skips ~70% of the pixels.
    var scale: CGFloat = 1

    var body: some View {
        Canvas { ctx, _ in
            var c = ctx
            c.scaleBy(x: scale, y: scale)
            let coats = species.coats
            Critter(species: species, coat: coats[min(max(coat, 0), coats.count - 1)], p: pose).draw(c)
        }
        .frame(width: Design.width * scale, height: Design.height * scale)
    }
}

// MARK: - Anatomy

private enum G {
    // chibi proportions: the head is most of the animal, the body a small soft bean
    static let bodyC = CGPoint(x: 76, y: 128)
    static let bodyW = 64.0
    static let bodyH = 46.0

    static let headC = CGPoint(x: 116, y: 70)
    /// Where the head turns: the bottom of the chin, so a tilt reads as a neck bend.
    static let neck = CGPoint(x: 110, y: 116)

    // wide-set and low on a big head: more forehead above the eyes is what reads as
    // babyish, which is the whole cuteness game
    static let eyeL = CGPoint(x: 90, y: 82)
    static let eyeR = CGPoint(x: 142, y: 80)
    static let muzzleC = CGPoint(x: 118, y: 100)
    static let noseC = CGPoint(x: 118, y: 94)

    static let hipY = 133.0
    static let ground = Double(Design.ground)
    static let legsX: [Double] = [46, 60, 84, 98]     // back-far, back-near, front-far, front-near
    static let rear = CGPoint(x: 46, y: 150)          // the torso pitches about here
    static let tailBase = CGPoint(x: 41, y: 122)
}

private let eyeInk = Color(red: 0.20, green: 0.17, blue: 0.25)
private let nosePink = Color(red: 0.93, green: 0.56, blue: 0.64)

// MARK: - The critter

struct Critter {
    let species: Species
    let coat: Coat
    let p: Pose

    private var T: Double { p.phase }

    // MARK: Species traits

    private var headW: Double {
        switch species {
        case .cat: return 126
        case .dog: return 124
        case .bunny: return 112
        case .fox: return 120
        case .panda: return 126
        case .hamster: return 134
        case .axolotl: return 134
        case .capybara: return 130
        }
    }
    private var headH: Double {
        switch species {
        case .cat: return 102
        case .dog: return 102
        case .bunny: return 98
        case .fox: return 94
        case .panda: return 104
        case .hamster: return 108
        case .axolotl: return 94
        case .capybara: return 90
        }
    }
    /// Each animal gets its own silhouette: a chubby-cheeked hamster, a flat wide axolotl, a
    /// loaf-shaped capybara. The ovals were why half the cast read as the same animal.
    private var headPath: Path {
        let (cx, cy) = (G.headC.x, G.headC.y)
        switch species {
        case .cat:      return softBlob(cx, cy, headW, headH, topW: 0.94, botW: 1.12, square: 0.1, sideY: 0.08)
        case .dog:      return softBlob(cx, cy, headW, headH, topW: 1.0, botW: 1.04, square: 0.16, sideY: 0.06)
        case .hamster:  return softBlob(cx, cy, headW, headH, topW: 0.8, botW: 1.2, square: 0.18, sideY: 0.14)
        case .axolotl:  return softBlob(cx, cy, headW, headH, topW: 1.0, botW: 1.08, square: 0.4, sideY: 0.1)
        case .capybara: return softBlob(cx, cy, headW, headH, topW: 1.0, botW: 1.0, square: 0.7, sideY: 0.04)
        default:        return ovalPath(cx, cy, headW, headH)
        }
    }
    private var bodyPath: Path { ovalPath(G.bodyC.x, G.bodyC.y, G.bodyW, G.bodyH) }
    private var rim: Color { coat.shade.opacity(0.55) }
    /// Head gradient: a hamster has a pale face under a coloured cap, everyone else is one tone.
    private var headTones: (Color, Color) { species == .hamster ? (coat.belly, coat.light) : (coat.light, coat.mid) }

    // MARK: Emotion-driven values

    private var hopAmount: Double {
        guard p.sleep < 0.5, !p.dangling else { return 0 }
        var h = 0.0
        switch p.emotion {
        case .excited, .playful, .blissful, .hyped: h = abs(sin(T * 7))
        case .love, .proud: h = abs(sin(T * 3.5)) * 0.4
        default: break
        }
        if p.dance > 0.01 { h = max(h, abs(sin(T * 6)) * p.dance) }
        return h
    }

    private var walkBob: Double {
        -abs(sin(p.gait)) * 3.4 * p.walk * (1 + 0.4 * p.run)
    }

    /// Chest rising and falling: a pet that never moves reads as a sticker.
    private var breathe: Double { sin(T * (p.sleep > 0.5 ? 1.5 : 2)) }

    private var tailSpeedAmp: (Double, Double) {
        if p.dance > 0.3 { return (14, 32) }
        switch p.emotion {
        case .love, .excited, .playful, .blissful, .hyped: return (15, 34)
        case .vibing: return (7, 18)
        case .cozy: return (2.5, 6)
        case .moody: return (2, 5)
        case .happy, .eating, .proud: return (9, 22)
        case .angry: return (14, 14)
        case .sleepy, .bored: return (1, 4)
        case .sad, .worried: return (1.5, 3)
        case .shy: return (2.4, 7)
        case .curious: return (5.5, 12)
        default: return (4, 12)
        }
    }

    /// Ear angle in degrees. Positive tips outward for upright ears, and swings a
    /// hanging ear inward: so the same numbers feel right for both kinds.
    private var earPerk: Double {
        switch p.emotion {
        case .alert, .angry, .excited, .blissful, .hyped: return -11 - abs(sin(T * 6)) * 4
        case .vibing: return sin(T * 4) * 5 + p.bop * 8
        case .cozy: return 6
        case .moody: return 16
        case .playful, .proud: return -5
        case .sad, .sleepy, .bored: return 22
        case .hungry, .worried: return 9
        case .curious: return -8
        case .shy: return 13
        default: return sin(T * 2.5) * 3
        }
    }

    /// A single ear flick every few seconds: the "someone's alive in there" tell.
    private var earTwitch: Double {
        if let e = p.events { return e.flick * 11 }
        return Self.flick(at: T, sleep: p.sleep) * 11
    }

    /// -1...1: one flick of the ear on a fixed beat.
    static func flick(at t: Double, sleep: Double) -> Double {
        let ph = (t / (Loop.period / 2)).truncatingRemainder(dividingBy: 1)
        guard ph < 0.045, sleep < 0.5 else { return 0 }
        return sin(ph / 0.045 * .pi * 2)
    }

    /// 0...1: how far shut the eyes are in a blink, on a fixed beat (every other blink is a double).
    static func blink(at t: Double, emotion: Emotion) -> Double {
        switch emotion {
        case .sleepy, .love, .happy, .eating, .angry, .sad, .shy, .proud, .bored, .blissful, .cozy, .vibing: return 0
        default: break
        }
        let period = Loop.blinkEvery
        let n = Int(t / period)
        let cyc = t.truncatingRemainder(dividingBy: period)
        func lid(_ t: Double, _ len: Double) -> Double { (t >= 0 && t < len) ? sin(t / len * .pi) : 0 }
        var v = lid(cyc, 0.14)
        if n % 3 == 0 { v = max(v, lid(cyc - 0.26, 0.12)) }
        return v
    }

    /// 0...1: the tongue's little blep, when she's just hanging out.
    static func blep(at t: Double, emotion: Emotion, sleep: Double, walk: Double) -> Double {
        let calm = emotion == .happy || emotion == .neutral || emotion == .curious
        let phase = t.truncatingRemainder(dividingBy: Loop.period)
        return (calm && sleep < 0.3 && walk < 0.3 && phase < 1.1) ? sin(phase / 1.1 * .pi) : 0
    }

    private var blink: Double {
        if let e = p.events { return e.blink }
        return Self.blink(at: T, emotion: p.emotion)
    }

    private var irisColor: Color {
        switch species {
        case .cat: return coat.name == "Ginger" ? Color(red: 0.98, green: 0.66, blue: 0.25)
            : (coat.name == "Cloud" ? Color(red: 0.42, green: 0.70, blue: 1.0) : Color(red: 0.66, green: 0.52, blue: 0.95))
        case .dog: return Color(red: 0.86, green: 0.52, blue: 0.30)
        case .bunny: return Color(red: 0.95, green: 0.45, blue: 0.58)
        case .fox: return Color(red: 1.0, green: 0.70, blue: 0.22)
        case .panda: return Color(red: 0.50, green: 0.62, blue: 0.85)
        case .hamster: return Color(red: 0.78, green: 0.52, blue: 0.40)
        case .axolotl: return Color(red: 0.90, green: 0.50, blue: 0.80)
        case .capybara: return Color(red: 0.70, green: 0.46, blue: 0.30)
        }
    }

    // MARK: Draw

    func draw(_ base: GraphicsContext) {
        var ctx = base
        ctx.translateBy(x: 0, y: Design.lift)

        let hop = hopAmount
        let sh = 1 - hop * 0.2
        if p.outfit.rug != .none {
            drawRug(ctx, hop: hop)
        } else if p.perched {
            drawCushion(ctx, hop: hop)
        } else {
            ctx.fill(ovalPath(94, Design.ground + 4, 100 * sh * (1 + 0.12 * p.sleep), 13 * sh),
                     with: .color(.black.opacity(0.12)))
        }

        // facing: eased through zero, so a turn reads as a quick pivot
        // (a floor on the width keeps the pivot from becoming a paper-thin sliver)
        let turnWidth = (p.facing < 0 ? -1.0 : 1.0) * max(pow(abs(p.facing), 0.6), 0.3)
        ctx.translateBy(x: 0, y: -3 * (1 - abs(p.facing)))
        ctx.scale(x: turnWidth, y: 1, about: CGPoint(x: Design.centerX, y: 0))

        // squash and stretch, anchored on the ground. Hopping stretches at the apex
        // and squashes on landing; running leans into a longer body.
        var sy = 1 - p.squash * 0.16
        var sx = 1 + p.squash * 0.16
        if hopAmount > 0 || p.emotion == .excited || p.emotion == .playful || p.emotion == .blissful {
            let k = (hop - 0.5) * 0.14
            sy += k; sx -= k * 0.8
        }
        sx *= 1 + 0.04 * p.run
        ctx.scale(x: sx, y: sy, about: CGPoint(x: Design.centerX, y: G.ground))
        if p.bop > 0.01 { ctx.scale(x: 1 + 0.03 * p.bop, y: 1 - 0.05 * p.bop, about: CGPoint(x: Design.centerX, y: G.ground)) }
        if p.dance > 0.01 {
            // a side-to-side groove, once per two hops
            ctx.rotate(degrees: sin(T * 3) * 7 * p.dance, about: CGPoint(x: Design.centerX, y: G.ground))
        }

        if p.dangling {
            ctx.scale(x: 0.96, y: 1.07, about: CGPoint(x: Design.centerX, y: 24))
            ctx.rotate(degrees: sin(T * 2.5) * 7, about: CGPoint(x: Design.centerX, y: 24))
        }

        let pitch = -16 * p.sit - 5 * p.sleep + 8 * p.stretch + 6 * p.sniff + 3 * p.run + sin(p.gait * 2 + 0.6) * 1.6 * p.walk
        let drop = 10 * p.sleep
        var air = ctx
        air.translateBy(x: 0, y: walkBob - hop * 7)

        drawAura(air, front: false)
        drawLegs(air, front: false, pitch: pitch, drop: drop)
        if p.sit > 0.01 { drawHindFoot(air) }

        var torso = air
        torso.translateBy(x: 0, y: drop)
        torso.rotate(degrees: pitch, about: G.rear)
        drawBodyBack(torso)
        drawTail(torso)
        drawBody(torso)
        drawBodyFront(torso)
        drawLegs(torso, front: true, pitch: pitch, drop: drop)
        if p.outfit.neck == .none {
            // the collar she earned by levelling up, unless she's chosen something else to wear
            drawCollar(torso, tier: p.collarTier,
                       at: CGPoint(x: G.headC.x - 12, y: G.headC.y + headH / 2 - 2), width: 44)
        } else {
            drawNeckItem(torso)
        }
        drawHead(torso)
        drawWavingPaw(torso)
        if p.propAmt > 0.01 { drawProp(air) }
        drawAura(air, front: true)
    }

    // MARK: Rug, aura, clothes

    /// The rug she sits on: drawn first, under everything. It replaces the plain shadow (or the
    /// perch cushion) while she has one.
    private func drawRug(_ ctx: GraphicsContext, hop: Double) {
        var c = ctx
        let squeeze = 1 - hop * 0.05
        let cx = 100.0, cy = Double(Design.ground) + 5
        c.fill(ovalPath(cx, cy + 8, 150 * squeeze, 14), with: .color(.black.opacity(0.10)))
        switch p.outfit.rug {
        case .rugCoquette:
            // a cream rug with a lace scalloped edge and a little pink ribbon
            let base = ovalPath(cx, cy, 148, 28)
            c.fill(base, with: .linearGradient(Gradient(colors: [Color(red: 1.0, green: 0.98, blue: 0.95), Color(red: 0.99, green: 0.90, blue: 0.91)]),
                                               startPoint: CGPoint(x: cx, y: cy - 14), endPoint: CGPoint(x: cx, y: cy + 14)))
            for i in 0..<22 {
                let a = Double(i) / 22 * .pi * 2
                c.fill(ovalPath(cx + cos(a) * 74, cy + sin(a) * 14, 7, 5), with: .color(.white))
            }
            c.stroke(ovalPath(cx, cy, 126, 20), with: .color(Color(red: 0.97, green: 0.66, blue: 0.76)), style: StrokeStyle(lineWidth: 1.6, dash: [4, 3]))
            c.stroke(base, with: .color(Color(red: 0.93, green: 0.78, blue: 0.80)), lineWidth: 1.2)
            for sd in [-1.0, 1.0] { c.fill(ovalPath(cx + 52 + sd * 5, cy + 3, 9, 6), with: .color(Color(red: 0.98, green: 0.58, blue: 0.72))) }
            c.fill(ovalPath(cx + 52, cy + 3, 4.5, 4.5), with: .color(Color(red: 0.88, green: 0.42, blue: 0.58)))

        case .rugCottage:
            let base = ovalPath(cx, cy, 148, 28)
            c.fill(base, with: .linearGradient(Gradient(colors: [Color(red: 0.80, green: 0.92, blue: 0.72), Color(red: 0.62, green: 0.82, blue: 0.58)]),
                                               startPoint: CGPoint(x: cx, y: cy - 14), endPoint: CGPoint(x: cx, y: cy + 14)))
            c.stroke(base, with: .color(Color(red: 0.46, green: 0.68, blue: 0.44)), lineWidth: 1.6)
            for (i, dx) in [-52.0, -32.0, -12.0, 8.0, 28.0, 50.0].enumerated() {
                var l = c
                l.translateBy(x: cx + dx, y: cy + (i % 2 == 0 ? -3 : 4))
                l.rotate(by: .degrees(Double(i) * 37 - 60))
                l.fill(ovalPath(0, 0, 11, 5), with: .color(Color(red: 0.42, green: 0.66, blue: 0.40).opacity(0.75)))
            }
            for (dx, dy) in [(-62.0, 1.0), (60.0, -2.0), (-20.0, 7.0), (30.0, 8.0)] {
                c.fill(ovalPath(cx + dx, cy + dy, 5, 5), with: .color(.white))
                c.fill(ovalPath(cx + dx, cy + dy, 2, 2), with: .color(Color(red: 1.0, green: 0.84, blue: 0.4)))
            }

        case .rugY2K:
            // a glittery hot pink heart, flattened into a rug
            var h = c
            h.translateBy(x: cx, y: cy + 1)
            h.scaleBy(x: 1.7, y: 0.36)
            let heart = heartPath(center: .zero, size: 78)
            h.fill(heart, with: .linearGradient(Gradient(colors: [Color(red: 1.0, green: 0.60, blue: 0.82), Color(red: 0.98, green: 0.36, blue: 0.64)]),
                                                 startPoint: CGPoint(x: 0, y: -39), endPoint: CGPoint(x: 0, y: 39)))
            h.stroke(heart, with: .color(.white.opacity(0.85)), lineWidth: 3.2)
            for i in 0..<9 {
                let tw = 0.5 + 0.5 * sin(T * 3 + Double(i) * 1.7)
                let x = cx + Double(i - 4) * 14 + (i % 2 == 0 ? 3 : -3)
                c.fill(starPath(1.0 + tw * 2.2).applying(CGAffineTransform(translationX: x, y: cy + (i % 3 == 0 ? -4 : 3))), with: .color(.white.opacity(0.5 + tw * 0.5)))
            }

        case .rugCyber:
            let base = ovalPath(cx, cy, 148, 28)
            c.fill(base, with: .linearGradient(Gradient(colors: [Color(red: 0.24, green: 0.20, blue: 0.40), Color(red: 0.12, green: 0.10, blue: 0.24)]),
                                               startPoint: CGPoint(x: cx, y: cy - 14), endPoint: CGPoint(x: cx, y: cy + 14)))
            let neon = Color(red: 0.36, green: 0.96, blue: 0.88)
            c.stroke(base, with: .color(neon.opacity(0.3)), lineWidth: 7)
            c.stroke(base, with: .color(neon), lineWidth: 2)
            let pulse = 0.5 + 0.5 * sin(T * 2)
            c.stroke(ovalPath(cx, cy, 104 + pulse * 6, 17 + pulse), with: .color(Color(red: 0.82, green: 0.52, blue: 1.0).opacity(0.55)), lineWidth: 1.6)
            c.stroke(ovalPath(cx, cy, 60, 10), with: .color(neon.opacity(0.35)), lineWidth: 1.2)
        default: break
        }
    }

    /// Floating sparkles, hearts or stars drifting round her: half pass behind her, half in front.
    private func drawAura(_ ctx: GraphicsContext, front: Bool) {
        guard p.outfit.aura != .none else { return }
        for i in 0..<7 {
            let a = T * 1 + Double(i) * (.pi * 2 / 7)
            let side = sin(a)                       // > 0: on the near side of her
            guard (side > 0) == front else { continue }
            let x = 100 + cos(a) * 84
            let y = 82 + side * 22 + sin(T * 1.5 + Double(i)) * 6 - Double(i % 3) * 9
            let tw = 0.55 + 0.45 * sin(T * 3 + Double(i) * 2.1)
            var c = ctx
            c.opacity = 0.55 + 0.45 * tw
            c.translateBy(x: x, y: y)
            switch p.outfit.aura {
            case .auraHearts:
                c.fill(heartPath(center: .zero, size: 9 + tw * 5), with: .color(Fur.heart))
            case .auraStars:
                c.rotate(by: .degrees(T * 43 + Double(i) * 30))
                c.fill(starPath(5 + tw * 3), with: .color(Color(red: 1.0, green: 0.86, blue: 0.36)))
            default:
                // four-point sparkle
                var sp = Path()
                let r = 3.5 + tw * 4, k = r * 0.28
                sp.move(to: CGPoint(x: 0, y: -r)); sp.addLine(to: CGPoint(x: k, y: -k)); sp.addLine(to: CGPoint(x: r, y: 0))
                sp.addLine(to: CGPoint(x: k, y: k)); sp.addLine(to: CGPoint(x: 0, y: r)); sp.addLine(to: CGPoint(x: -k, y: k))
                sp.addLine(to: CGPoint(x: -r, y: 0)); sp.addLine(to: CGPoint(x: -k, y: -k)); sp.closeSubpath()
                c.fill(sp, with: .color(Color(red: 1.0, green: 0.97, blue: 0.7)))
            }
        }
    }

    /// Things worn on the body that sit *behind* her: wings and a cape.
    private func drawBodyBack(_ ctx: GraphicsContext) {
        switch p.outfit.body {
        case .angelWings:
            // fanned up and out behind her back, clear of the big head
            let flap = sin(T * 3.5 + p.gait) * 7 * (0.5 + p.walk) + sin(T * 2) * 2
            for (i, tilt) in [-12.0, 6.0].enumerated() {           // far wing, then the near one
                var w = ctx
                w.translateBy(x: G.bodyC.x - 10, y: G.bodyC.y - 20)
                w.rotate(by: .degrees(tilt + (i == 0 ? flap : -flap * 0.7)))
                for (j, len) in [54.0, 49.0, 43.0, 36.0].enumerated() {
                    var f = w
                    f.rotate(by: .degrees(-158 + Double(j) * 17))
                    let feather = ovalPath(len * 0.5, 0, len, 16 - Double(j) * 1.5)
                    f.fill(feather, with: .linearGradient(Gradient(colors: [.white, Color(red: 0.86, green: 0.89, blue: 1.0)]),
                                                        startPoint: .zero, endPoint: CGPoint(x: len, y: 0)))
                    f.stroke(feather, with: .color(Color(red: 0.72, green: 0.76, blue: 0.95)), lineWidth: 1.2)
                }
            }
        case .cape:
            // billows out behind her like she's about to save the day
            let sway = sin(T * 2.5 + p.gait) * 4 + p.walk * sin(p.gait * 2) * 4
            var cape = Path()
            cape.move(to: CGPoint(x: G.neck.x - 6, y: 113))
            cape.addQuadCurve(to: CGPoint(x: 6 + sway, y: 140), control: CGPoint(x: 46, y: 100 + sway))
            cape.addQuadCurve(to: CGPoint(x: 40, y: 154), control: CGPoint(x: 10 + sway, y: 156))
            cape.addQuadCurve(to: CGPoint(x: G.neck.x + 6, y: 120), control: CGPoint(x: 80, y: 140))
            cape.closeSubpath()
            ctx.fill(cape, with: .linearGradient(Gradient(colors: [Color(red: 0.97, green: 0.50, blue: 0.66), Color(red: 0.62, green: 0.26, blue: 0.48)]),
                                                 startPoint: CGPoint(x: 90, y: 112), endPoint: CGPoint(x: 14, y: 154)))
            ctx.stroke(cape, with: .color(Color(red: 1.0, green: 0.84, blue: 0.42)), style: StrokeStyle(lineWidth: 2.2, lineJoin: .round))
            var fold = Path()
            fold.move(to: CGPoint(x: 70, y: 118)); fold.addQuadCurve(to: CGPoint(x: 30 + sway, y: 148), control: CGPoint(x: 50, y: 126))
            ctx.stroke(fold, with: .color(.white.opacity(0.22)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        default: break
        }
    }

    /// Clothes that sit over her body: a sweater or a hoodie, clipped to her shape.
    private func drawBodyFront(_ ctx: GraphicsContext) {
        guard p.outfit.body == .knitSweater || p.outfit.body == .hoodie else { return }
        var c = ctx
        // follow the same breathing as the body so the fabric never slips off her
        let flat = 1 - 0.13 * p.sleep
        let swell = 1 + breathe * (p.sleep > 0.5 ? 0.035 : 0.018)
        c.scale(x: 1 + 0.05 * p.sleep, y: swell * flat, about: CGPoint(x: G.bodyC.x, y: G.ground))
        let body = bodyPath
        var clipped = c
        clipped.clip(to: body)
        let top = G.bodyC.y - G.bodyH / 2
        if p.outfit.body == .knitSweater {
            let wool = Color(red: 1.0, green: 0.78, blue: 0.84)
            clipped.fill(Path(CGRect(x: 30, y: top - 2, width: 90, height: 60)), with: .linearGradient(
                Gradient(colors: [Color(red: 1.0, green: 0.84, blue: 0.88), wool]),
                startPoint: CGPoint(x: 70, y: top), endPoint: CGPoint(x: 80, y: top + 52)))
            for i in 0..<9 {
                let x = 42.0 + Double(i) * 8
                var st = Path()
                st.move(to: CGPoint(x: x, y: top + 4)); st.addLine(to: CGPoint(x: x + 3, y: top + 16))
                st.addLine(to: CGPoint(x: x, y: top + 28)); st.addLine(to: CGPoint(x: x + 3, y: top + 40))
                clipped.stroke(st, with: .color(Color(red: 0.92, green: 0.58, blue: 0.68).opacity(0.55)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }
            clipped.fill(Path(CGRect(x: 30, y: top + 38, width: 90, height: 14)), with: .color(Color(red: 0.96, green: 0.62, blue: 0.74)))
            for i in 0..<12 { clipped.fill(Path(CGRect(x: 36 + Double(i) * 7, y: top + 38, width: 1.6, height: 14)), with: .color(.white.opacity(0.28))) }
        } else {
            let fabric = Color(red: 0.80, green: 0.76, blue: 0.96)
            clipped.fill(Path(CGRect(x: 30, y: top - 2, width: 90, height: 60)), with: .linearGradient(
                Gradient(colors: [Color(red: 0.88, green: 0.85, blue: 1.0), fabric]),
                startPoint: CGPoint(x: 70, y: top), endPoint: CGPoint(x: 80, y: top + 52)))
            // kangaroo pocket
            let pocket = Path(roundedRect: CGRect(x: 56, y: top + 24, width: 34, height: 15), cornerRadius: 6)
            clipped.fill(pocket, with: .color(Color(red: 0.74, green: 0.70, blue: 0.92)))
            clipped.stroke(pocket, with: .color(Color(red: 0.62, green: 0.58, blue: 0.84).opacity(0.7)), lineWidth: 1.1)
            clipped.fill(Path(CGRect(x: 30, y: top + 42, width: 90, height: 10)), with: .color(Color(red: 0.70, green: 0.66, blue: 0.90)))
        }
        c.stroke(body, with: .color(Color(red: 0.84, green: 0.52, blue: 0.64).opacity(p.outfit.body == .hoodie ? 0 : 0.6)), lineWidth: 1.2)
        // the hoodie's hood and strings, bunched at her neck behind the head
        if p.outfit.body == .hoodie {
            let hood = ovalPath(G.neck.x - 4, 114, 56, 16)
            c.fill(hood, with: .color(Color(red: 0.72, green: 0.68, blue: 0.92)))
            c.stroke(hood, with: .color(Color(red: 0.60, green: 0.56, blue: 0.82).opacity(0.7)), lineWidth: 1.1)
            for dx in [-4.0, 5.0] {
                var s = Path()
                s.move(to: CGPoint(x: G.neck.x + dx, y: 118))
                s.addQuadCurve(to: CGPoint(x: G.neck.x + dx * 1.6, y: 134), control: CGPoint(x: G.neck.x + dx * 2.2, y: 126))
                c.stroke(s, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
        }
    }

    // MARK: Perch

    /// When she's been placed somewhere other than the floor she sits on a little
    /// pastel cushion that travels with her, so she never looks like she's floating.
    private func drawCushion(_ ctx: GraphicsContext, hop: Double) {
        var c = ctx
        let lift = hop * 3
        c.fill(ovalPath(94, Design.ground + 11, 104 - lift * 4, 10), with: .color(.black.opacity(0.10)))
        let r = CGRect(x: 36, y: Double(Design.ground) - 4 - lift, width: 116, height: 20)
        let pillow = Path(roundedRect: r, cornerRadius: 10)
        c.fill(pillow, with: .linearGradient(
            Gradient(colors: [Color(red: 1.0, green: 0.88, blue: 0.94), Color(red: 0.98, green: 0.72, blue: 0.86)]),
            startPoint: CGPoint(x: 0, y: r.minY), endPoint: CGPoint(x: 0, y: r.maxY)))
        c.stroke(pillow, with: .color(Color(red: 0.92, green: 0.55, blue: 0.75).opacity(0.7)), lineWidth: 1.4)
        c.fill(ovalPath(r.minX + 30, r.minY + 4, 34, 4.5), with: .color(.white.opacity(0.55)))
        for dx in [-12.0, 0.0, 12.0] {
            c.fill(ovalPath(r.midX + dx, r.midY + 2, 3, 3), with: .color(.white.opacity(0.7)))
        }
    }

    // MARK: Props

    /// What she's doing it with: a book on the floor while a focus timer runs, a boba
    /// cup on breaks. Pops in from the floor so it never just appears.
    private func drawProp(_ ctx: GraphicsContext) {
        var c = ctx
        let k = min(1, p.propAmt)
        c.opacity = k
        c.scale(x: 0.5 + 0.5 * k, y: 0.5 + 0.5 * k, about: CGPoint(x: 118, y: G.ground))
        switch p.prop {
        case .none: return
        case .book: drawBook(c)
        case .boba: drawBoba(c)
        case .matcha: drawMatcha(c)
        case .console: drawConsole(c)
        }
    }

    private func drawBook(_ c: GraphicsContext) {
        let cx = 122.0, cy = G.ground - 6
        let ribbon = Color(red: 0.80, green: 0.72, blue: 0.95)
        let cover = Path(roundedRect: CGRect(x: cx - 34, y: cy - 8, width: 68, height: 22), cornerRadius: 5)
        c.fill(cover, with: .linearGradient(
            Gradient(colors: [Color(red: 0.98, green: 0.62, blue: 0.78), Color(red: 0.90, green: 0.46, blue: 0.66)]),
            startPoint: CGPoint(x: cx, y: cy - 8), endPoint: CGPoint(x: cx, y: cy + 14)))
        for sd in [-1.0, 1.0] {
            var pg = c
            pg.translateBy(x: cx + sd * 15, y: cy + 2)
            pg.rotate(by: .degrees(sd * 5))
            let page = Path(roundedRect: CGRect(x: -15, y: -10, width: 30, height: 18), cornerRadius: 3)
            pg.fill(page, with: .color(.white))
            pg.stroke(page, with: .color(Color(red: 0.86, green: 0.78, blue: 0.95)), lineWidth: 1)
            for (i, w) in [20.0, 16.0, 19.0].enumerated() {
                var line = Path()
                line.move(to: CGPoint(x: -10, y: -6 + Double(i) * 5))
                line.addLine(to: CGPoint(x: -10 + w, y: -6 + Double(i) * 5))
                pg.stroke(line, with: .color(ribbon), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
        }
        // a page turning every few seconds
        let turn = (T / (Loop.period / 2)).truncatingRemainder(dividingBy: 1)
        if turn < 0.1 {
            var pg = c
            pg.translateBy(x: cx, y: cy + 2)
            pg.scaleBy(x: cos(turn / 0.1 * .pi), y: 1)
            let page = Path(roundedRect: CGRect(x: 0, y: -11, width: 29, height: 18), cornerRadius: 3)
            pg.fill(page, with: .color(.white))
            pg.stroke(page, with: .color(Color(red: 0.86, green: 0.78, blue: 0.95)), lineWidth: 1)
        }
        c.fill(Path(CGRect(x: cx - 1.2, y: cy - 8, width: 2.4, height: 19)), with: .color(Color(red: 0.86, green: 0.42, blue: 0.62).opacity(0.8)))
        c.fill(Path(CGRect(x: cx + 10, y: cy + 8, width: 4, height: 11)), with: .color(Color(red: 1.0, green: 0.86, blue: 0.45)))
    }

    private func drawMatcha(_ c: GraphicsContext) {
        let cx = 142.0, bottom = G.ground - 1
        // steam first, so the bowl sits over it
        for (i, dx) in [-5.0, 1.0, 7.0].enumerated() {
            var s = Path()
            let t = T * 1.5 + Double(i) * 1.3
            s.move(to: CGPoint(x: cx + dx, y: bottom - 20))
            s.addQuadCurve(to: CGPoint(x: cx + dx + sin(t) * 3, y: bottom - 36),
                           control: CGPoint(x: cx + dx + 4 * cos(t), y: bottom - 28))
            c.stroke(s, with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        var bowl = Path()
        bowl.move(to: CGPoint(x: cx - 17, y: bottom - 20))
        bowl.addLine(to: CGPoint(x: cx + 17, y: bottom - 20))
        bowl.addQuadCurve(to: CGPoint(x: cx - 17, y: bottom - 20), control: CGPoint(x: cx, y: bottom + 12))
        c.fill(bowl, with: .linearGradient(Gradient(colors: [Color(red: 1.0, green: 0.96, blue: 0.90), Color(red: 0.92, green: 0.82, blue: 0.72)]),
                                           startPoint: CGPoint(x: cx, y: bottom - 20), endPoint: CGPoint(x: cx, y: bottom + 4)))
        c.stroke(bowl, with: .color(Color(red: 0.80, green: 0.64, blue: 0.54)), lineWidth: 1.2)
        c.fill(ovalPath(cx, bottom - 20, 34, 8), with: .color(Color(red: 0.62, green: 0.80, blue: 0.48)))
        c.stroke(ovalPath(cx, bottom - 20, 34, 8), with: .color(Color(red: 0.50, green: 0.66, blue: 0.38)), lineWidth: 1)
        c.fill(ovalPath(cx - 5, bottom - 21, 12, 3), with: .color(.white.opacity(0.35)))
        c.fill(heartPath(center: CGPoint(x: cx, y: bottom - 8), size: 8), with: .color(Fur.heart.opacity(0.85)))
    }

    private func drawConsole(_ c: GraphicsContext) {
        let cx = 124.0, cy = G.ground - 7
        var g = c
        g.translateBy(x: cx, y: cy)
        g.rotate(by: .degrees(-4))
        let shell = Path(roundedRect: CGRect(x: -22, y: -10, width: 44, height: 22), cornerRadius: 7)
        g.fill(shell, with: .linearGradient(Gradient(colors: [Color(red: 1.0, green: 0.78, blue: 0.88), Color(red: 0.94, green: 0.58, blue: 0.78)]),
                                           startPoint: CGPoint(x: 0, y: -10), endPoint: CGPoint(x: 0, y: 12)))
        g.stroke(shell, with: .color(Color(red: 0.82, green: 0.44, blue: 0.64)), lineWidth: 1.2)
        let screen = Path(roundedRect: CGRect(x: -11, y: -7, width: 22, height: 15), cornerRadius: 3)
        g.fill(screen, with: .color(Color(red: 0.16, green: 0.14, blue: 0.28)))
        let glow = 0.6 + 0.4 * sin(T * 4)
        g.fill(heartPath(center: CGPoint(x: 0, y: 0), size: 8 + glow * 2), with: .color(Color(red: 0.55, green: 0.95, blue: 0.9).opacity(0.9)))
        g.fill(ovalPath(-17, 0, 6, 6), with: .color(Color(red: 0.98, green: 0.88, blue: 0.5)))
        g.fill(ovalPath(17, -2, 3.4, 3.4), with: .color(Color(red: 0.6, green: 0.9, blue: 1.0)))
        g.fill(ovalPath(17, 4, 3.4, 3.4), with: .color(Color(red: 1.0, green: 0.7, blue: 0.8)))
    }

    private func drawBoba(_ c: GraphicsContext) {
        let cx = 150.0, bottom = G.ground - 1
        let wobble = sin(T * 3) * 0.6
        var straw = Path()
        straw.move(to: CGPoint(x: cx + 2, y: bottom - 28))
        straw.addLine(to: CGPoint(x: cx - 6 + wobble, y: bottom - 52))
        c.stroke(straw, with: .color(Color(red: 0.97, green: 0.62, blue: 0.78)), style: StrokeStyle(lineWidth: 4.6, lineCap: .round))
        c.stroke(straw, with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: 4.6, dash: [3, 6]))
        var cup = Path()
        cup.move(to: CGPoint(x: cx - 13, y: bottom - 30))
        cup.addLine(to: CGPoint(x: cx + 13, y: bottom - 30))
        cup.addLine(to: CGPoint(x: cx + 9.5, y: bottom))
        cup.addQuadCurve(to: CGPoint(x: cx - 9.5, y: bottom), control: CGPoint(x: cx, y: bottom + 4))
        cup.closeSubpath()
        c.fill(cup, with: .linearGradient(
            Gradient(colors: [Color(red: 1.0, green: 0.92, blue: 0.88), Color(red: 0.96, green: 0.80, blue: 0.74)]),
            startPoint: CGPoint(x: cx, y: bottom - 30), endPoint: CGPoint(x: cx, y: bottom)))
        c.stroke(cup, with: .color(Color(red: 0.88, green: 0.62, blue: 0.62).opacity(0.8)), lineWidth: 1.3)
        for (dx, dy) in [(-5.0, -3.0), (1.0, -4.0), (6.0, -2.5), (-1.0, -8.0), (4.5, -9.0)] {
            c.fill(ovalPath(cx + dx, bottom + dy, 5.2, 5.2), with: .color(Color(red: 0.34, green: 0.22, blue: 0.24)))
            c.fill(ovalPath(cx + dx - 1, bottom + dy - 1, 1.6, 1.6), with: .color(.white.opacity(0.5)))
        }
        c.fill(ovalPath(cx, bottom - 30, 29, 7), with: .color(Color.white.opacity(0.85)))
        c.stroke(ovalPath(cx, bottom - 30, 29, 7), with: .color(Color(red: 0.88, green: 0.62, blue: 0.62).opacity(0.7)), lineWidth: 1.2)
        c.fill(heartPath(center: CGPoint(x: cx, y: bottom - 17), size: 8), with: .color(Fur.heart.opacity(0.9)))
    }

    // MARK: Tail

    private struct TailSpec {
        var n: Int, len: Double, r0: Double, r1: Double
        var base: Double, curl: Double, bushy: Double = 0
    }

    private var tailSpec: TailSpec? {
        switch species {
        case .cat: return TailSpec(n: 24, len: 3.0, r0: 6.6, r1: 3.8, base: 212, curl: 120)
        case .dog: return TailSpec(n: 18, len: 2.7, r0: 7.0, r1: 5.2, base: 222, curl: 120, bushy: 0.5)
        case .fox: return TailSpec(n: 22, len: 3.1, r0: 6.0, r1: 3.5, base: 232, curl: 38, bushy: 10)
        case .axolotl: return TailSpec(n: 20, len: 2.05, r0: 6.4, r1: 3.0, base: 214, curl: 34, bushy: 6)
        default: return nil
        }
    }

    private func drawTail(_ ctx: GraphicsContext) {
        var c = ctx
        c.translateBy(x: G.tailBase.x, y: G.tailBase.y)
        let (speed, amp) = tailSpeedAmp
        let boost = 1 + p.petting * 0.9
        // a low spirit lets the tail hang: shorter, pointing down behind her, tip curling in
        let hang = (p.sleep > 0.4 || p.emotion == .sad || p.emotion == .sleepy || p.emotion == .worried) ? 1.0 : 0.0
        let lift = 38 * p.stretch + 30 * p.sniff

        guard let s = tailSpec else { drawPom(c, speed: speed, amp: amp, boost: boost); return }

        // forward kinematics: every segment turns a little more than the last, and the
        // wag travels down the tail as a wave rather than swinging it like a rod
        let curl = hang > 0 ? -30 : s.curl
        let len = s.len * (hang > 0 ? 0.62 : 1)
        var pos = CGPoint.zero
        var heading = (hang > 0 ? 168 : s.base) + lift
        var dots: [(CGPoint, Double, Color)] = []
        for i in 0...s.n {
            let u = Double(i) / Double(s.n)
            heading += curl / Double(s.n)
            let wave = sin(T * speed * boost - u * 3.2) * amp * (0.2 + 0.9 * u) * (1 + p.petting * 0.4) * (hang > 0 ? 0.3 : 1)
            let a = (heading + wave) * .pi / 180
            pos.x += cos(a) * len
            pos.y += sin(a) * len
            var r = s.r0 + (s.r1 - s.r0) * u
            if s.bushy > 0 { r += s.bushy * sin(min(1, u * 0.82) * .pi) }
            var col = coat.blend(2, 0, u * 0.85)
            if species == .fox {
                col = u > 0.74 ? coat.belly : coat.blend(2, 1, 0.5 + u * 0.3)
            } else if species == .cat && u > 0.8 {
                col = coat.shade                     // a darker tip, like a dipped brush
            } else if species == .axolotl {
                col = coat.blend(1, 4, 0.15 + u * 0.55)   // fading to a bright fin
            }
            dots.append((pos, r, col))
        }
        // outline pass first so the whole tail gets one clean edge
        for d in dots { c.fill(ovalPath(d.0.x, d.0.y, d.1 * 2 + 2.6, d.1 * 2 + 2.6), with: .color(rim)) }
        for d in dots { c.fill(ovalPath(d.0.x, d.0.y, d.1 * 2, d.1 * 2), with: .color(d.2)) }
    }

    /// Bunny, panda and hamster: a round pom that jiggles instead of a long tail.
    private func drawPom(_ c: GraphicsContext, speed: Double, amp: Double, boost: Double) {
        let r: Double = species == .bunny ? 11 : (species == .panda ? 9 : (species == .capybara ? 5 : 6.5))
        let j = sin(T * speed * boost) * amp * 0.12
        var g = c
        g.translateBy(x: -1, y: -3)
        g.rotate(by: .degrees(j * 3))
        let pom = ovalPath(0, j * 0.3, r * 2, r * 2)
        g.fill(pom, with: .radialGradient(Gradient(colors: [coat.light, species == .panda ? coat.light : coat.mid]),
                                         center: CGPoint(x: -r * 0.3, y: -r * 0.3), startRadius: 1, endRadius: r * 1.4))
        g.stroke(pom, with: .color(rim), lineWidth: 1.3)
    }

    // MARK: Legs

    private func drawLegs(_ ctx: GraphicsContext, front: Bool, pitch: Double, drop: Double) {
        let ids = front ? [2, 3] : [0, 1]
        for i in ids {
            let far = (i == 0 || i == 2)
            let x = G.legsX[i]
            let sw = p.gait + (i % 2 == 0 ? 0 : .pi) + (front ? 0 : .pi)
            var angle = sin(sw) * 30 * p.walk * (1 + 0.3 * p.run)
            // the paw leaves the floor while it swings forward
            var lift = max(0, -cos(sw)) * 6 * p.walk
            var length = G.ground - G.hipY - 3

            if front {
                // a pitched torso moves the shoulder, so reach for the floor from
                // wherever it ended up instead of hard-coding each pose
                let th = pitch * .pi / 180
                let rx = x - G.rear.x, ry = G.hipY - G.rear.y
                let hipY = G.rear.y + rx * sin(th) + ry * cos(th) + drop
                length = max(10, G.ground - 3 - hipY)
                angle -= pitch * (1 - p.stretch)
                if p.stretch > 0 { angle += 44 * p.stretch }     // forearms stretch out ahead
            }
            if p.dance > 0.01 {
                // paws take turns: diagonal pairs, like a little two-step
                let beat = sin(T * 6 + (i % 2 == 0 ? 0 : .pi))
                angle += beat * 30 * p.dance
                lift += max(0, beat) * 7 * p.dance
            }
            if p.dangling { angle = sin(T * 3 + Double(i)) * 12 + (i < 2 ? 8 : -8); lift = 0 }
            if p.tapping && front {
                let r = tapRaise(p.tapPhase)
                angle = i == 3 ? -95 * r : 10 * r
                length = G.ground - G.hipY - 3
            }
            if p.scratch > 0 && i == 1 {
                angle = (-92 + sin(T * 22) * 9) * p.scratch + angle * (1 - p.scratch)
                lift = 0
            }
            let tuck = 1 - 0.62 * p.sleep
            var opacity = 1.0
            if !front { opacity = 1 - p.sit }
            if p.scratch > 0 && i == 1 { opacity = 1 }
            if front && i == 3 { opacity = 1 - p.wave }      // that paw is up, waving: see `drawWavingPaw`
            guard opacity > 0.01 else { continue }

            var c = ctx
            c.opacity = opacity
            c.translateBy(x: x, y: G.hipY - 4 - lift)
            c.rotate(by: .degrees(angle))
            drawLeg(c, length: length * tuck + 4, far: far, beans: !far)
        }
    }

    /// One leg hanging from the origin: a capsule with a paw cap. `length` runs hip to floor.
    private func drawLeg(_ c: GraphicsContext, length: Double, far: Bool, beans: Bool) {
        let w = species == .hamster ? 16.0 : 18.0
        let limb = capsulePath(0, length / 2, w, length)
        let limbColor: Color
        switch species {
        case .panda: limbColor = coat.patch
        case .fox: limbColor = far ? coat.shade : coat.patch
        default: limbColor = far ? coat.shade.opacity(0.92) : coat.mid
        }
        c.fill(limb, with: .color(limbColor))
        c.stroke(limb, with: .color(rim), lineWidth: 1.2)

        let pawColor: Color
        switch species {
        case .panda: pawColor = far ? coat.patch : coat.patch.opacity(0.92)
        case .fox: pawColor = far ? coat.patch : coat.patch
        default: pawColor = far ? coat.mid : coat.light
        }
        let paw = ovalPath(1, length - 3, far ? 21 : 24, 15)
        c.fill(paw, with: .color(pawColor))
        c.stroke(paw, with: .color(rim), lineWidth: 1.1)
        if beans {
            let by = length - 5
            let pad = Fur.blushAccent.opacity(species == .panda ? 0.75 : 0.62)
            c.fill(ovalPath(1, by + 2.5, 8, 6.4), with: .color(pad))
            for dx in [-6.4, 0.0, 6.4] { c.fill(ovalPath(1 + dx, by - 3.4, 4.2, 3.9), with: .color(pad)) }
        }
    }

    /// The folded hind foot a sitting pet rests on, drawn flat on the floor.
    private func drawHindFoot(_ ctx: GraphicsContext) {
        var c = ctx
        c.opacity = p.sit
        let foot = ovalPath(G.rear.x + 34, G.ground - 6, 32, 13)
        c.fill(foot, with: .color(species == .panda || species == .fox ? coat.patch : coat.light))
        c.stroke(foot, with: .color(rim), lineWidth: 1.1)
    }

    // MARK: Body

    private func drawBody(_ ctx: GraphicsContext) {
        var c = ctx
        // breathing: the chest swells, anchored low so the paws never leave the floor
        let flat = 1 - 0.13 * p.sleep
        let swell = 1 + breathe * (p.sleep > 0.5 ? 0.035 : 0.018)
        c.scale(x: 1 + 0.05 * p.sleep, y: swell * flat, about: CGPoint(x: G.bodyC.x, y: G.ground))

        let body = bodyPath
        c.fill(body, with: .radialGradient(
            Gradient(colors: [coat.light, coat.mid]),
            center: CGPoint(x: G.bodyC.x - 8, y: G.bodyC.y - G.bodyH * 0.45),
            startRadius: 2, endRadius: G.bodyW * 1.05))

        var clipped = c
        clipped.clip(to: body)
        clipped.fill(ovalPath(G.bodyC.x + 6, G.bodyC.y + G.bodyH * 0.34, G.bodyW * 0.72, G.bodyH * 0.36),
                     with: .color(coat.shade.opacity(0.2)))
        // soft pale tummy
        clipped.fill(ovalPath(G.bodyC.x + 12, G.bodyC.y + 12, G.bodyW * 0.55, G.bodyH * 0.55),
                     with: .color(coat.belly.opacity(species == .dog || species == .cat ? 0.55 : 0.8)))
        if species == .panda {
            clipped.fill(ovalPath(G.bodyC.x + 20, G.bodyC.y, 22, 70), with: .color(coat.patch))
        }
        if coat.stripes {
            for (dx, len) in [(-16.0, 12.0), (-4.0, 15.0), (8.0, 13.0)] {
                let x = G.bodyC.x + dx
                var s = Path()
                s.move(to: CGPoint(x: x, y: G.bodyC.y - G.bodyH / 2 - 1))
                s.addQuadCurve(to: CGPoint(x: x + 2, y: G.bodyC.y - G.bodyH / 2 + len),
                               control: CGPoint(x: x - 3, y: G.bodyC.y - G.bodyH / 2 + len * 0.5))
                clipped.stroke(s, with: .color(coat.patch.opacity(0.55)),
                               style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
            }
        }
        clipped.fill(ovalPath(G.bodyC.x - 8, G.bodyC.y - G.bodyH * 0.3, 26, 9), with: .color(.white.opacity(0.35)))
        c.stroke(body, with: .color(rim), lineWidth: 1.4)

        // the thigh, only once she's sitting: gives the folded hind leg some volume
        if p.sit > 0.02 {
            var h = c
            h.opacity = min(1, p.sit * 1.5)
            let thigh = ovalPath(G.rear.x + 8, 136, 38 * p.sit + 8, 32 * p.sit + 6)
            h.fill(thigh, with: .radialGradient(Gradient(colors: [coat.light, coat.mid]),
                                               center: CGPoint(x: G.rear.x + 4, y: 126), startRadius: 1, endRadius: 28))
            h.stroke(thigh, with: .color(rim), lineWidth: 1.2)
        }
    }

    // MARK: Head

    private var headTilt: Double {
        var t: Double
        switch p.emotion {
        case .love: t = sin(T * 2) * 6 - 4
        case .alert: t = -7
        case .sad, .worried: t = 6
        case .sleepy: t = 9 + sin(T * 1) * 3
        case .playful: t = sin(T * 5) * 7
        case .angry: t = sin(T * 12) * 2.5
        case .curious: t = 16 + sin(T * 1.5) * 3
        case .shy: t = 10
        case .bored: t = -3
        case .blissful: t = sin(T * 1) * 3
        case .vibing: t = sin(T * 3) * 8 + p.bop * 4
        case .cozy: t = 7 + sin(T * 1) * 2
        case .moody: t = -5
        default: t = sin(T * 1.5) * 2
        }
        t += p.look.dx * 3.5
        t += 16 * p.stretch + 20 * p.sniff + sin(T * 5) * 3 * p.sniff
        t += 14 * p.sleep
        t += (p.groom > 0 ? 14 + sin(((T / (Loop.period / 28)).truncatingRemainder(dividingBy: 1)) * .pi) * 10 : 0) * p.groom
        t -= 10 * p.scratch
        t += sin(T * 6) * 9 * p.dance + 5 * p.wave
        if p.prop == .book || p.prop == .console { t += 11 * p.propAmt }
        if p.prop == .boba || p.prop == .matcha { t += 6 * sip }
        if p.tapping { t -= 16 * tapRaise(p.tapPhase) }
        return t
    }

    /// 0...1: leaning in to sip her boba, a few seconds out of every eight.
    private var sip: Double { (p.prop == .boba || p.prop == .matcha) ? p.propAmt * pow(max(0, sin(T * 1)), 0.6) : 0 }

    private func drawHead(_ ctx: GraphicsContext) {
        var c = ctx

        var dx = p.look.dx * 2.5, dy = p.look.dy * 1.5
        dy += sin(p.gait - 0.7) * 1.8 * p.walk            // head lags the body
        dy -= p.petting * 3                                // leans up into the hand
        dx += sin(T * 0.5) * 0.9                           // slow weight shift
        dy += 5 * p.bop                                    // head bops down on the beat
        dx += 7 * p.sit
        dx -= 2 * p.sleep; dy += 30 * p.sleep
        dx -= 2 * p.stretch; dy += 8 * p.stretch
        dx += 0 * p.sniff; dy += 9 * p.sniff
        dx += 6 * p.run; dy += 2 * p.run
        if p.tapping { dx += 6 * tapRaise(p.tapPhase) }
        if p.prop == .book || p.prop == .console { dy += 7 * p.propAmt; dx -= 1 * p.propAmt }
        if p.prop == .boba || p.prop == .matcha { dx += 8 * sip; dy += 4 * sip }
        if p.emotion == .eating {
            let dip = 0.5 + 0.5 * sin(T * 7)
            dx += 2 + 3 * dip; dy += 20 + 10 * dip
        }
        if p.emotion == .angry { dx += 4 * abs(sin(T * 12)) }   // each bark lunges the head
        c.translateBy(x: dx, y: dy)
        var tilt = headTilt
        if p.emotion == .eating { tilt += 12 }
        c.rotate(degrees: tilt, about: G.neck)

        drawEars(c)
        drawCheekFluff(c)

        // head
        let head = headPath
        c.fill(head, with: .radialGradient(
            Gradient(colors: [headTones.0, headTones.1]),
            center: CGPoint(x: G.headC.x - 8, y: G.headC.y - headH * 0.5),
            startRadius: 2, endRadius: headW * 0.78))
        var clipped = c
        clipped.clip(to: head)
        drawMarks(clipped)
        // a soft glossy crescent up top and a pale rim-light along the bottom: plush, not flat
        var gloss = clipped
        gloss.translateBy(x: G.headC.x - headW * 0.2, y: G.headC.y - headH * 0.34)
        gloss.rotate(by: .degrees(-22))
        gloss.fill(ovalPath(0, 0, headW * 0.4, headH * 0.17), with: .color(.white.opacity(0.42)))
        clipped.fill(ovalPath(G.headC.x, G.headC.y + headH * 0.5, headW * 0.8, headH * 0.22), with: .color(.white.opacity(0.16)))
        c.stroke(head, with: .color(rim), lineWidth: 1.5)

        drawFoxRuff(c)
        drawMuzzle(c)
        drawBlush(c)
        drawWhiskers(c)
        drawMouthAndNose(c)
        drawEyes(c)
        drawGroomingPaw(c)
        drawHeadAccessory(c)
    }

    /// A raised paw, waving hello: drawn over the chest, after the head, so it reads as in
    /// front of her. It swings from the shoulder.
    private func drawWavingPaw(_ ctx: GraphicsContext) {
        guard p.wave > 0.02 else { return }
        var c = ctx
        c.opacity = min(1, p.wave * 2)
        c.translateBy(x: G.legsX[3] + 5, y: G.hipY - 6)
        c.rotate(by: .degrees((-108 + sin(T * 11) * 16) * p.wave))
        let limbColor: Color
        switch species {
        case .panda: limbColor = coat.patch
        case .fox: limbColor = coat.patch
        default: limbColor = coat.mid
        }
        let limb = capsulePath(0, 13, 17, 28)
        c.fill(limb, with: .color(limbColor))
        c.stroke(limb, with: .color(rim), lineWidth: 1.2)
        let paw = ovalPath(1, 26, 23, 15)
        c.fill(paw, with: .color(species == .panda || species == .fox ? coat.patch : coat.light))
        c.stroke(paw, with: .color(rim), lineWidth: 1.1)
        let pad = Fur.blushAccent.opacity(0.65)
        c.fill(ovalPath(1, 28, 7, 5.6), with: .color(pad))
        for dx in [-5.5, 0.0, 5.5] { c.fill(ovalPath(1 + dx, 22.5, 3.6, 3.4), with: .color(pad)) }
    }

    /// Two fluffy points on each cheek: the kitten's whole silhouette. Drawn before the head, so the
    /// head covers where they join.
    private func drawCheekFluff(_ c: GraphicsContext) {
        guard species == .cat else { return }
        for sd in [-1.0, 1.0] {
            let cx = G.headC.x + sd * headW * 0.5
            let y0 = G.headC.y + headH * 0.1
            for (dy, out, len) in [(0.0, 3.0, 9.0), (10.0, 1.5, 8.0)] {
                var t = Path()
                t.move(to: CGPoint(x: cx - sd * 8, y: y0 + dy - 5))
                t.addQuadCurve(to: CGPoint(x: cx + sd * (out + 5), y: y0 + dy + len), control: CGPoint(x: cx + sd * (out + 6), y: y0 + dy + 1))
                t.addLine(to: CGPoint(x: cx - sd * 8, y: y0 + dy + 9))
                t.closeSubpath()
                c.fill(t, with: .color(coat.mid))
                c.stroke(t, with: .color(rim), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
            }
        }
    }

    // MARK: Ears

    private func drawEars(_ ctx: GraphicsContext) {
        // anchors as fractions of the head, so ears follow any head size
        let f: (x: Double, y: Double)
        switch species {
        case .dog: f = (0.80, -0.50)
        case .bunny: f = (0.34, -0.78)
        case .panda: f = (0.70, -0.72)
        case .hamster: f = (0.66, -0.70)
        case .axolotl: f = (0.78, -0.08)
        case .capybara: f = (0.64, -0.78)
        case .fox: f = (0.58, -0.78)
        case .cat: f = (0.60, -0.76)
        }
        let hw = headW / 2, hh = headH / 2
        let anchors = [(CGPoint(x: G.headC.x - f.x * hw, y: G.headC.y + f.y * hh + 2), true),
                       (CGPoint(x: G.headC.x + f.x * hw, y: G.headC.y + f.y * hh), false)]
        for (anchor, mirrored) in anchors {
            var c = ctx
            c.translateBy(x: anchor.x, y: anchor.y)
            if mirrored { c.scaleBy(x: -1, y: 1) }
            // follow-through: the ear lags the head bob, and flaps on a run
            var angle = earPerk + (mirrored ? 0 : earTwitch)
            angle += sin(p.gait * 2 - 1.1) * 6 * p.walk + sin(T * 12) * 5 * p.dance
            angle += sin(T * 9 + (mirrored ? 0.7 : 0)) * 4 * (p.emotion == .excited ? 1 : 0)
            if p.emotion == .curious && !mirrored { angle -= 14 }
            if p.dangling { angle -= 34 }
            if p.sleep > 0.5 { angle = 16 }

            switch species {
            case .cat: earKitten(c, angle: angle)
            case .fox: earPointed(c, angle: angle, scale: 1.3, tip: coat.patch)
            case .dog: earFloppy(c, angle: angle)
            case .bunny: earLong(c, angle: angle, mirrored: mirrored)
            case .panda: earRound(c, angle: angle, r: 15, color: coat.patch, inner: nil)
            case .hamster: earRound(c, angle: angle, r: 14, color: coat.patch, inner: Fur.blushAccent.opacity(0.75))
            case .capybara: earRound(c, angle: angle, r: 10, color: coat.shade, inner: coat.patch.opacity(0.75))
            case .axolotl: gills(c)
            }
        }
    }

    private func earPointed(_ ctx: GraphicsContext, angle: Double, scale: Double, tip: Color?) {
        var c = ctx
        c.rotate(by: .degrees(angle))
        c.scaleBy(x: scale, y: scale * (species == .fox ? 1.1 : 1))
        var ear = Path()
        ear.move(to: CGPoint(x: -15, y: 7))
        ear.addQuadCurve(to: CGPoint(x: 1, y: -30), control: CGPoint(x: -12, y: -15))
        ear.addQuadCurve(to: CGPoint(x: 18, y: 9), control: CGPoint(x: 14, y: -14))
        ear.addQuadCurve(to: CGPoint(x: -15, y: 7), control: CGPoint(x: 1, y: 16))
        ear.closeSubpath()
        c.fill(ear, with: .linearGradient(Gradient(colors: [coat.mid, coat.shade]),
                                         startPoint: .zero, endPoint: CGPoint(x: 16, y: 34)))
        if let tip {
            var t = c
            t.clip(to: ear)
            t.fill(Path(CGRect(x: -30, y: -40, width: 60, height: 22)), with: .color(tip))
        }
        c.stroke(ear, with: .color(rim), lineWidth: 1.2 / scale)
        var inner = Path()
        inner.move(to: CGPoint(x: -7, y: 3))
        inner.addQuadCurve(to: CGPoint(x: 1, y: -19), control: CGPoint(x: -5, y: -10))
        inner.addQuadCurve(to: CGPoint(x: 9, y: 5), control: CGPoint(x: 6, y: -7))
        inner.addQuadCurve(to: CGPoint(x: -7, y: 3), control: CGPoint(x: 1, y: 9))
        inner.closeSubpath()
        c.fill(inner, with: .color(tip != nil ? coat.belly.opacity(0.9) : Fur.blushAccent.opacity(0.55)))
    }

    /// A kitten's ear: wide at the base, a rounded tip, and a pink inside with a little fluff.
    private func earKitten(_ ctx: GraphicsContext, angle: Double) {
        var c = ctx
        c.rotate(by: .degrees(angle))
        c.scaleBy(x: 1.12, y: 1.18)
        var ear = Path()
        ear.move(to: CGPoint(x: -17, y: 9))
        ear.addCurve(to: CGPoint(x: -5, y: -25), control1: CGPoint(x: -19, y: -6), control2: CGPoint(x: -13, y: -20))
        ear.addQuadCurve(to: CGPoint(x: 9, y: -24), control: CGPoint(x: 2, y: -33))
        ear.addCurve(to: CGPoint(x: 19, y: 9), control1: CGPoint(x: 17, y: -17), control2: CGPoint(x: 21, y: -3))
        ear.addQuadCurve(to: CGPoint(x: -17, y: 9), control: CGPoint(x: 1, y: 17))
        ear.closeSubpath()
        c.fill(ear, with: .linearGradient(Gradient(colors: [coat.mid, coat.shade]),
                                         startPoint: CGPoint(x: 0, y: -30), endPoint: CGPoint(x: 6, y: 20)))
        c.stroke(ear, with: .color(rim), style: StrokeStyle(lineWidth: 1.2 / 1.15, lineJoin: .round))
        var inner = Path()
        inner.move(to: CGPoint(x: -9, y: 5))
        inner.addCurve(to: CGPoint(x: -2, y: -17), control1: CGPoint(x: -11, y: -5), control2: CGPoint(x: -7, y: -13))
        inner.addQuadCurve(to: CGPoint(x: 6, y: -16), control: CGPoint(x: 2, y: -22))
        inner.addCurve(to: CGPoint(x: 11, y: 5), control1: CGPoint(x: 10, y: -10), control2: CGPoint(x: 12, y: -2))
        inner.addQuadCurve(to: CGPoint(x: -9, y: 5), control: CGPoint(x: 1, y: 10))
        inner.closeSubpath()
        c.fill(inner, with: .linearGradient(Gradient(colors: [Fur.blushAccent.opacity(0.9), Fur.blushAccent.opacity(0.45)]),
                                           startPoint: CGPoint(x: 0, y: -18), endPoint: CGPoint(x: 0, y: 8)))
        // two wisps of inner-ear fluff
        for dx in [-2.5, 2.5] {
            var w = Path()
            w.move(to: CGPoint(x: dx, y: 6))
            w.addQuadCurve(to: CGPoint(x: dx * 1.6, y: -6), control: CGPoint(x: dx * 2.4, y: 0))
            c.stroke(w, with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }
    }

    /// A puppy's ear: a soft triangle that folds over and hangs, with a crease where it bends.
    private func earFloppy(_ ctx: GraphicsContext, angle: Double) {
        var c = ctx
        c.rotate(by: .degrees(angle * 1.4 + 6))
        var ear = Path()
        ear.move(to: CGPoint(x: -9, y: -8))
        ear.addCurve(to: CGPoint(x: 21, y: 4), control1: CGPoint(x: 3, y: -17), control2: CGPoint(x: 17, y: -9))
        ear.addCurve(to: CGPoint(x: 17, y: 42), control1: CGPoint(x: 26, y: 16), control2: CGPoint(x: 26, y: 34))
        ear.addQuadCurve(to: CGPoint(x: 4, y: 38), control: CGPoint(x: 10, y: 50))
        ear.addCurve(to: CGPoint(x: -9, y: -8), control1: CGPoint(x: -3, y: 24), control2: CGPoint(x: -10, y: 8))
        ear.closeSubpath()
        c.fill(ear, with: .linearGradient(Gradient(colors: [coat.patch, coat.patch.opacity(0.82)]),
                                         startPoint: CGPoint(x: 0, y: -10), endPoint: CGPoint(x: 14, y: 46)))
        c.stroke(ear, with: .color(rim), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
        // the fold, and a soft light on the rounded part
        var crease = Path()
        crease.move(to: CGPoint(x: -4, y: -8))
        crease.addQuadCurve(to: CGPoint(x: 19, y: 6), control: CGPoint(x: 9, y: 2))
        c.stroke(crease, with: .color(.black.opacity(0.12)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        c.fill(ovalPath(13, 26, 8, 20), with: .color(.white.opacity(0.18)))
    }

    private func earLong(_ ctx: GraphicsContext, angle: Double, mirrored: Bool) {
        var c = ctx
        // droops outward when sad or sleepy, stands tall when alert
        let droop = (p.emotion == .sad || p.emotion == .sleepy || p.emotion == .bored || p.sleep > 0.5) ? 38.0 : 0
        c.rotate(by: .degrees(angle * 1.3 + 7 + droop))
        let ear = ovalPath(0, -26, 23, 62)
        c.fill(ear, with: .linearGradient(Gradient(colors: [coat.mid, coat.light]),
                                         startPoint: CGPoint(x: 0, y: 4), endPoint: CGPoint(x: 0, y: -58)))
        c.stroke(ear, with: .color(rim), lineWidth: 1.2)
        c.fill(ovalPath(0, -25, 11, 46), with: .color(Fur.blushAccent.opacity(0.6)))
    }

    /// The axolotl's three fluffy gill fronds a side, swaying like they're underwater: the
    /// feature everyone knows her by, so they're big, bright and a little bit frilly.
    private func gills(_ ctx: GraphicsContext) {
        for (i, base) in [-86.0, -56.0, -24.0].enumerated() {
            let c = ctx
            let sway = sin(T * 2.5 + Double(i) * 0.9) * 8 + p.walk * sin(p.gait * 2 + Double(i)) * 5
            let ang = (base + sway - (p.sleep > 0.5 ? -14 : 0)) * .pi / 180
            let len = 27.0 - Double(i) * 2.5
            let tip = CGPoint(x: cos(ang) * len, y: sin(ang) * len)
            let mid = CGPoint(x: tip.x * 0.5, y: tip.y * 0.5 - 3)
            var stalk = Path()
            stalk.move(to: CGPoint(x: -6, y: Double(i) * 6 - 4))
            stalk.addQuadCurve(to: tip, control: CGPoint(x: mid.x, y: mid.y))
            c.stroke(stalk, with: .color(coat.patch.opacity(0.5)), style: StrokeStyle(lineWidth: 8.4, lineCap: .round))
            c.stroke(stalk, with: .color(coat.patch), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            // fluffy filaments fanning off the end of the stalk
            for (k, spread) in [-34.0, 0.0, 34.0].enumerated() {
                let a = ang + spread * .pi / 180 + sin(T * 3 + Double(k + i)) * 0.12
                let end = CGPoint(x: tip.x + cos(a) * 8, y: tip.y + sin(a) * 8)
                var fil = Path()
                fil.move(to: tip)
                fil.addLine(to: end)
                c.stroke(fil, with: .color(coat.patch.opacity(0.55)), style: StrokeStyle(lineWidth: 6.4, lineCap: .round))
                c.stroke(fil, with: .color(coat.patch), style: StrokeStyle(lineWidth: 4.4, lineCap: .round))
                c.fill(ovalPath(end.x - 0.8, end.y - 0.9, 2.4, 2.2), with: .color(.white.opacity(0.55)))
            }
            c.fill(ovalPath(tip.x, tip.y, 11, 11), with: .color(coat.patch))
            c.fill(ovalPath(tip.x - 2, tip.y - 2.2, 3.6, 3.2), with: .color(.white.opacity(0.55)))
        }
    }

    private func earRound(_ ctx: GraphicsContext, angle: Double, r: Double, color: Color, inner: Color?) {
        var c = ctx
        c.rotate(by: .degrees(angle * 0.5))
        let ear = ovalPath(0, -r * 0.35, r * 2, r * 2)
        c.fill(ear, with: .color(color))
        c.stroke(ear, with: .color(rim), lineWidth: 1.2)
        if let inner { c.fill(ovalPath(0, -r * 0.3, r * 1.1, r * 1.1), with: .color(inner)) }
    }

    // MARK: Face

    /// Markings painted on the head and clipped to its outline.
    private func drawMarks(_ c: GraphicsContext) {
        switch species {
        case .panda:
            for (e, rot) in [(G.eyeL, 22.0), (G.eyeR, -22.0)] {
                var g = c
                g.translateBy(x: e.x, y: e.y + 2)
                g.rotate(by: .degrees(rot))
                g.fill(ovalPath(0, 0, 26, 33), with: .color(coat.patch))
            }
        case .dog:
            // a pale blaze down the forehead, and a patch that wraps one ear: how a real pup is marked
            c.fill(ovalPath(G.headC.x + 4, G.headC.y - 14, 19, 58), with: .linearGradient(
                Gradient(colors: [coat.belly.opacity(0.35), coat.belly.opacity(0.95)]),
                startPoint: CGPoint(x: 0, y: G.headC.y - 42), endPoint: CGPoint(x: 0, y: G.headC.y + 8)))
            c.fill(ovalPath(G.eyeR.x + 16, G.headC.y - 24, 54, 48), with: .color(coat.patch.opacity(0.92)))
        case .hamster:
            // a coloured cap over a pale face, with a dark stripe down the middle
            let hw = headW / 2, cx = G.headC.x, cy = G.headC.y
            var cap = Path()
            cap.move(to: CGPoint(x: cx - hw - 8, y: cy - headH))
            cap.addLine(to: CGPoint(x: cx + hw + 8, y: cy - headH))
            cap.addLine(to: CGPoint(x: cx + hw + 8, y: cy + 6))
            cap.addQuadCurve(to: CGPoint(x: cx, y: cy - 20), control: CGPoint(x: cx + hw * 0.5, y: cy - 22))
            cap.addQuadCurve(to: CGPoint(x: cx - hw - 8, y: cy + 6), control: CGPoint(x: cx - hw * 0.5, y: cy - 22))
            cap.closeSubpath()
            c.fill(cap, with: .linearGradient(Gradient(colors: [coat.patch, coat.patch.opacity(0.78)]),
                                              startPoint: CGPoint(x: 0, y: cy - 50), endPoint: CGPoint(x: 0, y: cy)))
            c.fill(capsulePath(cx, cy - 34, 10, 38), with: .color(coat.shade.opacity(0.4)))
        case .axolotl:
            // freckles across the cheeks
            for (dx, dy, r) in [(-44.0, 16.0, 1.5), (-37.0, 24.0, 1.2), (-48.0, 26.0, 1.3), (-30.0, 31.0, 1.1),
                                (44.0, 16.0, 1.5), (37.0, 24.0, 1.2), (48.0, 26.0, 1.3), (30.0, 31.0, 1.1)] {
                c.fill(ovalPath(G.headC.x + dx, G.headC.y + dy, r * 2, r * 2), with: .color(coat.shade.opacity(0.7)))
            }
            c.fill(ovalPath(G.headC.x, G.headC.y - headH * 0.5, headW * 0.9, 34), with: .color(coat.shade.opacity(0.16)))
        case .capybara:
            // a darker crown, and coarse little flecks of hair
            c.fill(ovalPath(G.headC.x, G.headC.y - headH * 0.46, headW * 0.9, 44), with: .color(coat.shade.opacity(0.22)))
            for (dx, dy) in [(-34.0, -30.0), (-20.0, -37.0), (-6.0, -33.0), (10.0, -38.0), (26.0, -32.0), (40.0, -25.0), (-46.0, -16.0), (49.0, -10.0)] {
                var h = Path()
                h.move(to: CGPoint(x: G.headC.x + dx, y: G.headC.y + dy))
                h.addLine(to: CGPoint(x: G.headC.x + dx + 2.5, y: G.headC.y + dy + 6))
                c.stroke(h, with: .color(coat.shade.opacity(0.5)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
        case .fox:
            // a pale lower face under the coloured mask: the fox's whole look
            c.fill(ovalPath(G.muzzleC.x, G.headC.y + headH * 0.44, headW * 0.98, headH * 0.6), with: .color(coat.belly))
        case .cat:
            // the tabby "M": strong on a ginger, a whisper on the pale coats
            for (dx, len) in [(-9.0, 14.0), (0.0, 19.0), (9.0, 14.0)] {
                var s = Path()
                s.move(to: CGPoint(x: G.headC.x + 2 + dx, y: G.headC.y - headH / 2))
                s.addLine(to: CGPoint(x: G.headC.x + 2 + dx * 0.8, y: G.headC.y - headH / 2 + len))
                c.stroke(s, with: .color((coat.stripes ? coat.patch : coat.shade).opacity(coat.stripes ? 0.55 : 0.34)),
                         style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
            }
        case .bunny:
            break
        }
    }

    private func drawFoxRuff(_ c: GraphicsContext) {
        guard species == .fox else { return }
        let k = headH / 90
        for sd in [-1.0, 1.0] {
            let cx = G.headC.x + sd * headW * 0.47
            let y0 = G.headC.y
            var t = Path()
            t.move(to: CGPoint(x: cx - sd * 7, y: y0 + 11 * k))
            t.addLine(to: CGPoint(x: cx + sd * 11, y: y0 + 27 * k))
            t.addLine(to: CGPoint(x: cx + sd * 1, y: y0 + 29 * k))
            t.addLine(to: CGPoint(x: cx + sd * 9, y: y0 + 41 * k))
            t.addLine(to: CGPoint(x: cx - sd * 12, y: y0 + 37 * k))
            t.closeSubpath()
            c.fill(t, with: .color(coat.belly))
            c.stroke(t, with: .color(rim), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
        }
    }

    /// A soft raised muzzle: a highlight, not a coloured patch.
    private func drawMuzzle(_ c: GraphicsContext) {
        let (w, h): (Double, Double)
        switch species {
        case .dog: (w, h) = (52, 35)
        case .fox: (w, h) = (36, 26)
        case .bunny: (w, h) = (40, 30)
        default: (w, h) = (38, 27)
        }
        if species == .cat {
            // two puffy whisker pads
            for sd in [-1.0, 1.0] { c.fill(ovalPath(G.muzzleC.x + sd * 9, G.muzzleC.y + 1, 22, 17), with: .color(coat.belly.opacity(0.9))) }
            return
        }
        if species == .capybara {
            // the capybara's whole personality is a big, calm, boxy snout
            let r = CGRect(x: G.muzzleC.x - 31, y: G.muzzleC.y - 15, width: 62, height: 28)
            let snout = Path(roundedRect: r, cornerRadius: 13)
            c.fill(snout, with: .linearGradient(Gradient(colors: [coat.belly, coat.belly.opacity(0.7)]),
                                               startPoint: CGPoint(x: 0, y: r.minY), endPoint: CGPoint(x: 0, y: r.maxY)))
            c.stroke(snout, with: .color(coat.shade.opacity(0.35)), lineWidth: 1)
            return
        }
        let alpha = (species == .panda || species == .fox) ? 0.0 : (species == .dog ? 0.9 : 0.55)
        if alpha > 0 { c.fill(ovalPath(G.muzzleC.x, G.muzzleC.y, w, h), with: .color(coat.belly.opacity(alpha))) }
    }

    private func drawBlush(_ c: GraphicsContext) {
        let shy = p.emotion == .love || p.emotion == .shy || p.emotion == .blissful || p.emotion == .proud || p.emotion == .cozy
        let col = Fur.blushAccent.opacity(shy ? 0.75 : 0.5)
        let wide: Double = species == .hamster ? 28 : (species == .axolotl ? 26 : 22)
        let spots = [CGPoint(x: G.eyeL.x - 12, y: G.eyeL.y + 19), CGPoint(x: G.eyeR.x + 14, y: G.eyeR.y + 21)]
        for sp in spots {
            c.fill(ovalPath(sp.x, sp.y, wide, 13), with: .color(col))
            // three little slanted ticks: the manga blush
            if shy || p.emotion == .happy {
                for i in -1...1 {
                    var t = Path()
                    t.move(to: CGPoint(x: sp.x + Double(i) * 5 - 2, y: sp.y + 3))
                    t.addLine(to: CGPoint(x: sp.x + Double(i) * 5 + 1, y: sp.y - 3))
                    c.stroke(t, with: .color(Fur.heart.opacity(0.55)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                }
            }
        }
    }

    private func drawWhiskers(_ c: GraphicsContext) {
        guard species == .cat || species == .fox || species == .hamster else { return }
        let len: Double = species == .cat ? 17 : 13
        let twitch = sin(T * 1.5) * 1.3
        let m = G.muzzleC
        for side in [-1.0, 1.0] {
            for dy in [-2.0, 5.0] {
                var w = Path()
                w.move(to: CGPoint(x: m.x + side * 14, y: m.y + dy))
                w.addQuadCurve(to: CGPoint(x: m.x + side * (14 + len), y: m.y + dy - 3 + twitch * side),
                               control: CGPoint(x: m.x + side * (14 + len * 0.5), y: m.y + dy - 1))
                c.stroke(w, with: .color(Fur.ink.opacity(0.3)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            }
        }
    }

    // MARK: Nose and mouth

    private func nosePath() -> Path {
        let nx = G.noseC.x, ny = G.noseC.y
        var n = Path()
        switch species {
        case .dog, .panda:
            let w: Double = species == .dog ? 7.5 : 8
            n.move(to: CGPoint(x: nx - w, y: ny - 4))
            n.addQuadCurve(to: CGPoint(x: nx + w, y: ny - 4), control: CGPoint(x: nx, y: ny - 8))
            n.addQuadCurve(to: CGPoint(x: nx, y: ny + 5), control: CGPoint(x: nx + w, y: ny + 3))
            n.addQuadCurve(to: CGPoint(x: nx - w, y: ny - 4), control: CGPoint(x: nx - w, y: ny + 3))
        case .fox:
            n.move(to: CGPoint(x: nx - 6, y: ny - 3))
            n.addQuadCurve(to: CGPoint(x: nx + 6, y: ny - 3), control: CGPoint(x: nx, y: ny - 6))
            n.addQuadCurve(to: CGPoint(x: nx, y: ny + 4), control: CGPoint(x: nx + 5, y: ny + 2))
            n.addQuadCurve(to: CGPoint(x: nx - 6, y: ny - 3), control: CGPoint(x: nx - 5, y: ny + 2))
        case .cat:
            n.move(to: CGPoint(x: nx - 5, y: ny - 3))
            n.addQuadCurve(to: CGPoint(x: nx + 5, y: ny - 3), control: CGPoint(x: nx, y: ny - 6))
            n.addQuadCurve(to: CGPoint(x: nx, y: ny + 4), control: CGPoint(x: nx + 4, y: ny + 1))
            n.addQuadCurve(to: CGPoint(x: nx - 5, y: ny - 3), control: CGPoint(x: nx - 4, y: ny + 1))
        case .bunny:
            n.move(to: CGPoint(x: nx - 4.5, y: ny - 3))
            n.addQuadCurve(to: CGPoint(x: nx + 4.5, y: ny - 3), control: CGPoint(x: nx, y: ny - 5.5))
            n.addQuadCurve(to: CGPoint(x: nx, y: ny + 3.5), control: CGPoint(x: nx + 4.5, y: ny + 1))
            n.addQuadCurve(to: CGPoint(x: nx - 4.5, y: ny - 3), control: CGPoint(x: nx - 4.5, y: ny + 1))
        case .hamster:
            n = ovalPath(nx, ny, 7, 5)
        case .axolotl:
            n = ovalPath(nx, ny, 5, 3.4)
        case .capybara:
            n = Path(roundedRect: CGRect(x: nx - 14, y: ny - 5, width: 28, height: 12), cornerRadius: 6)
        }
        n.closeSubpath()
        return n
    }

    private var noseColor: Color {
        switch species {
        case .cat, .bunny, .hamster, .axolotl: return nosePink
        case .capybara: return Color(red: 0.36, green: 0.23, blue: 0.22)
        default: return Fur.ink
        }
    }

    private var mouthHalfWidth: Double {
        switch species {
        case .dog: return 11
        case .cat, .panda: return 10
        case .fox: return 9
        case .bunny: return 8
        case .hamster: return 7
        case .axolotl: return 12
        case .capybara: return 8
        }
    }

    /// The classic "w" muzzle: a short stem from the nose with two soft curves sweeping
    /// out from its base. `lift` raises the curve ends for a happy mouth.
    private func omegaMouth(_ c: GraphicsContext, lift: Double) {
        if species == .axolotl {
            // a wide, forever smile with a dimple at each end
            let y0 = G.noseC.y + 6
            var m = Path()
            m.move(to: CGPoint(x: G.noseC.x - 22, y: y0 - 3 - lift * 0.6))
            m.addQuadCurve(to: CGPoint(x: G.noseC.x + 22, y: y0 - 3 - lift * 0.6), control: CGPoint(x: G.noseC.x, y: y0 + 10 + lift * 0.5))
            c.stroke(m, with: .color(Fur.ink), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            for sd in [-1.0, 1.0] {
                var d = Path()
                d.move(to: CGPoint(x: G.noseC.x + sd * 24.5, y: y0 - 8 - lift * 0.6))
                d.addLine(to: CGPoint(x: G.noseC.x + sd * 22, y: y0 - 2.5 - lift * 0.6))
                c.stroke(d, with: .color(Fur.ink.opacity(0.8)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
            return
        }
        if species == .capybara {
            // a tiny, perfectly calm mouth
            var m = Path()
            m.move(to: CGPoint(x: G.noseC.x - 7, y: G.noseC.y + 12 - lift * 0.4))
            m.addQuadCurve(to: CGPoint(x: G.noseC.x + 7, y: G.noseC.y + 12 - lift * 0.4), control: CGPoint(x: G.noseC.x, y: G.noseC.y + 16 + lift * 0.4))
            c.stroke(m, with: .color(Fur.ink.opacity(0.85)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            return
        }
        let top = G.noseC.y + 3
        let junction = top + 6
        let mw = mouthHalfWidth
        var stem = Path()
        stem.move(to: CGPoint(x: G.noseC.x, y: top))
        stem.addLine(to: CGPoint(x: G.noseC.x, y: junction))
        c.stroke(stem, with: .color(Fur.ink.opacity(0.75)), style: StrokeStyle(lineWidth: 2.0, lineCap: .round))
        var m = Path()
        m.move(to: CGPoint(x: G.noseC.x - mw, y: junction - lift))
        m.addQuadCurve(to: CGPoint(x: G.noseC.x, y: junction), control: CGPoint(x: G.noseC.x - mw / 2, y: junction + 4))
        m.addQuadCurve(to: CGPoint(x: G.noseC.x + mw, y: junction - lift), control: CGPoint(x: G.noseC.x + mw / 2, y: junction + 4))
        c.stroke(m, with: .color(Fur.ink), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
    }

    private func drawMouthAndNose(_ c: GraphicsContext) {
        let n = G.noseC, mz = G.muzzleC
        if p.stretch > 0.4 {
            // a satisfied yawn, whatever the mood
            c.fill(ovalPath(mz.x, mz.y + 4, 11, 9), with: .color(Fur.ink.opacity(0.85)))
            c.fill(nosePath(), with: .color(noseColor))
            return
        }
        // a tiny tongue blep every so often when she's just hanging out
        let blep = p.events?.blep ?? Self.blep(at: T, emotion: p.emotion, sleep: p.sleep, walk: p.walk)

        switch p.emotion {
        case .angry:
            let open = 8 + abs(sin(T * 12)) * 8
            c.fill(Path(ellipseIn: CGRect(x: mz.x - 11, y: mz.y - 2, width: 22, height: open)), with: .color(Fur.ink.opacity(0.85)))
            c.fill(Path(ellipseIn: CGRect(x: mz.x - 6, y: mz.y + open * 0.3, width: 12, height: open * 0.5)), with: .color(Fur.tongue))
        case .moody:
            var m = Path()
            m.move(to: CGPoint(x: n.x - 7, y: n.y + 12))
            m.addQuadCurve(to: CGPoint(x: n.x + 7, y: n.y + 12), control: CGPoint(x: n.x, y: n.y + 7.5))
            c.stroke(m, with: .color(Fur.ink), style: StrokeStyle(lineWidth: 2.0, lineCap: .round))
        case .happy, .excited, .playful, .love, .alert, .blissful, .proud, .hyped, .vibing, .cozy:
            if p.emotion == .excited || p.emotion == .playful || p.emotion == .love || p.emotion == .hyped {
                let loll = 1 + sin(T * 6) * 0.12
                c.fill(ovalPath(n.x, n.y + 14, 9.5, 10 * loll), with: .color(Fur.tongue))
            } else if species == .dog && p.emotion != .cozy && p.emotion != .proud {
                c.fill(ovalPath(n.x, n.y + 14.5, 9, 9.5), with: .color(Fur.tongue))
                c.stroke(Path { $0.move(to: CGPoint(x: n.x, y: n.y + 11)); $0.addLine(to: CGPoint(x: n.x, y: n.y + 16)) },
                         with: .color(.black.opacity(0.12)), lineWidth: 1)
            } else if blep > 0.1 {
                c.fill(ovalPath(n.x + 5, n.y + 13 + blep * 1.5, 6.5 * blep + 1, 6 * blep + 1), with: .color(Fur.tongue))
            }
            omegaMouth(c, lift: 4)
            bunnyTeeth(c)
        case .curious:
            c.stroke(ovalPath(n.x, n.y + 11, 6, 7), with: .color(Fur.ink), lineWidth: 2.0)
        case .shy:
            omegaMouth(c, lift: 0)
        case .worried:
            omegaMouth(c, lift: -3)
        case .bored:
            var m = Path()
            m.move(to: CGPoint(x: n.x - 8, y: n.y + 10))
            m.addLine(to: CGPoint(x: n.x + 8, y: n.y + 10))
            c.stroke(m, with: .color(Fur.ink), style: StrokeStyle(lineWidth: 2.0, lineCap: .round))
        case .eating, .hungry:
            let chomp = p.emotion == .eating ? abs(sin(T * 14)) * 6 : 2
            c.fill(Path(ellipseIn: CGRect(x: mz.x - 9, y: mz.y - 1, width: 18, height: 4 + chomp)), with: .color(Fur.ink.opacity(0.85)))
            c.fill(capsulePath(mz.x + 4, mz.y + 5, 9, 10), with: .color(Fur.tongue))
        case .sad:
            var m = Path()
            m.move(to: CGPoint(x: n.x - 8, y: n.y + 13))
            m.addQuadCurve(to: CGPoint(x: n.x + 8, y: n.y + 13), control: CGPoint(x: n.x, y: n.y + 6))
            c.stroke(m, with: .color(Fur.ink), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        case .sleepy:
            c.fill(ovalPath(mz.x, mz.y + 3, 9, 7), with: .color(Fur.ink.opacity(0.85)))
        default:
            if blep > 0.1 {
                c.fill(ovalPath(n.x + 5, n.y + 13 + blep * 1.5, 6.5 * blep + 1, 6 * blep + 1), with: .color(Fur.tongue))
            }
            omegaMouth(c, lift: 1)
        }
        c.fill(nosePath(), with: .color(noseColor))
        // a glint on the nose: wet noses are what make a face look alive
        c.fill(ovalPath(n.x - 2, n.y - 2, 3.2, 2.2), with: .color(.white.opacity(0.7)))
    }

    private func bunnyTeeth(_ c: GraphicsContext) {
        guard species == .bunny || species == .hamster else { return }
        let small = species == .hamster
        let r = small ? CGRect(x: G.noseC.x - 3.2, y: G.noseC.y + 9, width: 6.4, height: 5)
                      : CGRect(x: G.noseC.x - 4.5, y: G.noseC.y + 8.5, width: 9, height: 7)
        let tooth = Path(roundedRect: r, cornerRadius: 2)
        c.fill(tooth, with: .color(.white))
        c.stroke(tooth, with: .color(Fur.ink.opacity(0.35)), lineWidth: 1)
        var line = Path()
        line.move(to: CGPoint(x: G.noseC.x, y: r.minY + 1))
        line.addLine(to: CGPoint(x: G.noseC.x, y: r.maxY - 1))
        c.stroke(line, with: .color(Fur.ink.opacity(0.3)), lineWidth: 0.9)
    }

    // MARK: Eyes

    private func drawEyes(_ c: GraphicsContext) {
        // eyes drift a little even when she's idle: a perfectly fixed stare is uncanny
        let drift = (p.emotion == .neutral || p.emotion == .happy) && p.walk < 0.3
            ? CGVector(dx: (sin(T * 1) + sin(T * 1.5)) * 0.14, dy: sin(T * 1.5) * 0.08) : .zero
        let lookX = (p.look.dx + drift.dx) * 3.2
        let lookY = (p.look.dy + drift.dy + ((p.prop == .book || p.prop == .console) ? 0.7 * p.propAmt : 0)) * 2.6
        let size: (Double, Double)
        switch species {
        case .hamster: size = (20, 23)
        case .axolotl: size = (18, 20.5)
        case .capybara: size = (17.5, 20.5)
        default: size = (22, 25.5)
        }
        for (i, e) in [G.eyeL, G.eyeR].enumerated() {
            let far = i == 0
            let ctr = CGPoint(x: e.x + lookX, y: e.y + lookY)
            drawEye(c, at: ctr, w: far ? size.0 - 1.5 : size.0, h: far ? size.1 - 1.5 : size.1, far: far)
        }
        drawBrows(c)
    }

    private func drawEye(_ c: GraphicsContext, at ctr: CGPoint, w: Double, h: Double, far: Bool) {
        let stroke = StrokeStyle(lineWidth: 3.2, lineCap: .round)
        switch p.emotion {
        case .love:
            let pulse = 1 + sin(T * 6) * 0.10
            c.fill(heartPath(center: ctr, size: w * 1.35 * pulse), with: .color(Fur.heart))
            c.fill(ovalPath(ctr.x - w * 0.22, ctr.y - w * 0.2, w * 0.26, w * 0.2), with: .color(.white.opacity(0.75)))

        case .happy, .eating, .proud, .vibing:
            var a = Path()
            a.move(to: CGPoint(x: ctr.x - w * 0.55, y: ctr.y + 2))
            a.addQuadCurve(to: CGPoint(x: ctr.x + w * 0.55, y: ctr.y + 2), control: CGPoint(x: ctr.x, y: ctr.y - h * 0.55))
            c.stroke(a, with: .color(eyeInk), style: stroke)

        case .sleepy, .cozy:
            var a = Path()
            a.move(to: CGPoint(x: ctr.x - w * 0.55, y: ctr.y))
            a.addQuadCurve(to: CGPoint(x: ctr.x + w * 0.55, y: ctr.y), control: CGPoint(x: ctr.x, y: ctr.y + h * 0.42))
            c.stroke(a, with: .color(eyeInk), style: StrokeStyle(lineWidth: 3.0, lineCap: .round))

        case .blissful:
            let pulse = 1 + sin(T * 5) * 0.14
            var star = Path()
            let r1 = w * 0.64 * pulse, r2 = w * 0.23 * pulse
            for i in 0..<8 {
                let ang = Double(i) * .pi / 4 - .pi / 2
                let r = i % 2 == 0 ? r1 : r2
                let pt = CGPoint(x: ctr.x + cos(ang) * r, y: ctr.y + sin(ang) * r * (h / w))
                if i == 0 { star.move(to: pt) } else { star.addLine(to: pt) }
            }
            star.closeSubpath()
            c.fill(star, with: .color(Fur.heart))

        case .shy:
            var a = Path()
            a.move(to: CGPoint(x: ctr.x - w * 0.5, y: ctr.y - 2))
            a.addQuadCurve(to: CGPoint(x: ctr.x + w * 0.5, y: ctr.y - 2), control: CGPoint(x: ctr.x, y: ctr.y + h * 0.4))
            c.stroke(a, with: .color(eyeInk), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))

        case .bored, .moody:
            c.fill(ovalPath(ctr.x, ctr.y + h * 0.14, w * 0.65, h * 0.33), with: .color(eyeInk))
            var lid = Path()
            lid.move(to: CGPoint(x: ctr.x - w * 0.5, y: ctr.y - h * 0.08))
            lid.addLine(to: CGPoint(x: ctr.x + w * 0.5, y: ctr.y - h * 0.08))
            c.stroke(lid, with: .color(eyeInk), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))

        case .angry:
            c.fill(ovalPath(ctr.x, ctr.y + 2, w * 0.9, h * 0.55), with: .color(eyeInk))

        case .dizzy:
            var s = Path()
            for t in Swift.stride(from: 0.0, through: 3.2 * .pi, by: 0.24) {
                let r = t * 1.05
                let pt = CGPoint(x: ctr.x + cos(t + T * 8) * r, y: ctr.y + sin(t + T * 8) * r)
                if t == 0 { s.move(to: pt) } else { s.addLine(to: pt) }
            }
            c.stroke(s, with: .color(eyeInk), style: StrokeStyle(lineWidth: 2.0, lineCap: .round))

        default:
            let k = 1 - blink
            if k < 0.16 {
                var a = Path()
                a.move(to: CGPoint(x: ctr.x - w * 0.5, y: ctr.y))
                a.addLine(to: CGPoint(x: ctr.x + w * 0.5, y: ctr.y))
                c.stroke(a, with: .color(eyeInk), style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
                return
            }
            let big = (p.emotion == .alert || p.emotion == .excited || p.emotion == .curious || p.emotion == .hyped) ? 1.1 : 1.0
            let ew = w * big, eh = h * k * big
            let eye = ovalPath(ctr.x, ctr.y, ew, eh)
            c.fill(eye, with: .linearGradient(
                Gradient(colors: [eyeInk, Color(red: 0.30, green: 0.22, blue: 0.34)]),
                startPoint: CGPoint(x: ctr.x, y: ctr.y - eh / 2), endPoint: CGPoint(x: ctr.x, y: ctr.y + eh / 2)))
            // a coloured iris glowing up from the bottom of the eye: what makes it look wet and deep
            var iris = c
            iris.clip(to: eye)
            iris.fill(ovalPath(ctr.x, ctr.y + eh * 0.2, ew * 0.95, eh * 0.7), with: .radialGradient(
                Gradient(colors: [irisColor.opacity(0.95), irisColor.opacity(0)]),
                center: CGPoint(x: ctr.x, y: ctr.y + eh * 0.32), startRadius: 1, endRadius: ew * 0.58))
            if species == .capybara && big == 1.0 {
                // heavy lids: she is unbothered
                var lid = c
                lid.clip(to: eye)
                let lidH = eh * 0.4
                lid.fill(Path(CGRect(x: ctr.x - ew, y: ctr.y - eh / 2 - 2, width: ew * 2, height: lidH + 2)), with: .color(coat.mid))
                c.stroke(Path { $0.move(to: CGPoint(x: ctr.x - ew * 0.36, y: ctr.y - eh / 2 + lidH)); $0.addLine(to: CGPoint(x: ctr.x + ew * 0.36, y: ctr.y - eh / 2 + lidH)) },
                         with: .color(eyeInk), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
            // two highlights plus a pinprick: one reads flat, two reads glossy, three reads kawaii
            let thrill = (p.emotion == .excited || p.emotion == .alert || p.emotion == .hyped) ? 1 + sin(T * 8) * 0.12 : 1
            c.fill(ovalPath(ctr.x - ew * 0.18, ctr.y - eh * 0.22, ew * 0.44 * thrill, eh * 0.38 * thrill), with: .color(.white.opacity(0.97)))
            c.fill(ovalPath(ctr.x + ew * 0.2, ctr.y + eh * 0.22, ew * 0.19, eh * 0.16), with: .color(.white.opacity(0.75)))
            c.fill(ovalPath(ctr.x - ew * 0.27, ctr.y + eh * 0.08, ew * 0.08, eh * 0.07), with: .color(.white.opacity(0.7)))
            if p.emotion == .sad {
                let t = T.truncatingRemainder(dividingBy: Loop.period / 5) / (Loop.period / 5)
                let ty = ctr.y + eh * 0.5 + t * 18
                c.fill(ovalPath(ctr.x + (far ? -5 : 6), ty, 4.5, 7),
                       with: .color(Color(red: 0.55, green: 0.78, blue: 1.0).opacity(0.85 * (1 - t))))
            }
        }
    }

    private func drawBrows(_ c: GraphicsContext) {
        if species == .dog {
            // the two little tan dots above a puppy's eyes: the cutest marking there is
            switch p.emotion {
            case .angry, .sad, .hungry, .worried, .alert, .moody, .curious: break
            default:
                for e in [G.eyeL, G.eyeR] {
                    c.fill(ovalPath(e.x + p.look.dx * 1.5, e.y - 22, 8, 6), with: .color(coat.patch.opacity(0.85)))
                }
            }
        }
        func brow(_ e: CGPoint, mirrored: Bool, angle: Double, lift: Double) {
            var g = c
            g.translateBy(x: e.x + p.look.dx * 2, y: e.y - 18 + lift)
            if mirrored { g.scaleBy(x: -1, y: 1) }
            g.rotate(by: .degrees(angle))
            var b = Path()
            b.move(to: CGPoint(x: -5, y: 0))
            b.addLine(to: CGPoint(x: 5, y: 0))
            g.stroke(b, with: .color(Fur.ink.opacity(0.8)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        }
        switch p.emotion {
        case .angry:
            brow(G.eyeL, mirrored: true, angle: -26, lift: 3); brow(G.eyeR, mirrored: false, angle: -26, lift: 3)
        case .sad, .hungry:
            brow(G.eyeL, mirrored: true, angle: 20, lift: -1); brow(G.eyeR, mirrored: false, angle: 20, lift: -1)
        case .worried:
            brow(G.eyeL, mirrored: true, angle: 28, lift: -3); brow(G.eyeR, mirrored: false, angle: 28, lift: -3)
        case .alert:
            brow(G.eyeL, mirrored: true, angle: -6, lift: -4); brow(G.eyeR, mirrored: false, angle: -6, lift: -4)
        case .moody:
            brow(G.eyeL, mirrored: true, angle: -13, lift: 2); brow(G.eyeR, mirrored: false, angle: -13, lift: 2)
        case .curious:
            brow(G.eyeL, mirrored: true, angle: 4, lift: -2); brow(G.eyeR, mirrored: false, angle: -14, lift: -7)
        default: break
        }
    }

    // MARK: Accessories

    private func starPath(_ r: Double) -> Path {
        var s = Path()
        for i in 0..<10 {
            let a = Double(i) * .pi / 5 - .pi / 2
            let rad = i % 2 == 0 ? r : r * 0.45
            let pt = CGPoint(x: cos(a) * rad, y: sin(a) * rad)
            if i == 0 { s.move(to: pt) } else { s.addLine(to: pt) }
        }
        s.closeSubpath()
        return s
    }

    /// Everything worn on the head and face. Drawn after the face so it sits on top.
    private func drawHeadAccessory(_ ctx: GraphicsContext) {
        drawHeadItem(ctx, p.outfit.head)
        drawHeadItem(ctx, p.outfit.hair)
        drawFaceItem(ctx, p.outfit.face)
    }

    private func drawHeadItem(_ ctx: GraphicsContext, _ item: Accessory) {
        let hw = headW / 2, hh = headH / 2
        switch item {
        case .bow:
            var c = ctx
            c.translateBy(x: G.headC.x + hw * 0.52, y: G.headC.y - hh * 0.62)
            c.rotate(by: .degrees(16 + sin(T * 2) * 2))
            let pink = Color(red: 0.98, green: 0.56, blue: 0.72), deep = Color(red: 0.88, green: 0.38, blue: 0.58)
            for sd in [-1.0, 1.0] {
                let loop = ovalPath(sd * 11, 0, 20, 15)
                c.fill(loop, with: .color(pink))
                c.stroke(loop, with: .color(deep), lineWidth: 1.2)
                c.fill(ovalPath(sd * 12, -2.5, 8, 4), with: .color(.white.opacity(0.45)))
            }
            c.fill(ovalPath(0, 0, 9, 9), with: .color(deep))
            c.fill(ovalPath(-1, -1.5, 3.4, 2.6), with: .color(.white.opacity(0.5)))

        case .flower:
            var c = ctx
            c.translateBy(x: G.headC.x - hw * 0.5, y: G.headC.y - hh * 0.55)
            c.rotate(by: .degrees(-14 + sin(T * 1.5) * 3))
            for i in 0..<5 {
                var pe = c
                pe.rotate(by: .degrees(Double(i) * 72))
                let petal = ovalPath(0, -8, 9.5, 12)
                pe.fill(petal, with: .color(Color(red: 1.0, green: 0.80, blue: 0.88)))
                pe.stroke(petal, with: .color(Color(red: 0.93, green: 0.55, blue: 0.70).opacity(0.7)), lineWidth: 1)
            }
            c.fill(ovalPath(0, 0, 9, 9), with: .color(Color(red: 1.0, green: 0.84, blue: 0.32)))
            c.fill(ovalPath(-1.5, -1.5, 3, 3), with: .color(.white.opacity(0.6)))

        case .crown:
            var c = ctx
            c.translateBy(x: G.headC.x + 2, y: G.headC.y - hh + 5)
            c.rotate(by: .degrees(6))
            var crown = Path()
            crown.move(to: CGPoint(x: -16, y: 2))
            crown.addLine(to: CGPoint(x: -17, y: -15))
            crown.addLine(to: CGPoint(x: -8, y: -7))
            crown.addLine(to: CGPoint(x: 0, y: -19))
            crown.addLine(to: CGPoint(x: 8, y: -7))
            crown.addLine(to: CGPoint(x: 17, y: -15))
            crown.addLine(to: CGPoint(x: 16, y: 2))
            crown.closeSubpath()
            c.fill(crown, with: .linearGradient(
                Gradient(colors: [Color(red: 1.0, green: 0.90, blue: 0.45), Color(red: 0.95, green: 0.70, blue: 0.22)]),
                startPoint: CGPoint(x: 0, y: -19), endPoint: CGPoint(x: 0, y: 2)))
            c.stroke(crown, with: .color(Color(red: 0.80, green: 0.55, blue: 0.15)), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
            for (x, y, col) in [(0.0, -6.0, Color(red: 0.95, green: 0.4, blue: 0.55)), (-9.0, -2.0, Color(red: 0.5, green: 0.7, blue: 1)), (9.0, -2.0, Color(red: 0.5, green: 0.85, blue: 0.6))] {
                c.fill(ovalPath(x, y, 4.4, 4.4), with: .color(col))
            }

        case .headphones:
            let band = Color(red: 0.98, green: 0.66, blue: 0.82), cup = Color(red: 0.96, green: 0.52, blue: 0.72)
            var arc = Path()
            arc.addArc(center: CGPoint(x: G.headC.x, y: G.headC.y + 4), radius: hw * 0.96,
                       startAngle: .degrees(188), endAngle: .degrees(352), clockwise: false)
            ctx.stroke(arc, with: .color(cup.opacity(0.55)), style: StrokeStyle(lineWidth: 8.6, lineCap: .round))
            ctx.stroke(arc, with: .color(band), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            for sd in [-1.0, 1.0] {
                let r = CGRect(x: G.headC.x + sd * hw * 0.96 - 8, y: G.headC.y - 6, width: 16, height: 26)
                let cupPath = Path(roundedRect: r, cornerRadius: 8)
                ctx.fill(cupPath, with: .color(cup))
                ctx.stroke(cupPath, with: .color(.white.opacity(0.55)), lineWidth: 1.6)
                ctx.fill(ovalPath(r.midX, r.midY, 7, 12), with: .color(.white.opacity(0.4)))
            }

        case .yuzu:
            var c = ctx
            c.translateBy(x: G.headC.x + 4, y: G.headC.y - hh + 1 + sin(T * 2) * 0.8)
            c.rotate(by: .degrees(sin(T * 1.5) * 3 + p.look.dx * 3))
            let fruit = ovalPath(0, -6, 22, 19)
            c.fill(fruit, with: .radialGradient(
                Gradient(colors: [Color(red: 1.0, green: 0.88, blue: 0.40), Color(red: 1.0, green: 0.68, blue: 0.20)]),
                center: CGPoint(x: -4, y: -10), startRadius: 1, endRadius: 14))
            c.stroke(fruit, with: .color(Color(red: 0.88, green: 0.52, blue: 0.10).opacity(0.6)), lineWidth: 1.1)
            c.fill(ovalPath(-4.5, -10, 6, 3.6), with: .color(.white.opacity(0.6)))
            c.fill(ovalPath(5, -4, 1.6, 1.6), with: .color(Color(red: 0.9, green: 0.55, blue: 0.1).opacity(0.5)))
            var leaf = Path()
            leaf.move(to: CGPoint(x: 0, y: -15))
            leaf.addQuadCurve(to: CGPoint(x: 11, y: -21), control: CGPoint(x: 5, y: -22))
            leaf.addQuadCurve(to: CGPoint(x: 0, y: -15), control: CGPoint(x: 8, y: -13))
            c.fill(leaf, with: .color(Color(red: 0.50, green: 0.78, blue: 0.40)))

        case .beret:
            // a soft rose beret, tipped to one side: very "just left the art gallery"
            var c = ctx
            c.translateBy(x: G.headC.x + hw * 0.14, y: G.headC.y - hh + 7)
            c.rotate(by: .degrees(-13))
            let dome = ovalPath(0, -6, 54, 25)
            c.fill(dome, with: .linearGradient(
                Gradient(colors: [Color(red: 1.0, green: 0.72, blue: 0.78), Color(red: 0.92, green: 0.48, blue: 0.62)]),
                startPoint: CGPoint(x: 0, y: -18), endPoint: CGPoint(x: 0, y: 6)))
            c.stroke(dome, with: .color(Color(red: 0.80, green: 0.36, blue: 0.52).opacity(0.7)), lineWidth: 1.2)
            c.fill(ovalPath(-10, -13, 18, 5), with: .color(.white.opacity(0.4)))
            c.fill(ovalPath(2, -19, 6, 6), with: .color(Color(red: 0.86, green: 0.40, blue: 0.56)))

        case .starClip:
            var c = ctx
            c.translateBy(x: G.headC.x - hw * 0.5, y: G.headC.y - hh * 0.32)
            c.rotate(by: .degrees(-12 + sin(T * 2.5) * 4))
            let star = starPath(10)
            c.fill(star, with: .linearGradient(
                Gradient(colors: [Color(red: 1.0, green: 0.94, blue: 0.55), Color(red: 1.0, green: 0.76, blue: 0.25)]),
                startPoint: CGPoint(x: 0, y: -10), endPoint: CGPoint(x: 0, y: 10)))
            c.stroke(star, with: .color(Color(red: 0.88, green: 0.60, blue: 0.12)), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
            c.fill(ovalPath(-2, -3, 3.4, 3.4), with: .color(.white.opacity(0.7)))

        case .partyHat:
            var c = ctx
            c.translateBy(x: G.headC.x + hw * 0.12, y: G.headC.y - hh + 6)
            c.rotate(by: .degrees(13 + sin(T * 3) * 1.5))
            var cone = Path()
            cone.move(to: CGPoint(x: -15, y: 3))
            cone.addLine(to: CGPoint(x: 0, y: -36))
            cone.addLine(to: CGPoint(x: 15, y: 3))
            cone.closeSubpath()
            c.fill(cone, with: .linearGradient(
                Gradient(colors: [Color(red: 0.72, green: 0.62, blue: 1.0), Color(red: 1.0, green: 0.62, blue: 0.80)]),
                startPoint: CGPoint(x: -15, y: 0), endPoint: CGPoint(x: 15, y: -20)))
            c.stroke(cone, with: .color(Color(red: 0.62, green: 0.46, blue: 0.86).opacity(0.7)), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
            for (x, y) in [(-5.0, -5.0), (4.0, -12.0), (-1.0, -20.0), (6.0, -2.0)] {
                c.fill(ovalPath(x, y, 3.4, 3.4), with: .color(.white.opacity(0.85)))
            }
            c.fill(ovalPath(0, -37, 9, 9), with: .color(Color(red: 1.0, green: 0.90, blue: 0.45)))

        case .halo:
            let bob = sin(T * 2) * 2
            let ring = ovalPath(G.headC.x + 2, G.headC.y - hh - 9 + bob, 42, 11)
            ctx.stroke(ring, with: .color(Color(red: 1.0, green: 0.88, blue: 0.4).opacity(0.35)), lineWidth: 9)
            ctx.stroke(ring, with: .color(Color(red: 1.0, green: 0.86, blue: 0.35)), lineWidth: 4.2)
            ctx.stroke(ring, with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: 1.4, dash: [5, 14]))

        default: break
        }
    }

    private func drawFaceItem(_ ctx: GraphicsContext, _ item: Accessory) {
        switch item {
        case .glasses:
            let frame = Color(red: 0.40, green: 0.30, blue: 0.52)
            for e in [G.eyeL, G.eyeR] {
                let lens = ovalPath(e.x + p.look.dx * 1.2, e.y, 33, 33)
                ctx.fill(lens, with: .color(.white.opacity(0.14)))
                ctx.stroke(lens, with: .color(frame), lineWidth: 2.6)
                var glint = Path()
                glint.addArc(center: CGPoint(x: e.x - 2, y: e.y), radius: 11.5,
                             startAngle: .degrees(205), endAngle: .degrees(250), clockwise: false)
                ctx.stroke(glint, with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            bridge(ctx, color: frame)

        case .sunglasses:
            let frame = Color(red: 0.22, green: 0.18, blue: 0.30)
            for e in [G.eyeL, G.eyeR] {
                let lens = Path(roundedRect: CGRect(x: e.x - 17, y: e.y - 11, width: 34, height: 25), cornerRadius: 9)
                ctx.fill(lens, with: .linearGradient(
                    Gradient(colors: [Color(red: 0.30, green: 0.24, blue: 0.42), Color(red: 0.14, green: 0.11, blue: 0.22)]),
                    startPoint: CGPoint(x: e.x, y: e.y - 11), endPoint: CGPoint(x: e.x, y: e.y + 14)))
                ctx.stroke(lens, with: .color(frame), lineWidth: 2.2)
                var glint = Path()
                glint.move(to: CGPoint(x: e.x - 11, y: e.y - 3)); glint.addLine(to: CGPoint(x: e.x - 4, y: e.y - 8))
                ctx.stroke(glint, with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            }
            bridge(ctx, color: frame)

        case .heartGlasses:
            let frame = Color(red: 0.93, green: 0.42, blue: 0.64)
            for e in [G.eyeL, G.eyeR] {
                let heart = heartPath(center: CGPoint(x: e.x + p.look.dx * 1.2, y: e.y + 1), size: 40)
                ctx.fill(heart, with: .color(Color(red: 1.0, green: 0.62, blue: 0.80).opacity(0.5)))
                ctx.stroke(heart, with: .color(frame), style: StrokeStyle(lineWidth: 2.6, lineJoin: .round))
                ctx.fill(ovalPath(e.x - 8, e.y - 6, 7, 4), with: .color(.white.opacity(0.7)))
            }
            bridge(ctx, color: frame)

        case .lashes:
            // long curled lashes on the outer corner of each eye
            for (e, sd) in [(G.eyeL, -1.0), (G.eyeR, 1.0)] {
                for (i, ang) in [-62.0, -38.0, -14.0].enumerated() {
                    let a = (ang * sd + (sd < 0 ? 180 : 0) * 0) * .pi / 180
                    let base = CGPoint(x: e.x + sd * 8 + cos(a) * 0, y: e.y - 9 + Double(i) * 2.5)
                    var l = Path()
                    l.move(to: base)
                    l.addQuadCurve(to: CGPoint(x: base.x + sd * (13 - Double(i)), y: base.y - 7 + Double(i) * 2),
                                   control: CGPoint(x: base.x + sd * 8, y: base.y - 9 + Double(i)))
                    ctx.stroke(l, with: .color(Fur.ink.opacity(0.9)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                }
            }

        default: break
        }
    }

    private func bridge(_ ctx: GraphicsContext, color: Color) {
        var b = Path()
        b.move(to: CGPoint(x: G.eyeL.x + 16, y: G.eyeL.y - 2))
        b.addQuadCurve(to: CGPoint(x: G.eyeR.x - 16, y: G.eyeR.y - 2),
                       control: CGPoint(x: (G.eyeL.x + G.eyeR.x) / 2, y: G.eyeL.y - 8))
        ctx.stroke(b, with: .color(color), lineWidth: 2.4)
    }

    /// Everything worn around the neck: drawn under the chin so the head overlaps it.
    private func drawNeckItem(_ ctx: GraphicsContext) {
        let y0 = G.headC.y + headH / 2 - 7
        let nx = G.neck.x
        switch p.outfit.neck {
        case .scarf:
            let red = Color(red: 0.93, green: 0.45, blue: 0.50)
            var band = Path()
            band.move(to: CGPoint(x: nx - 34, y: y0 + 2))
            band.addQuadCurve(to: CGPoint(x: nx + 36, y: y0 - 1), control: CGPoint(x: nx + 2, y: y0 + 20))
            ctx.stroke(band, with: .color(red.opacity(0.5)), style: StrokeStyle(lineWidth: 14.5, lineCap: .round))
            ctx.stroke(band, with: .color(red), style: StrokeStyle(lineWidth: 12, lineCap: .round))
            ctx.stroke(band, with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: 12, dash: [3.5, 9]))
            let swing = sin(T * 2.5 + p.gait * 0.5) * 4 + p.walk * sin(p.gait) * 5
            var tail = ctx
            tail.translateBy(x: nx + 22, y: y0 + 8)
            tail.rotate(by: .degrees(swing))
            let end = capsulePath(0, 12, 13, 28)
            tail.fill(end, with: .color(red))
            tail.stroke(end, with: .color(red.opacity(0.5)), lineWidth: 1.3)
            for y in [8.0, 17.0] { tail.fill(Path(CGRect(x: -6.5, y: y, width: 13, height: 3)), with: .color(.white.opacity(0.55))) }

        case .bandana:
            let pink = Color(red: 0.98, green: 0.58, blue: 0.70)
            var tri = Path()
            tri.move(to: CGPoint(x: nx - 30, y: y0 - 1))
            tri.addQuadCurve(to: CGPoint(x: nx + 32, y: y0 - 3), control: CGPoint(x: nx + 1, y: y0 + 7))
            tri.addLine(to: CGPoint(x: nx + 2 + sin(T * 2) * 1.5, y: y0 + 30))
            tri.closeSubpath()
            ctx.fill(tri, with: .linearGradient(
                Gradient(colors: [pink, Color(red: 0.92, green: 0.44, blue: 0.62)]),
                startPoint: CGPoint(x: nx, y: y0), endPoint: CGPoint(x: nx, y: y0 + 30)))
            ctx.stroke(tri, with: .color(Color(red: 0.82, green: 0.34, blue: 0.54).opacity(0.7)), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
            for (dx, dy) in [(-14.0, 4.0), (-2.0, 12.0), (10.0, 3.0), (3.0, 21.0), (-9.0, 16.0)] {
                ctx.fill(ovalPath(nx + dx, y0 + dy, 3.6, 3.6), with: .color(.white.opacity(0.85)))
            }

        case .pearls:
            var path = Path()
            path.move(to: CGPoint(x: nx - 30, y: y0 + 1))
            path.addQuadCurve(to: CGPoint(x: nx + 32, y: y0 - 2), control: CGPoint(x: nx + 1, y: y0 + 24))
            // pearls spaced along the curve
            for i in 0...10 {
                let t = Double(i) / 10, mt = 1 - t
                let x = mt * mt * (nx - 30) + 2 * mt * t * (nx + 1) + t * t * (nx + 32)
                let y = mt * mt * (y0 + 1) + 2 * mt * t * (y0 + 24) + t * t * (y0 - 2)
                ctx.fill(ovalPath(x, y, 8.2, 8.2), with: .radialGradient(
                    Gradient(colors: [.white, Color(red: 0.93, green: 0.90, blue: 0.97)]),
                    center: CGPoint(x: x - 1.5, y: y - 1.5), startRadius: 0.5, endRadius: 5.5))
                ctx.stroke(ovalPath(x, y, 8.2, 8.2), with: .color(Color(red: 0.82, green: 0.78, blue: 0.9)), lineWidth: 0.7)
            }

        case .bell:
            var band = Path()
            band.move(to: CGPoint(x: nx - 30, y: y0 + 1))
            band.addQuadCurve(to: CGPoint(x: nx + 32, y: y0 - 2), control: CGPoint(x: nx + 1, y: y0 + 20))
            ctx.stroke(band, with: .color(Color(red: 0.93, green: 0.45, blue: 0.62)), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            ctx.stroke(band, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 6, dash: [2, 7]))
            var bell = ctx
            bell.translateBy(x: nx + 3, y: y0 + 15)
            bell.rotate(by: .degrees(sin(T * 3 + p.gait) * 6 * (0.3 + p.walk)))
            bell.fill(ovalPath(0, 5, 13, 13), with: .radialGradient(
                Gradient(colors: [Color(red: 1.0, green: 0.92, blue: 0.5), Color(red: 0.95, green: 0.72, blue: 0.22)]),
                center: CGPoint(x: -2, y: 2), startRadius: 1, endRadius: 9))
            bell.stroke(ovalPath(0, 5, 13, 13), with: .color(Color(red: 0.82, green: 0.58, blue: 0.14)), lineWidth: 1)
            bell.fill(Path(CGRect(x: -4.5, y: 6.5, width: 9, height: 1.6)), with: .color(Color(red: 0.7, green: 0.48, blue: 0.1)))
            bell.fill(ovalPath(0, 10, 3, 3), with: .color(Color(red: 0.7, green: 0.48, blue: 0.1)))

        case .bowtie:
            var c = ctx
            c.translateBy(x: nx + 2, y: y0 + 11)
            let col = Color(red: 0.95, green: 0.48, blue: 0.66), deep = Color(red: 0.82, green: 0.34, blue: 0.54)
            for sd in [-1.0, 1.0] {
                var wing = Path()
                wing.move(to: .zero)
                wing.addLine(to: CGPoint(x: sd * 15, y: -9))
                wing.addQuadCurve(to: CGPoint(x: sd * 15, y: 9), control: CGPoint(x: sd * 19, y: 0))
                wing.closeSubpath()
                c.fill(wing, with: .color(col))
                c.stroke(wing, with: .color(deep), style: StrokeStyle(lineWidth: 1.1, lineJoin: .round))
            }
            c.fill(ovalPath(0, 0, 8, 10), with: .color(deep))
            c.fill(ovalPath(-1, -2, 3, 2.4), with: .color(.white.opacity(0.5)))

        default: break
        }
    }

    // MARK: Grooming

    /// Her signature wash: a paw lifts and wipes across the cheek, drawn after the
    /// head so it reads as in front of the face.
    private func drawGroomingPaw(_ ctx: GraphicsContext) {
        guard p.groom > 0.02 else { return }
        let cycle = (T / (Loop.period / 28)).truncatingRemainder(dividingBy: 1.0)
        let lift = sin(cycle * .pi)
        let rest = CGPoint(x: G.headC.x - headW * 0.12, y: G.headC.y + headH * 0.58)
        let top = CGPoint(x: G.headC.x - headW * 0.30, y: G.headC.y - headH * 0.02)
        let x = rest.x + (top.x - rest.x) * lift
        let y = rest.y + (top.y - rest.y) * lift + (1 - p.groom) * 34

        var c = ctx
        c.opacity = min(1, p.groom * 2)
        c.translateBy(x: x, y: y)
        c.rotate(by: .degrees(-25 - lift * 20))
        let arm = capsulePath(0, 8, 12, 22)
        c.fill(arm, with: .linearGradient(Gradient(colors: [coat.mid, coat.shade]),
                                         startPoint: CGPoint(x: 0, y: -3), endPoint: CGPoint(x: 0, y: 16)))
        c.stroke(arm, with: .color(rim), lineWidth: 1.1)
        let mitt = ovalPath(0, -5, 14, 12)
        c.fill(mitt, with: .color(species == .panda || species == .fox ? coat.patch : coat.light))
        c.stroke(mitt, with: .color(rim), lineWidth: 1.1)
    }
}

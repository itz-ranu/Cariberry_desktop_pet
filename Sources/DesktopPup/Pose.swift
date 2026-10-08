import SwiftUI

// MARK: - Pose

/// Everything that can be animated about a pet for a single frame. Every "amount" is
/// a 0...1 value that `Pet` eases toward its target, so changing activity (sitting
/// down, turning round, breaking into a walk) glides instead of snapping.
struct Pose {
    var emotion: Emotion = .neutral
    var phase: Double = 0          // seconds of animation time (idle clock)
    var gait: Double = 0           // accumulated stride phase, advanced by `Pet`
    var walk: Double = 0           // 0 = standing, 1 = walking
    var run: Double = 0            // 0...1 extra speed on top of walking (zoomies)
    var facing: Double = 1         // 1 = right, -1 = left, eased through 0 on a turn
    var squash: Double = 0         // -1 stretched .. 0 normal .. 1 squashed
    var dangling: Bool = false     // held by the scruff (dragged)
    var look: CGVector = .zero     // -1..1 eye direction, eased
    var sit: Double = 0            // 0...1 sitting upright
    var sleep: Double = 0          // 0...1 curled up asleep
    var petting: Double = 0        // 0..1 how hard it is being scritched
    var stretch: Double = 0        // 0...1 play-bow stretch
    var sniff: Double = 0          // 0...1 nose to the ground
    var groom: Double = 0          // 0...1 washing her face with a paw
    var scratch: Double = 0        // 0...1 scratching an ear with a hind leg
    var dance: Double = 0          // 0...1 dancing on the spot
    var wave: Double = 0           // 0...1 waving hello with a front paw
    var bop: Double = 0            // 0...1 pulse on each beat of the music she's listening to
    var collarTier: Int = 0        // 0 = none, 1...5 = earned collar tiers
    var tapping: Bool = false      // reaching out to tap the Reels close button
    var tapPhase: Double = 0       // 0 = at rest, mid = fully reached and pressing, 1 = retracted
    var outfit = Outfit()
    var perched: Bool = false      // placed above the floor: she sits on a cushion
    var prop: Prop = .none         // what she's holding or next to
    var propAmt: Double = 0        // 0...1, eased so a prop pops in and out
    /// The three small things that happen on a beat while she rests, handed over ready-made. Set only when a
    /// frame is being drawn for the cache (see Sprites.swift); live drawing works them out from the clock.
    var events: RestEvents?
}

/// A blink, an ear flick and a tongue blep, each 0...1 (the flick -1...1).
struct RestEvents: Equatable {
    var blink = 0.0
    var flick = 0.0
    var blep = 0.0
}

enum Prop { case none, book, boba, matcha, console }

/// Shapes the one-shot reach-and-press arc of `tapping`: eases up to a held peak
/// (the moment the paw is actually on the button), then eases back down.
func tapRaise(_ phase: Double) -> Double {
    if phase < 0.4 { let t = phase / 0.4; return 1 - (1 - t) * (1 - t) }
    if phase < 0.6 { return 1 }
    let t = (phase - 0.6) / 0.4
    return max(0, 1 - t * t)
}

/// Exponential ease toward a target: frame-rate independent, so it feels the same at
/// 24 fps idle and 45 fps walking.
func ease(_ v: inout Double, to target: Double, rate: Double, dt: Double) {
    v += (target - v) * min(1, dt * rate)
    if abs(target - v) < 0.002 { v = target }
}

/// The collar she earns by levelling up: a band across the chest with a little tag
/// hanging off it. Shared by every species so an upgrade looks the same on all.
func drawCollar(_ ctx: GraphicsContext, tier: Int, at c: CGPoint, width: Double) {
    guard tier > 0 else { return }
    let colour = Progression.collarColor(tier: tier)

    var band = Path()
    band.move(to: CGPoint(x: c.x - width / 2, y: c.y - 3))
    band.addQuadCurve(to: CGPoint(x: c.x + width / 2, y: c.y - 5),
                      control: CGPoint(x: c.x, y: c.y + 7))
    ctx.stroke(band, with: .linearGradient(
        Gradient(colors: [colour.opacity(0.75), colour]),
        startPoint: CGPoint(x: c.x - width / 2, y: c.y),
        endPoint: CGPoint(x: c.x + width / 2, y: c.y)),
        style: StrokeStyle(lineWidth: 7, lineCap: .round))

    // the tag, with a highlight so it reads as metal rather than a flat dot
    let tagC = CGPoint(x: c.x + 2, y: c.y + 9)
    ctx.fill(ovalPath(tagC.x, tagC.y, 11, 11), with: .color(colour))
    ctx.fill(ovalPath(tagC.x - 2, tagC.y - 2, 4.5, 4), with: .color(.white.opacity(0.65)))
}

// MARK: - Small path helpers

@inline(__always) func ovalPath(_ cx: Double, _ cy: Double, _ w: Double, _ h: Double) -> Path {
    Path(ellipseIn: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h))
}

/// A shape between an ellipse and a rounded box. `square` 0...1 pushes it toward the box, `topW`/`botW`
/// fatten or slim the upper and lower halves (an egg, or a pair of chubby cheeks), and `sideY` drops the
/// widest line below centre.
func softBlob(_ cx: Double, _ cy: Double, _ w: Double, _ h: Double,
              topW: Double = 1, botW: Double = 1, square: Double = 0, sideY: Double = 0) -> Path {
    let k = 0.5523 + 0.2 * square
    let hw = w / 2, hh = h / 2
    let oy = sideY * h
    let top = CGPoint(x: cx, y: cy - hh), bot = CGPoint(x: cx, y: cy + hh)
    let right = CGPoint(x: cx + hw, y: cy + oy), left = CGPoint(x: cx - hw, y: cy + oy)
    var p = Path()
    p.move(to: top)
    p.addCurve(to: right, control1: CGPoint(x: cx + k * hw * topW, y: top.y), control2: CGPoint(x: right.x, y: right.y - k * (right.y - top.y)))
    p.addCurve(to: bot, control1: CGPoint(x: right.x, y: right.y + k * (bot.y - right.y)), control2: CGPoint(x: cx + k * hw * botW, y: bot.y))
    p.addCurve(to: left, control1: CGPoint(x: cx - k * hw * botW, y: bot.y), control2: CGPoint(x: left.x, y: left.y + k * (bot.y - left.y)))
    p.addCurve(to: top, control1: CGPoint(x: left.x, y: left.y - k * (left.y - top.y)), control2: CGPoint(x: cx - k * hw * topW, y: top.y))
    p.closeSubpath()
    return p
}

@inline(__always) func capsulePath(_ cx: Double, _ cy: Double, _ w: Double, _ h: Double) -> Path {
    Path(roundedRect: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h), cornerRadius: min(w, h) / 2)
}

func heartPath(center: CGPoint, size: Double) -> Path {
    var p = Path()
    let s = size / 2
    let x = center.x, y = center.y
    p.move(to: CGPoint(x: x, y: y + s * 0.95))
    p.addCurve(to: CGPoint(x: x - s, y: y - s * 0.25),
               control1: CGPoint(x: x - s * 0.55, y: y + s * 0.45),
               control2: CGPoint(x: x - s, y: y + s * 0.25))
    p.addArc(center: CGPoint(x: x - s * 0.5, y: y - s * 0.3), radius: s * 0.52,
             startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
    p.addArc(center: CGPoint(x: x + s * 0.5, y: y - s * 0.3), radius: s * 0.52,
             startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
    p.addCurve(to: CGPoint(x: x, y: y + s * 0.95),
               control1: CGPoint(x: x + s, y: y + s * 0.25),
               control2: CGPoint(x: x + s * 0.55, y: y + s * 0.45))
    p.closeSubpath()
    return p
}

extension GraphicsContext {
    /// Rotates about a pivot instead of the origin: the one transform every limb needs.
    mutating func rotate(degrees: Double, about p: CGPoint) {
        translateBy(x: p.x, y: p.y)
        rotate(by: .degrees(degrees))
        translateBy(x: -p.x, y: -p.y)
    }

    /// Scales about a pivot: squash-and-stretch anchors on the ground, breathing on the chest.
    mutating func scale(x: Double, y: Double, about p: CGPoint) {
        translateBy(x: p.x, y: p.y)
        scaleBy(x: x, y: y)
        translateBy(x: -p.x, y: -p.y)
    }
}

extension View {
    /// A white die-cut border, like a sticker: it keeps a pastel pet readable on any
    /// wallpaper, light or dark. Four crisp offset copies, then a soft shadow.
    func stickerOutline(_ width: CGFloat = 3.4) -> some View {
        self
            .shadow(color: .white, radius: 0, x: width, y: 0)
            .shadow(color: .white, radius: 0, x: -width, y: 0)
            .shadow(color: .white, radius: 0, x: 0, y: width)
            .shadow(color: .white, radius: 0, x: 0, y: -width)
            .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 3)
    }
}

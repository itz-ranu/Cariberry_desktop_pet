import AppKit
import SwiftUI

/// Everything drawn inside the floating window: pet, bowl, particles, speech bubble.
struct SceneView: View {
    /// The window is stacked from three layers so she can be a ready-made image in the middle: what sits behind
    /// her (room decor), her (see `PetSpriteView`), and what sits in front (bowl, particles, speech bubble).
    /// `.all` draws everything live in one view, which is how the panel and the tests still use it.
    enum Layer { case all, back, front }

    @ObservedObject var pet: Pet
    var layer: Layer = .all

    var body: some View {
        let scale = pet.scale
        ZStack(alignment: .topLeading) {
            Color.clear

            if layer != .front, !pet.decorOn.isEmpty {
                DecorLayer(items: pet.decorOn, scale: scale).allowsHitTesting(false)
                if let kind = Decor.allCases.first(where: { $0.isAmbient && pet.decorOn.contains($0.rawValue) }) {
                    AmbientLayer(kind: kind, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
                        .frame(width: Stage.size.width, height: Stage.size.height)
                        .allowsHitTesting(false)
                }
            }

            if layer == .all {
                AnimatedPet(pet: pet, scale: scale)
                    .stickerOutline(max(1.4, scale * 3.6))
                    .offset(x: Stage.dogOrigin.x, y: Stage.dogOrigin.y)
            }

            if layer != .back, pet.bowl > 0 {
                FoodView(species: pet.species, fullness: pet.bowl)
                    .frame(width: Design.width, height: Design.height)
                    .scaleEffect(x: pet.facing < 0 ? -1 : 1, y: 1, anchor: .center)
                    .scaleEffect(scale, anchor: .topLeading)
                    .offset(x: Stage.dogOrigin.x, y: Stage.dogOrigin.y)
            }

            if layer != .back, !pet.particles.isEmpty {
                ParticleLayer(particles: pet.particles)
                    .frame(width: Stage.size.width, height: Stage.size.height)
                    .allowsHitTesting(false)
            }

            if layer != .back, let pos = pet.closeButtonAt {
                CloseButtonProp(pressed: pet.closeButtonPressed)
                    .frame(width: 30, height: 30)
                    .position(pos)
                    .transition(.scale(scale: 0.3, anchor: .center).combined(with: .opacity))
                    .allowsHitTesting(false)
            }

            if layer != .back { bubbleZone }
        }
        .frame(width: Stage.size.width, height: Stage.size.height)
        .animation(.spring(response: 0.24, dampingFraction: 0.58), value: pet.closeButtonAt)
    }

    private var bubbleZone: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            if let text = pet.bubbleText {
                SpeechBubble(text: text, accent: pet.emotion.accent)
                    .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                    .id(text)
            }
        }
        .frame(width: Stage.size.width, height: max(40, Stage.p(0, -18).y), alignment: .bottom)
        .animation(.spring(response: 0.32, dampingFraction: 0.62), value: pet.bubbleText)
        .allowsHitTesting(false)
    }
}

/// Just her, drawn live. The window shows ready-made frames of her; this takes over if one ever can't be made.
struct LivePet: View {
    @ObservedObject var pet: Pet
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            AnimatedPet(pet: pet, scale: pet.scale)
                .stickerOutline(max(1.4, pet.scale * 3.6))
                .offset(x: Stage.dogOrigin.x, y: Stage.dogOrigin.y)
        }
        .frame(width: Stage.size.width, height: Stage.size.height)
        .allowsHitTesting(false)
    }
}

/// Drives the pet's animation clock inside SwiftUI, so a wagging tail redraws only
/// this canvas instead of invalidating the whole window every frame. The pose is read
/// from the pet on every tick (not captured once), because its eased blends change
/// continuously without ever publishing.
struct AnimatedPet: View {
    let pet: Pet
    var scale: CGFloat = 1
    @ObservedObject private var clock: FrameClock

    init(pet: Pet, scale: CGFloat = 1) {
        self.pet = pet
        self.scale = scale
        _clock = ObservedObject(wrappedValue: pet.clock)
    }

    var body: some View {
        // reading the clock is what ties this canvas (and only this canvas) to each frame
        let _ = clock.frame
        CritterView(species: pet.species, coat: pet.coatIndex, pose: pet.pose, scale: scale)
    }
}

struct SpeechBubble: View {
    var text: String
    var accent: Color

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(UI.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
                .frame(maxWidth: 224)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(LinearGradient(colors: [.white, UI.bg], startPoint: .top, endPoint: .bottom))
                        .shadow(color: accent.opacity(0.45), radius: 9, y: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(accent, lineWidth: 2.4)
                )
            Triangle()
                .fill(UI.bg)
                .overlay(Triangle().stroke(accent, lineWidth: 2.4))
                .frame(width: 16, height: 10)
                .offset(x: 6, y: -1.5)
        }
        .padding(.horizontal, 16)
    }
}

struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// The big red "✕" she presses when she closes a Reels tab herself. Decorative: the real close
/// happens through the browser's own scripting. A ring pulses around it until she taps,
/// then ripples outward.
struct CloseButtonProp: View {
    var pressed: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white, lineWidth: 2.5)
                .scaleEffect(pressed ? 2.3 : 1.12)
                .opacity(pressed ? 0 : 0.9)
            Circle()
                .fill(RadialGradient(
                    colors: [Color(red: 1.0, green: 0.52, blue: 0.56), Color(red: 0.90, green: 0.22, blue: 0.34)],
                    center: UnitPoint(x: 0.35, y: 0.3), startRadius: 1, endRadius: 22))
                .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 2))
                .shadow(color: Color(red: 0.9, green: 0.2, blue: 0.3).opacity(0.5), radius: 5, y: 2)
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(.white)
        }
        .scaleEffect(pressed ? 0.76 : 1)
        .animation(.spring(response: 0.18, dampingFraction: 0.45), value: pressed)
        .animation(.easeOut(duration: 0.45), value: pressed)
    }
}

struct ParticleLayer: View {
    var particles: [Particle]

    var body: some View {
        Canvas { ctx, _ in
            for p in particles {
                let fade = min(1, p.life / max(0.001, p.maxLife) * 1.6)
                var c = ctx
                c.opacity = fade
                c.translateBy(x: p.pos.x, y: p.pos.y)
                c.rotate(by: .radians(p.rot))
                switch p.kind {
                case .heart:
                    c.fill(heartPath(center: .zero, size: p.size), with: .color(Fur.heart))
                    c.fill(ovalPath(-p.size * 0.16, -p.size * 0.16, p.size * 0.18, p.size * 0.14),
                           with: .color(.white.opacity(0.8)))
                case .crumb:
                    c.fill(ovalPath(0, 0, p.size, p.size * 0.85),
                           with: .color(Color(red: 0.55, green: 0.34, blue: 0.19)))
                case .anger:
                    // drawn rather than the 💢 emoji, whose hard red was the one
                    // thing on screen still shouting over the pastels
                    let r = p.size * 0.5
                    for a in stride(from: 0.0, to: .pi * 2, by: .pi / 2) {
                        var spike = Path()
                        spike.move(to: CGPoint(x: cos(a) * r * 0.35, y: sin(a) * r * 0.35))
                        spike.addLine(to: CGPoint(x: cos(a) * r, y: sin(a) * r))
                        c.stroke(spike, with: .color(Fur.alertAccent.opacity(0.85)),
                                 style: StrokeStyle(lineWidth: p.size * 0.16, lineCap: .round))
                    }
                case .zzz:
                    // a soft lilac "z" instead of the bright blue 💤
                    c.draw(Text("z")
                            .font(.system(size: p.size * 1.15, weight: .heavy, design: .rounded))
                            .foregroundStyle(UI.lilac), at: .zero)
                case .confetti:
                    // paper confetti in the pet's own pastel palette, tumbling as it falls
                    let palette: [Color] = [UI.blush, UI.lilac, UI.butter, UI.sage, UI.sky, UI.peach]
                    let col = palette[abs(p.id.hashValue) % palette.count]
                    c.scaleBy(x: 1, y: 0.4 + 0.6 * abs(cos(p.rot * 1.3)))
                    c.fill(Path(roundedRect: CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / 2), cornerRadius: 1.5),
                           with: .color(col))
                case .bubble:
                    c.stroke(ovalPath(0, 0, p.size, p.size), with: .color(Dish.shade.opacity(0.6)), lineWidth: 1.2)
                    c.fill(ovalPath(0, 0, p.size, p.size), with: .color(.white.opacity(0.28)))
                    c.fill(ovalPath(-p.size * 0.22, -p.size * 0.22, p.size * 0.26, p.size * 0.2),
                           with: .color(.white.opacity(0.85)))
                default:
                    c.draw(Text(glyph(p.kind)).font(.system(size: p.size)), at: .zero)
                }
            }
        }
    }

    private func glyph(_ k: Particle.Kind) -> String {
        switch k {
        case .zzz:     return "💤"
        case .sparkle: return "✨"
        case .anger:   return "💢"
        case .star:    return "⭐️"
        case .note:    return "🎵"
        case .sweat:   return "💦"
        default:       return "•"
        }
    }
}


/// The little objects bought in the Sanctuary, drawn beside her. They're drawn once (not
/// every frame), and move with her because they live inside her window.
struct DecorLayer: View {
    var items: Set<String>
    var scale: CGFloat

    var body: some View {
        Canvas { ctx, size in
            var c = ctx
            let o = Stage.dogOrigin
            c.translateBy(x: o.x, y: o.y + Design.lift * scale)
            c.scaleBy(x: scale, y: scale)
            let ground = Double(Design.ground)
            if items.contains(Decor.fairyLights.rawValue) { drawLights(c, ground: ground) }
            if items.contains(Decor.plant.rawValue) { drawPlant(c, x: -34, ground: ground) }
            if items.contains(Decor.books.rawValue) { drawBooks(c, x: -80, ground: ground) }
            if items.contains(Decor.teddy.rawValue) { drawTeddy(c, x: 214, ground: ground) }
            if items.contains(Decor.lamp.rawValue) { drawLamp(c, x: 252, ground: ground) }
            if items.contains(Decor.duck.rawValue) { drawDuck(c, x: 190, ground: ground) }
            if items.contains(Decor.bobaCup.rawValue) { drawBoba(c, x: -52, ground: ground) }
            if items.contains(Decor.cocoa.rawValue) { drawCocoa(c, x: 232, ground: ground) }
        }
        .frame(width: Stage.size.width, height: Stage.size.height)
    }

    private func drawDuck(_ c: GraphicsContext, x: Double, ground: Double) {
        let yellow = Color(red: 1.0, green: 0.88, blue: 0.40), shade = Color(red: 0.96, green: 0.74, blue: 0.28)
        c.fill(ovalPath(x, ground - 7, 26, 15), with: .color(shade))
        c.fill(ovalPath(x, ground - 8, 25, 14), with: .color(yellow))
        c.fill(ovalPath(x + 7, ground - 18, 15, 14), with: .color(yellow))
        c.fill(ovalPath(x + 15, ground - 16, 8, 4.5), with: .color(Color(red: 1.0, green: 0.62, blue: 0.36)))
        c.fill(ovalPath(x + 8, ground - 20, 2.6, 2.8), with: .color(Fur.ink))
        c.fill(ovalPath(x - 3, ground - 9, 11, 7), with: .color(shade.opacity(0.6)))
        c.fill(ovalPath(x - 6, ground - 12, 5, 2.4), with: .color(.white.opacity(0.7)))
    }

    private func drawBoba(_ c: GraphicsContext, x: Double, ground: Double) {
        var cup = Path()
        cup.move(to: CGPoint(x: x - 10, y: ground - 30)); cup.addLine(to: CGPoint(x: x + 10, y: ground - 30))
        cup.addLine(to: CGPoint(x: x + 7.5, y: ground)); cup.addLine(to: CGPoint(x: x - 7.5, y: ground)); cup.closeSubpath()
        c.fill(cup, with: .linearGradient(Gradient(colors: [Color(red: 0.98, green: 0.86, blue: 0.80), Color(red: 0.88, green: 0.68, blue: 0.62)]),
                                         startPoint: CGPoint(x: x, y: ground - 30), endPoint: CGPoint(x: x, y: ground)))
        c.fill(Path(roundedRect: CGRect(x: x - 11, y: ground - 33, width: 22, height: 4), cornerRadius: 2), with: .color(.white.opacity(0.9)))
        c.stroke(Path(CGRect(x: x + 1, y: ground - 46, width: 2.4, height: 14)), with: .color(Color(red: 0.98, green: 0.58, blue: 0.72)), lineWidth: 2.4)
        for (dx, dy) in [(-4.0, -4.0), (0.0, -2.0), (4.0, -4.5), (-1.0, -7.0), (3.0, -8.0)] {
            c.fill(ovalPath(x + dx, ground + dy, 4.2, 4.2), with: .color(Color(red: 0.34, green: 0.22, blue: 0.24)))
        }
        c.fill(heartPath(center: CGPoint(x: x, y: ground - 19), size: 6), with: .color(.white.opacity(0.85)))
    }

    private func drawCocoa(_ c: GraphicsContext, x: Double, ground: Double) {
        let mug = Path(roundedRect: CGRect(x: x - 11, y: ground - 20, width: 22, height: 20), cornerRadius: 6)
        c.stroke(Path(ellipseIn: CGRect(x: x + 7, y: ground - 16, width: 11, height: 11)), with: .color(Color(red: 0.86, green: 0.58, blue: 0.66)), lineWidth: 3)
        c.fill(mug, with: .linearGradient(Gradient(colors: [Color(red: 1.0, green: 0.78, blue: 0.84), Color(red: 0.94, green: 0.60, blue: 0.70)]),
                                         startPoint: CGPoint(x: x, y: ground - 20), endPoint: CGPoint(x: x, y: ground)))
        c.fill(ovalPath(x, ground - 19, 19, 5), with: .color(Color(red: 0.46, green: 0.28, blue: 0.24)))
        c.fill(ovalPath(x - 3, ground - 20, 6, 2.6), with: .color(.white.opacity(0.9)))      // a marshmallow
        c.fill(ovalPath(x + 3, ground - 19.5, 5, 2.4), with: .color(.white.opacity(0.9)))
        c.fill(heartPath(center: CGPoint(x: x - 1, y: ground - 9), size: 6), with: .color(.white.opacity(0.85)))
        for (i, dx) in [-3.0, 3.0].enumerated() {      // steam
            var s = Path()
            s.move(to: CGPoint(x: x + dx, y: ground - 24))
            s.addQuadCurve(to: CGPoint(x: x + dx, y: ground - 38), control: CGPoint(x: x + dx + (i == 0 ? 5 : -5), y: ground - 31))
            c.stroke(s, with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        }
    }

    private func drawPlant(_ c: GraphicsContext, x: Double, ground: Double) {
        for (dx, rot, h) in [(-5.0, -28.0, 26.0), (0.0, 0.0, 32.0), (5.0, 28.0, 26.0)] {
            var l = c
            l.translateBy(x: x + dx, y: ground - 16)
            l.rotate(by: .degrees(rot))
            let leaf = ovalPath(0, -h / 2, 11, h)
            l.fill(leaf, with: .linearGradient(Gradient(colors: [Color(red: 0.62, green: 0.84, blue: 0.56), Color(red: 0.40, green: 0.66, blue: 0.44)]),
                                              startPoint: CGPoint(x: 0, y: -h), endPoint: .zero))
            l.stroke(leaf, with: .color(Color(red: 0.34, green: 0.56, blue: 0.38).opacity(0.6)), lineWidth: 1)
        }
        var pot = Path()
        pot.move(to: CGPoint(x: x - 12, y: ground - 17)); pot.addLine(to: CGPoint(x: x + 12, y: ground - 17))
        pot.addLine(to: CGPoint(x: x + 9, y: ground + 2)); pot.addLine(to: CGPoint(x: x - 9, y: ground + 2)); pot.closeSubpath()
        c.fill(pot, with: .linearGradient(Gradient(colors: [Color(red: 1.0, green: 0.78, blue: 0.68), Color(red: 0.92, green: 0.58, blue: 0.5)]),
                                         startPoint: CGPoint(x: x, y: ground - 17), endPoint: CGPoint(x: x, y: ground + 2)))
        c.fill(Path(roundedRect: CGRect(x: x - 13, y: ground - 19, width: 26, height: 5), cornerRadius: 2.5), with: .color(Color(red: 0.96, green: 0.66, blue: 0.58)))
        c.fill(heartPath(center: CGPoint(x: x, y: ground - 7), size: 7), with: .color(.white.opacity(0.8)))
    }

    private func drawBooks(_ c: GraphicsContext, x: Double, ground: Double) {
        let colours: [(Color, Double, Double)] = [
            (Color(red: 0.98, green: 0.70, blue: 0.80), 30, 9), (Color(red: 0.72, green: 0.80, blue: 0.98), 26, 8), (Color(red: 0.98, green: 0.90, blue: 0.62), 28, 8),
        ]
        var y = ground + 1
        for (i, b) in colours.enumerated() {
            y -= b.2
            let r = CGRect(x: x - b.1 / 2 + (i == 1 ? 2 : -1), y: y, width: b.1, height: b.2)
            c.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(b.0))
            c.stroke(Path(roundedRect: r, cornerRadius: 2), with: .color(.black.opacity(0.15)), lineWidth: 1)
            c.fill(Path(CGRect(x: r.minX + 3, y: r.minY + 2, width: 4, height: b.2 - 4)), with: .color(.white.opacity(0.55)))
        }
    }

    private func drawTeddy(_ c: GraphicsContext, x: Double, ground: Double) {
        let fur = Color(red: 0.86, green: 0.68, blue: 0.52), shade = Color(red: 0.72, green: 0.54, blue: 0.40)
        c.fill(ovalPath(x, ground - 9, 24, 22), with: .color(fur))
        c.fill(ovalPath(x, ground - 8, 13, 13), with: .color(Color(red: 0.97, green: 0.88, blue: 0.78)))
        for dx in [-8.0, 8.0] { c.fill(ovalPath(x + dx, ground - 1, 10, 9), with: .color(shade)) }
        c.fill(ovalPath(x, ground - 28, 22, 20), with: .color(fur))
        for dx in [-9.0, 9.0] { c.fill(ovalPath(x + dx, ground - 37, 9, 9), with: .color(fur)); c.fill(ovalPath(x + dx, ground - 37, 4.5, 4.5), with: .color(Color(red: 0.96, green: 0.74, blue: 0.76))) }
        c.fill(ovalPath(x - 4.5, ground - 29, 3, 3.6), with: .color(Fur.ink)); c.fill(ovalPath(x + 4.5, ground - 29, 3, 3.6), with: .color(Fur.ink))
        c.fill(ovalPath(x, ground - 24, 7, 5), with: .color(Color(red: 0.97, green: 0.88, blue: 0.78)))
        c.fill(ovalPath(x, ground - 25, 3, 2.4), with: .color(Fur.ink))
        // a little pink bow
        for sd in [-1.0, 1.0] { c.fill(ovalPath(x + sd * 5, ground - 18, 7, 5), with: .color(Color(red: 0.98, green: 0.58, blue: 0.72))) }
        c.fill(ovalPath(x, ground - 18, 3.5, 3.5), with: .color(Color(red: 0.88, green: 0.42, blue: 0.58)))
    }

    private func drawLamp(_ c: GraphicsContext, x: Double, ground: Double) {
        // a warm pool of light first, so it sits behind the lamp
        c.fill(ovalPath(x, ground - 28, 80, 70), with: .radialGradient(
            Gradient(colors: [Color(red: 1.0, green: 0.90, blue: 0.6).opacity(0.45), Color(red: 1.0, green: 0.90, blue: 0.6).opacity(0)]),
            center: CGPoint(x: x, y: ground - 30), startRadius: 2, endRadius: 40))
        c.fill(ovalPath(x, ground - 1, 22, 7), with: .color(Color(red: 0.96, green: 0.76, blue: 0.82)))
        c.fill(Path(CGRect(x: x - 2, y: ground - 34, width: 4, height: 33)), with: .color(Color(red: 0.88, green: 0.66, blue: 0.74)))
        var shade = Path()
        shade.move(to: CGPoint(x: x - 9, y: ground - 32)); shade.addLine(to: CGPoint(x: x + 9, y: ground - 32))
        shade.addLine(to: CGPoint(x: x + 15, y: ground - 50)); shade.addLine(to: CGPoint(x: x - 15, y: ground - 50)); shade.closeSubpath()
        c.fill(shade, with: .linearGradient(Gradient(colors: [Color(red: 1.0, green: 0.96, blue: 0.82), Color(red: 1.0, green: 0.82, blue: 0.62)]),
                                           startPoint: CGPoint(x: x, y: ground - 50), endPoint: CGPoint(x: x, y: ground - 32)))
        c.stroke(shade, with: .color(Color(red: 0.86, green: 0.62, blue: 0.5).opacity(0.7)), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
    }

    private func drawLights(_ c: GraphicsContext, ground: Double) {
        var string = Path()
        string.move(to: CGPoint(x: -90, y: 14))
        string.addQuadCurve(to: CGPoint(x: 290, y: 14), control: CGPoint(x: 100, y: 52))
        c.stroke(string, with: .color(Color(red: 0.62, green: 0.52, blue: 0.5).opacity(0.7)), lineWidth: 1.4)
        let cols: [Color] = [Color(red: 1.0, green: 0.78, blue: 0.84), Color(red: 1.0, green: 0.94, blue: 0.64), Color(red: 0.76, green: 0.92, blue: 1.0), Color(red: 0.84, green: 0.80, blue: 1.0)]
        for i in 0...15 {
            let t = Double(i) / 15
            let mt = 1 - t
            let px = mt * mt * -90 + 2 * mt * t * 100 + t * t * 290
            let py = mt * mt * 14 + 2 * mt * t * 52 + t * t * 14
            let col = cols[i % cols.count]
            c.fill(ovalPath(px, py + 5, 15, 15), with: .color(col.opacity(0.28)))
            c.fill(ovalPath(px, py + 5, 7, 8), with: .color(col))
            c.fill(ovalPath(px - 1.5, py + 3, 2.4, 2.4), with: .color(.white.opacity(0.8)))
        }
    }
}


/// Petals, leaves, rain or stars drifting through her corner. It only runs while one is switched
/// on, at 15 frames a second, and holds still for people who've asked for reduced motion.
struct AmbientLayer: View {
    var kind: Decor
    var reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: reduceMotion)) { ctx in
            let t = reduceMotion ? 3 : ctx.date.timeIntervalSinceReferenceDate
            Canvas { c, size in
                for i in 0..<12 {
                    let f = Double(i)
                    let seed = (f * 0.6180339).truncatingRemainder(dividingBy: 1)
                    let speed = (kind == .rainDrops ? 120 : (kind == .starSparkles ? 0 : 22)) + seed * 14
                    let travel = size.height + 30
                    var y = (t * speed + seed * travel * 3).truncatingRemainder(dividingBy: travel) - 15
                    var x = seed * (size.width + 40) - 20
                    switch kind {
                    case .sakura, .leaves: x += sin(t * 0.9 + f * 1.7) * 16
                    case .starSparkles: y = (seed * 7.3).truncatingRemainder(dividingBy: 1) * size.height * 0.8
                    default: break
                    }
                    var g = c
                    g.translateBy(x: x, y: y)
                    switch kind {
                    case .sakura:
                        g.rotate(by: .radians(t * 0.8 + f))
                        g.fill(ovalPath(0, 0, 9, 6), with: .color(Color(red: 1.0, green: 0.76, blue: 0.84).opacity(0.9)))
                        g.fill(ovalPath(-1, -1, 4, 2.5), with: .color(.white.opacity(0.6)))
                    case .leaves:
                        g.rotate(by: .radians(t * 0.7 + f * 2))
                        let cols = [Color(red: 0.96, green: 0.62, blue: 0.30), Color(red: 0.88, green: 0.42, blue: 0.26), Color(red: 0.98, green: 0.78, blue: 0.36)]
                        g.fill(ovalPath(0, 0, 11, 6), with: .color(cols[i % 3].opacity(0.92)))
                        g.stroke(Path { $0.move(to: CGPoint(x: -5, y: 0)); $0.addLine(to: CGPoint(x: 5, y: 0)) }, with: .color(.white.opacity(0.4)), lineWidth: 0.8)
                    case .rainDrops:
                        g.stroke(Path { $0.move(to: .zero); $0.addLine(to: CGPoint(x: -2, y: 9)) },
                                 with: .color(Color(red: 0.62, green: 0.78, blue: 1.0).opacity(0.75)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    case .starSparkles:
                        let twinkle = 0.45 + 0.55 * abs(sin(t * 1.6 + f * 2.1))
                        var star = Path()
                        for k in 0..<8 {
                            let r = k % 2 == 0 ? 6.0 : 1.8, a = Double(k) * .pi / 4
                            let pt = CGPoint(x: cos(a) * r, y: sin(a) * r)
                            if k == 0 { star.move(to: pt) } else { star.addLine(to: pt) }
                        }
                        star.closeSubpath()
                        g.fill(star, with: .color(Color(red: 1.0, green: 0.94, blue: 0.62).opacity(twinkle)))
                    default: break
                    }
                }
            }
        }
    }
}

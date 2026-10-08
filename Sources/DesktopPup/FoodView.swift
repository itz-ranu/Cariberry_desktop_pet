import SwiftUI

/// What she's eating depends on what she is: kibble for a puppy, a fish for a kitten,
/// a carrot for a bunny. Drawn in the same space as the character so it lines up with
/// her mouth when her head dips down to eat.
struct FoodView: View {
    var species: Species
    var fullness: Double   // 1 = fresh, 0 = finished

    var body: some View {
        Canvas { ctx, _ in
            var c = ctx
            c.translateBy(x: 0, y: Design.lift)
            let cx = 150.0, cy = Double(Design.ground) - 4
            if species == .cat {
                drawSaucer(c, cx: cx, cy: cy + 2)
            } else {
                drawBowl(c, cx: cx, cy: cy)
            }
        }
        .frame(width: Design.width, height: Design.height)
    }

    // MARK: Bowl

    private func drawBowl(_ ctx: GraphicsContext, cx: Double, cy: Double) {
        let fill = max(0.05, fullness)
        // contents sit behind the front lip of the bowl
        switch species {
        case .dog:
            let bits: [(Double, Double, Double)] = [(-11, -3, 6.5), (0, -7, 7), (11, -4, 6), (-6, -9, 5.5), (7, -10, 5), (-1, -12, 5)]
            for (i, b) in bits.prefix(max(1, Int(fill * Double(bits.count)))).enumerated() {
                let shade = i % 2 == 0 ? Color(red: 0.72, green: 0.55, blue: 0.36) : Color(red: 0.82, green: 0.65, blue: 0.44)
                ctx.fill(ovalPath(cx + b.0, cy - 8 + b.1 * fill, b.2, b.2 * 0.82), with: .color(shade))
            }
            if fullness > 0.7 { drawBone(ctx, cx: cx, cy: cy - 15) }
        case .bunny:
            for (dx, rot) in [(-8.0, -24.0), (4.0, -6.0), (14.0, 14.0)].prefix(max(1, Int((fill * 3).rounded(.up)))) {
                var c = ctx
                c.translateBy(x: cx + dx, y: cy - 4)
                c.rotate(by: .degrees(rot))
                var carrot = Path()
                carrot.move(to: CGPoint(x: -5, y: -4))
                carrot.addLine(to: CGPoint(x: 5, y: -4))
                carrot.addQuadCurve(to: CGPoint(x: 0, y: 17), control: CGPoint(x: 4, y: 8))
                carrot.addQuadCurve(to: CGPoint(x: -5, y: -4), control: CGPoint(x: -4, y: 8))
                c.fill(carrot, with: .linearGradient(
                    Gradient(colors: [Color(red: 1.0, green: 0.66, blue: 0.34), Color(red: 0.95, green: 0.50, blue: 0.24)]),
                    startPoint: CGPoint(x: 0, y: -4), endPoint: CGPoint(x: 0, y: 17)))
                for y in [2.0, 8.0] {
                    var line = Path(); line.move(to: CGPoint(x: -2.5, y: y)); line.addLine(to: CGPoint(x: 1, y: y))
                    c.stroke(line, with: .color(.white.opacity(0.4)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                }
                for a in [-26.0, 0.0, 26.0] {
                    var leaf = c
                    leaf.translateBy(x: 0, y: -4)
                    leaf.rotate(by: .degrees(a))
                    leaf.fill(ovalPath(0, -6, 4.5, 11), with: .color(Color(red: 0.55, green: 0.78, blue: 0.48)))
                }
            }
        case .fox:
            let berries: [(Double, Double)] = [(-11, -3), (-2, -6), (9, -3), (-6, -10), (4, -11)]
            for b in berries.prefix(max(1, Int((fill * Double(berries.count)).rounded(.up)))) {
                ctx.fill(ovalPath(cx + b.0, cy - 6 + b.1, 10, 10), with: .color(Color(red: 0.88, green: 0.28, blue: 0.40)))
                ctx.fill(ovalPath(cx + b.0 - 2, cy - 8 + b.1, 3.4, 2.6), with: .color(.white.opacity(0.7)))
            }
        case .hamster:
            let seeds: [(Double, Double, Double)] = [(-10, -2, -20), (0, -4, 15), (10, -2, 40), (-5, -8, 60), (5, -9, -30), (-12, -7, 10)]
            for s in seeds.prefix(max(1, Int((fill * Double(seeds.count)).rounded(.up)))) {
                var c = ctx
                c.translateBy(x: cx + s.0, y: cy - 6 + s.1)
                c.rotate(by: .degrees(s.2))
                c.fill(ovalPath(0, 0, 11, 6.5), with: .color(Color(red: 0.36, green: 0.31, blue: 0.30)))
                c.fill(ovalPath(0, 0, 3, 5.5), with: .color(.white.opacity(0.5)))
            }
        case .panda:
            for (dx, h, lean) in [(-8.0, 28.0, -10.0), (2.0, 34.0, 2.0), (12.0, 26.0, 12.0)] {
                var c = ctx
                c.translateBy(x: cx + dx, y: cy - 3)
                c.rotate(by: .degrees(lean))
                let stalk = capsulePath(0, -h / 2, 6, h)
                c.fill(stalk, with: .linearGradient(
                    Gradient(colors: [Color(red: 0.62, green: 0.82, blue: 0.50), Color(red: 0.45, green: 0.68, blue: 0.40)]),
                    startPoint: CGPoint(x: -3, y: 0), endPoint: CGPoint(x: 3, y: 0)))
                for y in stride(from: -8.0, to: -h, by: -9.0) {
                    c.fill(capsulePath(0, y, 7.5, 2.2), with: .color(Color(red: 0.36, green: 0.55, blue: 0.34)))
                }
            }
        case .axolotl:
            for (dx, dy, rot) in [(-9.0, -3.0, -20.0), (3.0, -6.0, 10.0), (12.0, -3.0, 35.0)].prefix(max(1, Int((fill * 3).rounded(.up)))) {
                var c = ctx
                c.translateBy(x: cx + dx, y: cy - 4 + dy)
                c.rotate(by: .degrees(rot))
                var shrimp = Path()
                shrimp.addArc(center: .zero, radius: 7, startAngle: .degrees(200), endAngle: .degrees(20), clockwise: false)
                c.stroke(shrimp, with: .color(Color(red: 1.0, green: 0.62, blue: 0.62)), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                c.fill(ovalPath(6, 1, 2.2, 2.2), with: .color(Fur.ink))
            }
        case .capybara:
            var slice = Path()
            slice.move(to: CGPoint(x: cx - 15, y: cy - 4))
            slice.addLine(to: CGPoint(x: cx + 15, y: cy - 4))
            slice.addQuadCurve(to: CGPoint(x: cx - 15, y: cy - 4), control: CGPoint(x: cx, y: cy - 4 - 30 * max(0.3, fill)))
            ctx.fill(slice, with: .color(Color(red: 1.0, green: 0.46, blue: 0.52)))
            for (dx, dy) in [(-6.0, -8.0), (3.0, -12.0), (8.0, -7.0)] {
                ctx.fill(ovalPath(cx + dx, cy + dy, 2.2, 3.4), with: .color(Fur.ink.opacity(0.8)))
            }
        case .cat: break
        }

        var bowl = Path()
        bowl.move(to: CGPoint(x: cx - 24, y: cy))
        bowl.addLine(to: CGPoint(x: cx + 24, y: cy))
        bowl.addQuadCurve(to: CGPoint(x: cx - 24, y: cy), control: CGPoint(x: cx, y: cy + 28))
        ctx.fill(bowl, with: .linearGradient(Gradient(colors: [Dish.mid, Dish.shade]),
                                            startPoint: CGPoint(x: cx - 24, y: cy), endPoint: CGPoint(x: cx + 24, y: cy + 22)))
        ctx.fill(capsulePath(cx, cy - 1, 52, 9), with: .color(Dish.light))
        ctx.fill(heartPath(center: CGPoint(x: cx, y: cy + 11), size: 11), with: .color(.white.opacity(0.85)))
    }

    private func drawBone(_ ctx: GraphicsContext, cx: Double, cy: Double) {
        var bone = Path()
        bone.move(to: CGPoint(x: cx - 9, y: cy - 2))
        bone.addLine(to: CGPoint(x: cx + 9, y: cy - 2))
        ctx.stroke(bone, with: .color(Dish.light), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        for end in [cx - 9.0, cx + 9.0] {
            ctx.fill(ovalPath(end, cy - 5, 5, 5), with: .color(Dish.light))
            ctx.fill(ovalPath(end, cy + 1, 5, 5), with: .color(Dish.light))
        }
    }

    // MARK: Saucer

    /// A shallow saucer with a little fish: cats don't eat from a deep bowl.
    private func drawSaucer(_ ctx: GraphicsContext, cx: Double, cy: Double) {
        var saucer = Path()
        saucer.move(to: CGPoint(x: cx - 26, y: cy))
        saucer.addLine(to: CGPoint(x: cx + 26, y: cy))
        saucer.addQuadCurve(to: CGPoint(x: cx - 26, y: cy), control: CGPoint(x: cx, y: cy + 16))
        ctx.fill(saucer, with: .linearGradient(Gradient(colors: [Dish.mid, Dish.shade]),
                                              startPoint: CGPoint(x: cx - 26, y: cy), endPoint: CGPoint(x: cx + 26, y: cy + 12)))
        ctx.fill(capsulePath(cx, cy - 1, 56, 7), with: .color(Dish.light))

        guard fullness > 0.04 else { return }
        let scale = 0.5 + 0.5 * fullness
        var f = ctx
        f.opacity = min(1, fullness * 1.6)
        f.translateBy(x: cx, y: cy - 8)
        f.scaleBy(x: scale, y: scale)
        f.fill(fishPath(cx: 0, cy: 0, w: 34, h: 16), with: .color(Color(red: 0.62, green: 0.73, blue: 0.88)))
        f.fill(ovalPath(6, -2, 3, 3), with: .color(Fur.ink.opacity(0.7)))
    }
}

/// A simple side-on fish silhouette for the cat's saucer.
func fishPath(cx: Double, cy: Double, w: Double, h: Double) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: cx - w * 0.5, y: cy))
    p.addQuadCurve(to: CGPoint(x: cx + w * 0.32, y: cy - h * 0.5), control: CGPoint(x: cx - w * 0.15, y: cy - h * 0.62))
    p.addQuadCurve(to: CGPoint(x: cx + w * 0.32, y: cy + h * 0.5), control: CGPoint(x: cx + w * 0.5, y: cy))
    p.addQuadCurve(to: CGPoint(x: cx - w * 0.5, y: cy), control: CGPoint(x: cx - w * 0.15, y: cy + h * 0.62))
    p.closeSubpath()
    p.move(to: CGPoint(x: cx - w * 0.46, y: cy))
    p.addLine(to: CGPoint(x: cx - w * 0.72, y: cy - h * 0.34))
    p.addLine(to: CGPoint(x: cx - w * 0.72, y: cy + h * 0.34))
    p.closeSubpath()
    return p
}

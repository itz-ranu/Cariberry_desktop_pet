import AppKit
import SwiftUI

// Her frames, drawn once and replayed.
//
// A frame of her costs a couple of milliseconds to draw (hundreds of gradient shapes), and a laptop does that
// work whether she is walking across the screen or just breathing. But what she does is a small, repeating set of
// poses, and her idle animation loops exactly (see `Loop`). So each distinct frame is drawn the first time it is
// needed, kept, and from then on put on screen by handing a ready-made image to a Core Animation layer, which
// costs almost nothing. The frames are identical to what live drawing would give: the pose is snapped to a grid
// first, and both the key and the drawing use the snapped pose.

// MARK: - Snapping a pose to a frame

struct SpriteKey: Hashable {
    var species: Species
    var coat: Int
    var scale: Int              // dogScale in hundredths
    var backing: Int            // 1 or 2: points to pixels
    var outfit: Outfit
    var emotion: Emotion
    var prop: Prop
    var flags: Int              // dangling, tapping, perched
    var collarTier: Int
    var steps: [Int]            // every continuous amount, snapped
}

extension Pose {
    /// The pose rounded to a grid fine enough to look continuous and coarse enough that frames repeat, with the key
    /// that names it. Amounts that do nothing right now (the stride while standing still) are zeroed, so the same
    /// picture always gets the same key.
    func snapped(species: Species, coat: Int, scale: CGFloat, backing: Int) -> (pose: Pose, key: SpriteKey) {
        var s = self
        var steps: [Int] = []
        func snap(_ v: inout Double, _ n: Double) {
            let i = Int((v * n).rounded())
            v = Double(i) / n
            steps.append(i)
        }
        let walking = walk > 0.01
        // blends to tenths: transitions (sitting down, turning round) then pass through the same few pictures
        // every time, so they can be kept too
        snap(&s.walk, 10); snap(&s.run, 10); snap(&s.facing, 10); snap(&s.squash, 10)
        snap(&s.sit, 10); snap(&s.sleep, 10); snap(&s.petting, 5); snap(&s.stretch, 10); snap(&s.sniff, 10)
        snap(&s.groom, 10); snap(&s.scratch, 10); snap(&s.dance, 10); snap(&s.wave, 10); snap(&s.bop, 5)
        var dx = Double(look.dx), dy = Double(look.dy)
        if walk > 0.5 { dx = s.facing >= 0 ? 0.5 : -0.5; dy = 0 }       // eyes front while she walks
        snap(&dx, 2); snap(&dy, 2)
        s.look = CGVector(dx: dx, dy: dy)

        // time. Walking: the small idle motions hold still (the stride is what you see). Resting (a pom-tailed
        // animal, which has no tail to wave): the pose is one still picture, and the three small things that
        // happen on a beat (blink, ear flick, tongue) are handed over as levels, so a whole resting animation is
        // a handful of frames instead of hundreds; her slow breathing is played by the layer itself. Anything
        // livelier follows the clock on a grid that divides the loop exactly.
        var ti = Int((phase / Loop.step).rounded()) % Loop.steps
        let mode = species.stillWhenResting ? timeMode(s) : .live
        if s.walk > 0.95 {
            ti = 0
        } else if case .free = mode {
            let t = Double(ti) * Loop.step
            func level(_ v: Double, _ n: Double) -> Double { (v * n).rounded() / n }
            var e = RestEvents()
            e.blink = level(Critter.blink(at: t, emotion: emotion), 2)
            e.flick = level(Critter.flick(at: t, sleep: s.sleep), 2)
            e.blep = level(Critter.blep(at: t, emotion: emotion, sleep: s.sleep, walk: s.walk), 2)
            s.events = e
            steps.append(Int(e.blink * 2)); steps.append(Int(e.flick * 2)); steps.append(Int(e.blep * 2))
            ti = 0
        } else if case .cycle(let length) = mode {
            // face-washing, scratching, a sniff, a wave and a dance repeat on a short beat, so the clock is
            // folded onto one beat and the same few pictures serve every time she does it
            let t = (Double(ti) * Loop.step).truncatingRemainder(dividingBy: length)
            ti = Int((t / Loop.step).rounded())
            s.events = RestEvents()
            steps.append(-1)
        } else if isCalm(s) && !Loop.eventActive(at: Double(ti) * Loop.step) {
            ti = ti / Loop.coarse * Loop.coarse
        }
        s.phase = Double(ti) * Loop.step
        steps.append(ti)
        // the stride in 24 steps while she walks properly, 8 while she is only starting or stopping (a third of a
        // second that nobody counts frames of)
        let gn = s.walk >= 0.95 ? 24 : 8
        let gi = walking ? Int((gait.truncatingRemainder(dividingBy: 2 * .pi) / (2 * .pi / Double(gn))).rounded()) % gn : 0
        s.gait = Double(gi) * (2 * .pi / Double(gn))
        steps.append(gi)
        if tapping { snap(&s.tapPhase, 20) } else { s.tapPhase = 0; steps.append(0) }
        if prop != .none { snap(&s.propAmt, 20) } else { s.propAmt = 0; steps.append(0) }

        let key = SpriteKey(species: species, coat: coat, scale: Int((scale * 100).rounded()), backing: backing,
                            outfit: outfit, emotion: emotion, prop: prop,
                            flags: (dangling ? 1 : 0) | (tapping ? 2 : 0) | (perched ? 4 : 0),
                            collarTier: collarTier, steps: steps)
        return (s, key)
    }
}

extension Pose {
    enum TimeMode { case free, cycle(Double), live }

    /// How the picture depends on the clock. `free`: only on the beat events (standing, sitting down, getting up,
    /// turning round, a stretch). `cycle`: on a short repeating beat (face-washing, scratching, a sniff, a wave, a
    /// dance). `live`: on the clock itself (hopping, being petted, anything on her that sways).
    func timeMode(_ s: Pose) -> TimeMode {
        guard s.squash == 0, s.petting == 0, s.bop == 0, !dangling, !tapping, prop == .none,
              outfit.aura == .none, outfit.body == .none, outfit.neck == .none else { return .live }
        switch emotion {
        case .excited, .playful, .blissful, .hyped, .love, .proud, .angry, .eating, .dizzy, .vibing, .alert: return .live
        default: break
        }
        if s.dance > 0 { return .cycle(Loop.period / 6) }
        if s.groom > 0 { return .cycle(Loop.period / 28) }
        if s.scratch > 0 { return .cycle(2 * .pi / 22) }
        if s.sniff > 0 { return .cycle(2 * .pi / 5) }
        if s.wave > 0 { return .cycle(2 * .pi / 11) }
        return .free
    }

    /// Resting: standing, sitting or asleep and settled, with nothing lively going on and nothing on her that sways.
    func isCalm(_ s: Pose) -> Bool {
        guard s.walk == 0, s.run == 0, s.squash == 0, s.stretch == 0, s.sniff == 0, s.groom == 0, s.scratch == 0,
              s.dance == 0, s.wave == 0, s.bop == 0, s.petting == 0, !dangling, !tapping, prop == .none,
              s.sit == s.sit.rounded(), s.sleep == s.sleep.rounded(),
              outfit.aura == .none, outfit.body == .none, outfit.neck == .none else { return false }
        switch emotion {
        case .excited, .playful, .blissful, .hyped, .love, .proud, .angry, .eating, .dizzy, .vibing, .alert: return false
        default: return true
        }
    }
}

// MARK: - Drawing one frame to an image

@MainActor
enum SpriteRenderer {
    /// Room around the art for her sticker outline's soft shadow.
    static let margin: CGFloat = 12

    static func render(species: Species, coat: Int, pose: Pose, scale: CGFloat, backing: CGFloat) -> CGImage? {
        let w = Design.width * scale, h = Design.height * scale
        let view = CritterView(species: species, coat: coat, pose: pose, scale: scale)
            .stickerOutline(max(1.4, scale * 3.6))
            .frame(width: w, height: h)
            .padding(margin)
        let renderer = ImageRenderer(content: view)
        renderer.scale = backing
        renderer.isOpaque = false
        return renderer.cgImage
    }

    /// Where the frame sits in the window (AppKit coordinates, origin bottom-left).
    static func rect() -> CGRect {
        let w = Design.width * Stage.dogScale + 2 * margin, h = Design.height * Stage.dogScale + 2 * margin
        let topDown = Stage.dogOrigin.y - margin
        return CGRect(x: Stage.dogOrigin.x - margin, y: Stage.size.height - topDown - h, width: w, height: h)
    }
}

// MARK: - Keeping them

/// Frames she has already been drawn in. Each distinct frame is drawn once, ever: it is written to a file in the
/// Caches folder and read back by memory-mapping it, so the next launch (and the next day) starts with everything
/// she has ever looked like, and the memory they take is the system's to reclaim, not the app's.
@MainActor
final class SpriteCache {
    static let shared = SpriteCache()

    private struct Entry { var image: CGImage; var used: UInt64 }
    private var items: [SpriteKey: Entry] = [:]
    private var tick: UInt64 = 0
    /// Images already wrapped for display (memory-mapped, so each costs address space, not memory).
    private let memoryLimit = 400
    private(set) var hits = 0, misses = 0, diskHits = 0

    private let dir: URL?
    private var onDisk: Set<String> = []
    private var diskBytes = 0
    private let diskBudget = 320 * 1024 * 1024

    init() {
        // The folder is named for this exact build, so a new version (whose art may have changed) never reads
        // frames drawn by an old one; old folders are removed.
        var name = "sprites"
        if let exe = Bundle.main.executableURL,
           let a = try? FileManager.default.attributesOfItem(atPath: exe.path),
           let size = a[.size] as? Int, let mtime = (a[.modificationDate] as? Date)?.timeIntervalSince1970 {
            name += "-\(size)-\(Int(mtime))"
        }
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("Cariberry", isDirectory: true)
        guard let root else { dir = nil; return }
        let mine = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: mine, withIntermediateDirectories: true)
        if let others = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            for o in others where o.lastPathComponent.hasPrefix("sprites") && o != mine { try? FileManager.default.removeItem(at: o) }
        }
        dir = mine
        if let files = try? FileManager.default.contentsOfDirectory(at: mine, includingPropertiesForKeys: [.fileSizeKey]) {
            for f in files where f.pathExtension == "spr" {
                onDisk.insert(f.deletingPathExtension().lastPathComponent)
                diskBytes += (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            }
        }
        trimDisk()
    }

    func image(for key: SpriteKey, render: () -> CGImage?) -> CGImage? {
        tick &+= 1
        if var e = items[key] {
            e.used = tick
            items[key] = e
            hits += 1
            return e.image
        }
        let name = key.fileName
        if onDisk.contains(name), let image = load(name) {
            diskHits += 1
            remember(key, image)
            return image
        }
        misses += 1
        guard let drawn = render() else { return nil }
        let image = save(drawn, as: name) ?? drawn
        remember(key, image)
        return image
    }

    private func remember(_ key: SpriteKey, _ image: CGImage) {
        items[key] = Entry(image: image, used: tick)
        if items.count > memoryLimit {
            for (k, _) in items.sorted(by: { $0.value.used < $1.value.used }).prefix(memoryLimit / 4) { items[k] = nil }
        }
    }

    // MARK: files

    private static let space = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

    /// 16 bytes (magic, width, height, bytes per row) then the pixels, BGRA, premultiplied.
    private func save(_ image: CGImage, as name: String) -> CGImage? {
        guard let dir else { return nil }
        let w = image.width, h = image.height, bpr = w * 4
        var data = Data(count: 16 + bpr * h)
        let ok: Bool = data.withUnsafeMutableBytes { raw in
            let p = raw.baseAddress!
            p.storeBytes(of: UInt32(0x53505231), as: UInt32.self)
            p.storeBytes(of: UInt32(w), toByteOffset: 4, as: UInt32.self)
            p.storeBytes(of: UInt32(h), toByteOffset: 8, as: UInt32.self)
            p.storeBytes(of: UInt32(bpr), toByteOffset: 12, as: UInt32.self)
            guard let ctx = CGContext(data: p + 16, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr,
                                      space: Self.space, bitmapInfo: Self.info) else { return false }
            ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        let url = dir.appendingPathComponent(name + ".spr")
        let tmp = dir.appendingPathComponent(name + ".tmp")
        do {
            try data.write(to: tmp)
            _ = try? FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: tmp, to: url)
        } catch { return nil }
        onDisk.insert(name)
        diskBytes += data.count
        if diskBytes > diskBudget { trimDisk() }
        return load(name)
    }

    /// Memory-maps a saved frame and wraps it as an image, without copying a byte.
    private func load(_ name: String) -> CGImage? {
        guard let dir else { return nil }
        let path = dir.appendingPathComponent(name + ".spr").path
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { onDisk.remove(name); return nil }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, st.st_size > 16 else { return nil }
        let size = Int(st.st_size)
        guard let map = mmap(nil, size, PROT_READ, MAP_SHARED, fd, 0), map != MAP_FAILED else { return nil }
        let header = map.assumingMemoryBound(to: UInt32.self)
        guard header[0] == 0x53505231 else { munmap(map, size); try? FileManager.default.removeItem(atPath: path); onDisk.remove(name); return nil }
        let w = Int(header[1]), h = Int(header[2]), bpr = Int(header[3])
        guard 16 + bpr * h <= size else { munmap(map, size); return nil }
        final class Box { let map: UnsafeMutableRawPointer; let size: Int; init(_ m: UnsafeMutableRawPointer, _ s: Int) { map = m; size = s }; deinit { munmap(map, size) } }
        let box = Box(map, size)
        guard let provider = CGDataProvider(dataInfo: Unmanaged.passRetained(box).toOpaque(), data: map + 16, size: bpr * h,
                                            releaseData: { info, _, _ in if let info { Unmanaged<Box>.fromOpaque(info).release() } }) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bpr, space: Self.space,
                       bitmapInfo: CGBitmapInfo(rawValue: Self.info), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Keeps the folder under budget by dropping the oldest frames.
    private func trimDisk() {
        guard let dir, diskBytes > diskBudget,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { return }
        let sorted = files.filter { $0.pathExtension == "spr" }.sorted {
            ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
        for f in sorted {
            if diskBytes <= diskBudget * 3 / 4 { break }
            let size = (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            try? FileManager.default.removeItem(at: f)
            onDisk.remove(f.deletingPathExtension().lastPathComponent)
            diskBytes -= size
        }
    }

    func flush() { items.removeAll() }
    var count: Int { items.count }
    var megabytes: Double { Double(diskBytes) / 1_048_576 }
}

extension SpriteKey {
    /// A name for this frame that is the same in every launch (Swift's own hashing is not), so a frame drawn
    /// yesterday is found today.
    var fileName: String {
        var h: UInt64 = 0xcbf29ce484222325
        func mix(_ v: UInt64) { h = (h ^ v) &* 0x100000001b3 }
        func mix(_ s: String) { for b in s.utf8 { mix(UInt64(b)) }; mix(0xff) }
        mix(species.rawValue); mix(UInt64(truncatingIfNeeded: coat)); mix(UInt64(truncatingIfNeeded: scale)); mix(UInt64(truncatingIfNeeded: backing))
        for slot in AccessorySlot.allCases { mix(outfit[slot].rawValue) }
        mix(emotion.rawValue); mix("\(prop)"); mix(UInt64(truncatingIfNeeded: flags)); mix(UInt64(truncatingIfNeeded: collarTier))
        for v in steps { mix(UInt64(bitPattern: Int64(v))) }
        return String(h, radix: 16)
    }
}

// MARK: - Showing one

/// A plain layer-backed view that shows one ready-made image. Swapping it is nearly free; she is never redrawn
/// by SwiftUI while resting or walking. While she rests, the layer itself plays her slow breathing and sway:
/// Core Animation runs that on the render server, so it costs the app nothing.
final class PetSpriteView: NSView {
    private let motion = CALayer()       // sways about her feet
    private let imageLayer = CALayer()   // the frame

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(motion)
        motion.addSublayer(imageLayer)
        for l in [motion, imageLayer] {
            l.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "contentsScale": NSNull(), "anchorPoint": NSNull(), "transform": NSNull()]
        }
        imageLayer.magnificationFilter = .linear
        imageLayer.minificationFilter = .linear
    }
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private var placed = CGRect.null
    private var placedScale: CGFloat = 0

    func show(_ image: CGImage, backing: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // only touch the geometry when it changed (a new size or screen): setting it is not free
        let rect = SpriteRenderer.rect()
        if rect != placed || backing != placedScale {
            placed = rect; placedScale = backing
            // the sway pivots about her feet
            let groundFromTop = (Design.ground + Design.lift) * Stage.dogScale + SpriteRenderer.margin
            let fy = (rect.height - groundFromTop) / rect.height
            motion.bounds = CGRect(origin: .zero, size: rect.size)
            motion.anchorPoint = CGPoint(x: 0.5, y: fy)
            motion.position = CGPoint(x: rect.midX, y: rect.minY + fy * rect.height)
            imageLayer.frame = motion.bounds
            imageLayer.contentsScale = backing
        }
        imageLayer.contents = image
        CATransaction.commit()
    }

    private var resting = false
    private var sleeping = false

    /// While she rests a little, she breathes and sways by herself; anything else stops it.
    func setResting(_ on: Bool, sleeping asleep: Bool) {
        guard on != resting || (on && asleep != sleeping) else { return }
        resting = on; sleeping = asleep
        motion.removeAllAnimations()
        guard on else { return }
        func wave(_ key: String, _ from: Double, _ to: Double, _ half: Double) {
            let a = CABasicAnimation(keyPath: key)
            a.fromValue = from; a.toValue = to
            a.duration = half
            a.autoreverses = true
            a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            motion.add(a, forKey: key)
        }
        wave("transform.scale.y", 0.9965, 1.0035, asleep ? 2.1 : 1.57)      // her chest swelling
        wave("transform.rotation.z", -0.0035, 0.0035, asleep ? 3.0 : 2.1)   // a slow sway
    }
}

extension Species {
    /// Animals whose tail is a small pom (or none) have nothing big moving while they rest, so resting can be a
    /// still picture. A cat, dog, fox or axolotl waves a long tail, which is real motion and keeps its frames.
    var stillWhenResting: Bool {
        switch self {
        case .bunny, .panda, .hamster, .capybara: return true
        default: return false
        }
    }
}

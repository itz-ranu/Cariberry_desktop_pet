import AppKit
import SwiftUI
import Combine

/// Dev helpers behind `DesktopPup --render-… /path/out.png`: draw the art to a PNG so a
/// change can be checked without launching the whole pet or granting screen recording.
enum RenderSheet {
    /// Every helper: flag, default file name, and what it draws. `species` is an
    /// optional extra argument after the path.
    @MainActor
    static func run(flag: String, args: [String]) -> Bool {
        let idx = args.firstIndex(of: flag)!
        let path = args.count > idx + 1 && !args[idx + 1].hasPrefix("--")
            ? args[idx + 1] : NSTemporaryDirectory() + flag.dropFirst(2) + ".png"
        let species = args.count > idx + 2 ? Species(rawValue: args[idx + 2]) ?? .cat : .cat

        switch flag {
        case "--render-sheet":    write(SheetView(species: species), path, scale: 1.5)
        case "--render-scene":    write(SceneCheck(species: species), path)
        case "--render-lineup":   write(LineupView(species: species), path, scale: 1.3)
        case "--render-species":  write(VStack(spacing: 0) { GalleryView(); AccessoryRow() }, path)
        case "--render-wardrobe": write(AccessoryRow(), path)
        case "--render-cards":    write(CardsCheck(), path, scale: 1.5)
        case "--render-chat":     return renderChat(path: path)
        case "--render-themes":   return renderThemes(path: path)
        case "--render-motion":   write(MotionView(species: species), path, scale: 1.5)
        case "--render-stats":    write(statsView(), path)
        case "--render-icon":     write(IconView(), path, scale: 1)
        case "--render-web":      renderWeb(dir: path)
        case "--render-share":
            write(ShareCard(name: "Cariberry", species: species, coat: 0, outfit: Outfit(head: .bow, face: .none, neck: .scarf),
                            dayTitle: "Today", date: "3 October 2026", focusMinutes: 135, goalMinutes: 120,
                            streak: 7, sessions: 4, tasks: 5, level: 9, title: "Best Friend"), path, scale: 2)
        case "--render-story":
            write(StoryCard(data: StoryData(name: "Cariberry", species: species, coat: 0, outfit: Outfit(head: .bow, face: .none, neck: .scarf, rug: .rugCoquette),
                                            focusMinutes: 135, goalMinutes: 120, streak: 7, sessions: 4, level: 9, title: "Best Friend",
                                            doneTasks: ["Finish chem notes", "Reply to Maya", "Read chapter 4", "Flashcards"],
                                            habitsDone: 3, habitsTotal: 5, badges: ["🌱", "🍵", "🔥", "💪", "⏱", "🎯", "🍅", "✅"], badgeTotal: 34,
                                            date: "saturday 3 october")), path, scale: 2)
        case "--render-panel":    return renderPanel(path: path)
        case "--bench-panel":     return benchPanel()
        case "--bench-stats":     return benchStats()
        case "--bench-scene":     return benchScene()
        case "--bench-life":      return benchLife()
        case "--render-placement": return renderPlacement(path: path)
        case "--bench-tick":      return benchTick()
        case "--render-spritecheck": return renderSpriteCheck(path: path, species: species)
        case "--bench-render":    return benchRender()
        default: return false
        }
        return true
    }

    static let flags = ["--render-placement", "--bench-tick", "--render-spritecheck", "--bench-render", "--bench-life", "--bench-scene", "--bench-panel", "--bench-stats", "--render-lineup", "--render-chat", "--render-themes", "--render-cards", "--render-wardrobe", "--render-share", "--render-sheet", "--render-scene", "--render-species", "--render-motion",
                        "--render-stats", "--render-icon", "--render-panel", "--render-story", "--render-web"]

    /// `--render-web dir`: every animal on a transparent background, for the download site.
    @MainActor
    private static func renderWeb(dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        func out(_ name: String, _ sp: Species, _ coat: Int, _ pose: Pose) {
            write(CritterView(species: sp, coat: coat, pose: pose), "\(dir)/\(name).png", scale: 4)
        }
        for sp in Species.allCases {
            for i in 0..<sp.coats.count {
                out("\(sp.rawValue)-\(i)", sp, i, Pose(emotion: .happy, phase: 0.4))
                out("\(sp.rawValue)-\(i)-excited", sp, i, Pose(emotion: .excited, phase: 0.42))
                out("\(sp.rawValue)-\(i)-sleepy", sp, i, Pose(emotion: .sleepy, phase: 0.6))
                out("\(sp.rawValue)-\(i)-love", sp, i, Pose(emotion: .love, phase: 0.4))
            }
        }
        let panda: [(String, Pose)] = [
            ("neutral", Pose(emotion: .neutral, phase: 0.42)), ("happy", Pose(emotion: .happy, phase: 0.4)),
            ("excited", Pose(emotion: .excited, phase: 0.42)), ("sleepy", Pose(emotion: .sleepy, phase: 0.6)),
            ("walking", Pose(emotion: .happy, phase: 0.3, gait: 1.2, walk: 1)),
            ("boba", Pose(emotion: .happy, phase: 0.9, sit: 1, prop: .boba, propAmt: 1)),
        ]
        for (n, p) in panda { out("panda-1-\(n)", .panda, 1, p) }
        let bow = Outfit(hair: .bow)
        out("hero-happy", .panda, 1, Pose(emotion: .happy, phase: 0.4, outfit: bow))
        out("hero-excited", .panda, 1, Pose(emotion: .excited, phase: 0.42, outfit: bow))
        out("hero-sleepy", .panda, 1, Pose(emotion: .sleepy, phase: 0.6, outfit: bow))
        out("hero-love", .panda, 1, Pose(emotion: .love, phase: 0.4, outfit: bow))
        out("hero-boba", .panda, 1, Pose(emotion: .happy, phase: 0.9, sit: 1, outfit: bow, prop: .boba, propAmt: 1))
        out("hero-study", .panda, 1, Pose(emotion: .cozy, phase: 0.9, sit: 1, outfit: Outfit(face: .glasses, hair: .bow), prop: .book, propAmt: 1))
        out("set-coquette", .cat, 0, Pose(emotion: .cozy, phase: 0.4, outfit: Outfit(head: .beret, face: .heartGlasses, neck: .pearls, hair: .bow, body: .knitSweater, aura: .auraHearts, rug: .rugCoquette)))
        out("set-study", .bunny, 0, Pose(emotion: .vibing, phase: 0.4, outfit: Outfit(head: .headphones, face: .glasses, neck: .bell, body: .hoodie, aura: .auraSparkles, rug: .rugCottage)))
        out("set-angel", .hamster, 0, Pose(emotion: .hyped, phase: 0.4, outfit: Outfit(head: .halo, face: .lashes, body: .angelWings, aura: .auraStars, rug: .rugY2K)))
        out("set-hero", .fox, 0, Pose(emotion: .moody, phase: 0.4, outfit: Outfit(face: .sunglasses, body: .cape, rug: .rugCyber)))
        out("set-matcha", .panda, 0, Pose(emotion: .cozy, phase: 0.9, sit: 1, outfit: Outfit(), prop: .matcha, propAmt: 1))
        out("set-gaming", .axolotl, 0, Pose(emotion: .hyped, phase: 0.9, sit: 1, outfit: Outfit(), prop: .console, propAmt: 1))
    }

    @MainActor
    private static func write<V: View>(_ view: V, _ path: String, scale: CGFloat = 2) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let img = renderer.nsImage,
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("render failed\n".utf8))
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }

    @MainActor
    private static func snapshot(_ view: PanelView) -> NSImage? {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: PanelView.width, height: PanelView.height)
        let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = host
        win.backgroundColor = NSColor(UI.bg)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        let img = NSImage(size: host.bounds.size)
        img.addRepresentation(rep)
        return img
    }

    @MainActor
    private static func samplePet() -> Pet {
        let pet = Pet()
        pet.name = "Cariberry"
        pet.xp = 640
        pet.berries = 118
        pet.totalFocusMinutes = 187
        pet.currentActivity = "Xcode"
        pet.lastVerdict = .work
        pet.tasks = [FocusTask(title: "Finish chem notes"), FocusTask(title: "Reply to Maya", done: true), FocusTask(title: "Read ch. 4")]
        let today = Calendar.current.startOfDay(for: Date())
        pet.dailyFocus[today] = 38
        for d in 1...3 { pet.dailyFocus[Calendar.current.date(byAdding: .day, value: -d, to: today)!] = 30 }
        pet.intention = "Chem notes"
        pet.outfit = Outfit(head: .beret, face: .heartGlasses, neck: .pearls, hair: .bow, body: .knitSweater, aura: .auraHearts, rug: .rugCoquette)
        pet.owned = ["rugCottage", "decor.plant"]
        pet.decorOn = ["plant"]
        Prefs.todayMood = .cozy
        return pet
    }

    @MainActor
    private static func stitch(_ shots: [NSImage], to path: String) {
        let w = PanelView.width, h = PanelView.height
        let total = NSSize(width: w * CGFloat(shots.count) + 16 * CGFloat(shots.count + 1), height: h + 32)
        let out = NSImage(size: total)
        out.lockFocus()
        NSColor(white: 0.82, alpha: 1).setFill()
        NSRect(origin: .zero, size: total).fill()
        for (i, s) in shots.enumerated() { s.draw(at: NSPoint(x: 16 + CGFloat(i) * (w + 16), y: 16), from: .zero, operation: .sourceOver, fraction: 1) }
        out.unlockFocus()
        guard let tiff = out.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }


    // MARK: Live benchmarks

    private static func cpuSeconds() -> Double {
        var ru = rusage(); getrusage(RUSAGE_SELF, &ru)
        return Double(ru.ru_utime.tv_sec) + Double(ru.ru_utime.tv_usec) / 1e6 + Double(ru.ru_stime.tv_sec) + Double(ru.ru_stime.tv_usec) / 1e6
    }

    /// Runs the run loop for `seconds` while ticking the pet like the real window does, and reports the CPU used.
    @MainActor
    private static func measure(_ title: String, pet: Pet, seconds: Double = 4) {
        var changes = 0
        let sub = pet.objectWillChange.sink { _ in changes += 1 }
        defer { sub.cancel() }
        // tick at the pace the real window uses (slow when she's idle, smooth when she moves)
        var running = true
        func next() {
            guard running else { return }
            Timer.scheduledTimer(withTimeInterval: pet.desiredFrameInterval, repeats: false) { _ in
                MainActor.assumeIsolated { pet.tick(pet.desiredFrameInterval); next() }
            }
        }
        next()
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))           // settle
        let c0 = cpuSeconds(), t0 = CFAbsoluteTimeGetCurrent()
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        let used = (cpuSeconds() - c0) / (CFAbsoluteTimeGetCurrent() - t0) * 100
        running = false
        print(String(format: "  %@: %.0f%% CPU, pet published %d changes", title, used, changes))
    }

    /// The panel open on screen, tab by tab, with the pet ticking: what you feel as lag.
    @MainActor
    private static func benchPanel() -> Bool {
        let pet = samplePet()
        if ProcessInfo.processInfo.environment["BENCH_PLAIN"] != nil { pet.outfit = Outfit(); pet.species = .panda }
        print("panel open, pet animating:")
        measure("no window (the pet alone)", pet: pet)
        for tab in PanelView.Tab.allCases where ProcessInfo.processInfo.environment["BENCH_TAB"].map({ $0 == tab.rawValue }) ?? true {
            let view = PanelView(pet: pet, actions: PanelActions(pet: pet, controller: nil, monitor: ActivityMonitor()), startTab: tab, welcome: false)
            let host = NSHostingView(rootView: view)
            let win = NSWindow(contentRect: NSRect(x: 80, y: 80, width: PanelView.width, height: PanelView.height), styleMask: [.titled], backing: .buffered, defer: false)
            win.contentView = host
            win.makeKeyAndOrderFront(nil)
            measure("\(tab.title) tab", pet: pet)
            win.close()
        }
        return true
    }

    /// The pet's own window, the way it sits on your desktop. The clock is bumped at a fixed rate (default
    /// 12 fps, her idle pace) so runs are comparable: it measures what one drawn frame costs.
    @MainActor
    private static func benchScene() -> Bool {
        let pet = Pet()
        pet.species = .panda; pet.coatIndex = 1
        pet.outfit = Outfit(hair: .bow)
        let mode = ProcessInfo.processInfo.environment["BENCH_MODE"] ?? "scene"
        let win = NSPanel(contentRect: NSRect(x: 80, y: 80, width: Stage.size.width, height: Stage.size.height),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        win.isOpaque = false; win.backgroundColor = .clear; win.hasShadow = false
        var layerView: NSView?
        var frames: [CGImage] = []
        var surfaceFrames: [IOSurface] = []
        var imageLayerForBench: CALayer?
        switch mode {
        case "layer":
            // a plain CALayer showing pre-drawn images: the floor for what a sprite player could cost
            let v = NSView(frame: NSRect(origin: .zero, size: Stage.size)); v.wantsLayer = true
            let r = ImageRenderer(content: CritterView(species: .panda, coat: 1, pose: Pose(emotion: .happy, phase: 0.4)).frame(width: Stage.size.width, height: Stage.size.height))
            r.scale = 2
            for _ in 0..<4 { if let cg = r.cgImage { frames.append(cg) } }
            win.contentView = v; layerView = v
        case "anim", "anim-nooutline", "anim-group", "anim-async", "anim-layerbacked":
            // the real thing: a pose that changes every frame, so every frame truly redraws
            struct Anim: View { @ObservedObject var clock: FrameClock; var mode: String
                var critter: some View {
                    CritterView(species: .panda, coat: 1, pose: Pose(emotion: .neutral, phase: Double(clock.frame) * 0.0833, walk: 0, outfit: Outfit(hair: .bow)), scale: Stage.dogScale)
                }
                var body: some View {
                    ZStack(alignment: .topLeading) {
                        Color.clear
                        switch mode {
                        case "anim-nooutline": critter.offset(x: Stage.dogOrigin.x, y: Stage.dogOrigin.y)
                        case "anim-group": critter.drawingGroup().stickerOutline(max(1.4, Stage.dogScale * 3.6)).offset(x: Stage.dogOrigin.x, y: Stage.dogOrigin.y)
                        default: critter.stickerOutline(max(1.4, Stage.dogScale * 3.6)).offset(x: Stage.dogOrigin.x, y: Stage.dogOrigin.y)
                        }
                    }.frame(width: Stage.size.width, height: Stage.size.height)
                } }
            win.contentView = NSHostingView(rootView: Anim(clock: pet.clock, mode: mode))
        case "layer-many", "layer-many-iosurface":
            // many distinct frames cycling through a layer: does each new image cost an upload?
            let v = NSView(frame: NSRect(origin: .zero, size: Stage.size)); v.wantsLayer = true
            let il = CALayer(); il.frame = CGRect(x: 40, y: 20, width: 136, height: 133); il.contentsScale = 2
            v.layer?.addSublayer(il)
            let n = Int(ProcessInfo.processInfo.environment["BENCH_N"] ?? "") ?? 200
            var cgs: [CGImage] = []
            var surfaces: [IOSurface] = []
            for k in 0..<n {
                let r = ImageRenderer(content: CritterView(species: .panda, coat: 1, pose: Pose(emotion: .neutral, phase: Double(k) * 0.05, outfit: Outfit(hair: .bow)), scale: 0.52).stickerOutline(2).frame(width: 104, height: 101).padding(16))
                r.scale = 2
                guard let cg = r.cgImage else { continue }
                if mode == "layer-many-iosurface" {
                    let props: [IOSurfacePropertyKey: Any] = [.width: cg.width, .height: cg.height, .bytesPerElement: 4, .pixelFormat: 0x42475241 /* BGRA */]
                    if let surf = IOSurface(properties: props) {
                        surf.lock(options: [], seed: nil)
                        let c = CGContext(data: surf.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: surf.bytesPerRow, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
                        c.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
                        surf.unlock(options: [], seed: nil)
                        surfaces.append(surf)
                    }
                } else { cgs.append(cg) }
            }
            win.contentView = v; layerView = v
            frames = cgs
            surfaceFrames = surfaces
            imageLayerForBench = il
        case "cached", "cached-nsimage":
            // pre-drawn frames (the pet with her sticker outline) swapped in as plain images
            let content = CritterView(species: .panda, coat: 1, pose: Pose(emotion: .neutral, phase: 0.4, outfit: Outfit(hair: .bow)), scale: Stage.dogScale).stickerOutline(max(1.4, Stage.dogScale * 3.6))
                .frame(width: Design.width * Stage.dogScale + 20, height: Design.height * Stage.dogScale + 20)
            var imgs: [NSImage] = []
            for k in 0..<8 {
                let r = ImageRenderer(content: CritterView(species: .panda, coat: 1, pose: Pose(emotion: .neutral, phase: Double(k) * 0.2, outfit: Outfit(hair: .bow)), scale: Stage.dogScale).stickerOutline(max(1.4, Stage.dogScale * 3.6))
                    .frame(width: Design.width * Stage.dogScale + 20, height: Design.height * Stage.dogScale + 20))
                r.scale = 2
                if let im = r.nsImage { imgs.append(im) }
            }
            _ = content
            struct Cached: View { @ObservedObject var clock: FrameClock; var imgs: [NSImage]
                var body: some View {
                    ZStack(alignment: .topLeading) {
                        Color.clear
                        Image(nsImage: imgs[clock.frame % imgs.count]).offset(x: Stage.dogOrigin.x - 10, y: Stage.dogOrigin.y - 10)
                    }.frame(width: Stage.size.width, height: Stage.size.height)
                } }
            win.contentView = NSHostingView(rootView: Cached(clock: pet.clock, imgs: imgs))
        case "front-static", "back-and-front-static":
            let rect = NSRect(origin: .zero, size: Stage.size)
            let c = NSView(frame: rect)
            if mode == "back-and-front-static" { let b = NSHostingView(rootView: SceneView(pet: pet, layer: .back)); b.frame = rect; c.addSubview(b) }
            let sp = PetSpriteView(frame: rect); c.addSubview(sp)
            let f = NSHostingView(rootView: SceneView(pet: pet, layer: .front)); f.frame = rect; c.addSubview(f)
            win.contentView = c
        case "empty":
            win.contentView = NSHostingView(rootView: Color.clear.frame(width: Stage.size.width, height: Stage.size.height))
        case "canvas1":
            // SwiftUI + Canvas, but the canvas draws one rectangle: the fixed cost of the pipeline
            struct Tiny: View { @ObservedObject var clock: FrameClock
                var body: some View { let _ = clock.frame; Canvas { c, _ in c.fill(Path(CGRect(x: 10, y: 10, width: 50, height: 50)), with: .color(.pink)) }.frame(width: Double(ProcessInfo.processInfo.environment["BENCH_W"] ?? "") ?? Stage.size.width, height: Double(ProcessInfo.processInfo.environment["BENCH_W"] ?? "") ?? Stage.size.height) } }
            win.contentView = NSHostingView(rootView: Tiny(clock: pet.clock))
        default:
            win.contentView = NSHostingView(rootView: SceneView(pet: pet))
        }
        win.orderFrontRegardless()
        let fps = Double(ProcessInfo.processInfo.environment["BENCH_FPS"] ?? "") ?? 12
        var k = 0
        let timer = Timer.scheduledTimer(withTimeInterval: 1 / fps, repeats: true) { _ in
            MainActor.assumeIsolated {
                if let il = imageLayerForBench {
                    k += 1
                    CATransaction.begin(); CATransaction.setDisableActions(true)
                    if !surfaceFrames.isEmpty { il.contents = surfaceFrames[k % surfaceFrames.count] } else if !frames.isEmpty { il.contents = frames[k % frames.count] }
                    CATransaction.commit()
                } else if let lv = layerView, !frames.isEmpty { k += 1; lv.layer?.contents = frames[k % frames.count] } else { pet.clock.frame &+= 1 }
            }
        }
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        let c0 = cpuSeconds(), t0 = CFAbsoluteTimeGetCurrent()
        RunLoop.main.run(until: Date().addingTimeInterval(8))
        let used = (cpuSeconds() - c0) / (CFAbsoluteTimeGetCurrent() - t0) * 100
        timer.invalidate()
        print(String(format: "  pet window at %.0f fps: %.1f%% CPU  (%.2f ms per frame)", fps, used, used / 100 / fps * 1000))
        win.close()
        return true
    }

    /// A minute and a half of her real life (acts, walking, the lot) with the window open, reporting CPU
    /// and how the time split across frame rates.
    @MainActor
    private static func benchLife() -> Bool {
        let pet = Pet()
        pet.species = .panda; pet.coatIndex = 1
        pet.outfit = Outfit(hair: .bow)
        let live = ProcessInfo.processInfo.environment["CARI_LIVE"] != nil
        if ProcessInfo.processInfo.environment["BENCH_STILL"] != nil { pet.holdStill = true }   // she stays where she is
        let rect = NSRect(origin: .zero, size: Stage.size)
        let win = NSPanel(contentRect: NSRect(x: 80, y: 80, width: Stage.size.width, height: Stage.size.height),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        win.isOpaque = false; win.backgroundColor = .clear; win.hasShadow = false
        let content = NSView(frame: rect)
        let sprite = PetSpriteView(frame: rect)
        if live {
            let host = NSHostingView(rootView: SceneView(pet: pet)); host.frame = rect; content.addSubview(host)
        } else {
            content.addSubview(sprite)
            let front = NSHostingView(rootView: SceneView(pet: pet, layer: .front)); front.frame = rect; content.addSubview(front)
        }
        win.contentView = content
        win.orderFrontRegardless()
        var lastKey: SpriteKey?
        var missTags: [String: Int] = [:]
        var tickWall = 0.0, spriteWall = 0.0
        var missSamples: [String] = []
        var renderCPU = 0.0, renderWall = 0.0, renders = 0, showCPU = 0.0, shows = 0
        func showSprite() {
            guard !live else { return }
            let (snapped, key) = pet.pose.snapped(species: pet.species, coat: pet.coatIndex, scale: pet.scale, backing: 2)
            sprite.setResting(pet.species.stillWhenResting && snapped.isCalm(snapped), sleeping: snapped.sleep > 0.5)
            guard key != lastKey else { return }
            lastKey = key
            let scale = pet.scale
            if let img = SpriteCache.shared.image(for: key, render: {
                let tag = snapped.walk > 0.95 ? "walk(\(pet.act))" : (snapped.walk > 0 ? "walk-blend" : (snapped.sit > 0 && snapped.sit < 1 ? "sit-blend" : (snapped.sleep > 0 && snapped.sleep < 1 ? "sleep-blend" : "\(pet.act)/\(snapped.emotion)")))
                missTags[tag, default: 0] += 1
                if tag.hasPrefix("idle") && missSamples.count < 40 { missSamples.append("steps=\(key.steps) emo=\(key.emotion)") }
                let a = cpuSeconds(), w = CFAbsoluteTimeGetCurrent()
                let r = SpriteRenderer.render(species: pet.species, coat: pet.coatIndex, pose: snapped, scale: scale, backing: 2)
                renderCPU += cpuSeconds() - a; renderWall += CFAbsoluteTimeGetCurrent() - w; renders += 1
                return r }) {
                let a = cpuSeconds()
                sprite.show(img, backing: 2)
                showCPU += cpuSeconds() - a; shows += 1
            }
        }
        let seconds = Double(ProcessInfo.processInfo.environment["BENCH_SECONDS"] ?? "") ?? 90
        var running = true
        var frames = 0
        var published = 0
        let sub = pet.objectWillChange.sink { _ in published += 1 }
        defer { sub.cancel() }
        var byInterval: [Int: Double] = [:], byAct: [String: Double] = [:], cpuByAct: [String: Double] = [:], framesByAct: [String: Int] = [:], cpuByRate: [Int: Double] = [:], lastRate = 0
        var lastCPU = cpuSeconds(), lastAct = "\(pet.act)"
        func next() {
            guard running else { return }
            let dt = pet.desiredFrameInterval
            Timer.scheduledTimer(withTimeInterval: dt, repeats: false) { _ in
                MainActor.assumeIsolated {
                    let c = cpuSeconds(); cpuByAct[lastAct, default: 0] += c - lastCPU; cpuByRate[lastRate, default: 0] += c - lastCPU; lastCPU = c; lastRate = Int((1 / dt).rounded())
                    let w0 = CFAbsoluteTimeGetCurrent()
                    pet.tick(dt); frames += 1
                    let w1 = CFAbsoluteTimeGetCurrent()
                    showSprite()
                    let w2 = CFAbsoluteTimeGetCurrent()
                    tickWall += w1 - w0; spriteWall += w2 - w1
                    lastAct = "\(pet.act)"
                    framesByAct[lastAct, default: 0] += 1
                    byInterval[Int((1 / dt).rounded()), default: 0] += dt
                    byAct[lastAct, default: 0] += dt
                    next()
                }
            }
        }
        next()
        let c0 = cpuSeconds(), t0 = CFAbsoluteTimeGetCurrent()
        var chunkC = c0, chunkT = t0, h0 = 0, m0 = 0
        while CFAbsoluteTimeGetCurrent() - t0 < seconds {
            RunLoop.main.run(until: Date().addingTimeInterval(min(60, seconds - (CFAbsoluteTimeGetCurrent() - t0))))
            let c = cpuSeconds(), t = CFAbsoluteTimeGetCurrent()
            let cache = SpriteCache.shared
            print(String(format: "    minute %.0f: %.2f%% CPU, cache %d frames %.0f MB, this minute %d hits / %d misses", (t - t0) / 60, (c - chunkC) / (t - chunkT) * 100, cache.count, cache.megabytes, cache.hits - h0, cache.misses - m0))
            chunkC = c; chunkT = t; h0 = cache.hits; m0 = cache.misses
        }
        let wall = CFAbsoluteTimeGetCurrent() - t0
        running = false
        print(String(format: "  her real life for %.0fs: %.2f%% CPU, %.1f frames/s, pet published %.1f changes/s", wall, (cpuSeconds() - c0) / wall * 100, Double(frames) / wall, Double(published) / wall))
        print(String(format: "  one miss costs %.2f ms cpu (%.2f ms wall) to draw; showing a frame costs %.3f ms cpu", renderCPU / Double(max(1, renders)) * 1000, renderWall / Double(max(1, renders)) * 1000, showCPU / Double(max(1, shows)) * 1000))
        for m in missSamples.prefix(24) { print("   idle miss:", m) }
        print(String(format: "  main-thread time per tick: Pet.tick %.3f ms, sprite lookup+show %.3f ms (%d ticks)", tickWall / Double(max(1, frames)) * 1000, spriteWall / Double(max(1, frames)) * 1000, frames))
        print("  misses by kind:", missTags.sorted { $0.value > $1.value }.prefix(12).map { "\($0.key) \($0.value)" }.joined(separator: " | "))
        print(String(format: "  sprite cache: %d frames in memory, %.1f MB on disk, %d memory hits / %d disk hits / %d drawn", SpriteCache.shared.count, SpriteCache.shared.megabytes, SpriteCache.shared.hits, SpriteCache.shared.diskHits, SpriteCache.shared.misses))
        print("  time by frame rate:", byInterval.sorted { $0.key < $1.key }.map { "\($0.key)fps \(Int($0.value / wall * 100))% of time, \(String(format: "%.2f", (cpuByRate[$0.key] ?? 0) / wall * 100))% of CPU" }.joined(separator: " | "))
        print("  time by act:", byAct.sorted { $0.value > $1.value }.map { "\($0.key) \(Int($0.value / wall * 100))%" }.joined(separator: "  "))
        print("  CPU while in each act:", byAct.keys.sorted().map { String(format: "%@ %.1f%% (%.2f ms/frame)", $0, (cpuByAct[$0] ?? 0) / max(0.001, byAct[$0] ?? 0.001) * 100, (cpuByAct[$0] ?? 0) / Double(max(1, framesByAct[$0] ?? 1)) * 1000) }.joined(separator: " | "))
        win.close()
        return true
    }

    /// What it costs to draw one pet frame into an image (the price of a sprite-cache miss).
    @MainActor
    private static func benchRender() -> Bool {
        let n = Int(ProcessInfo.processInfo.environment["BENCH_N"] ?? "") ?? 200
        for useCG in [false, true] {
            let c0 = cpuSeconds(), t0 = CFAbsoluteTimeGetCurrent()
            var bytes = 0
            for k in 0..<n {
                let v = CritterView(species: .panda, coat: 1, pose: Pose(emotion: .neutral, phase: Double(k) * 0.083, outfit: Outfit(hair: .bow)), scale: Stage.dogScale)
                    .stickerOutline(max(1.4, Stage.dogScale * 3.6))
                    .frame(width: Design.width * Stage.dogScale + 20, height: Design.height * Stage.dogScale + 20)
                let r = ImageRenderer(content: v); r.scale = 2
                if useCG { if let cg = r.cgImage { bytes = cg.bytesPerRow * cg.height } } else if let im = r.nsImage { bytes = Int(im.size.width * im.size.height * 4) * 4 }
            }
            let wall = CFAbsoluteTimeGetCurrent() - t0
            print(String(format: "  ImageRenderer %@: %.2f ms wall, %.2f ms cpu per frame, image %d KB", useCG ? "cgImage" : "nsImage", wall / Double(n) * 1000, (cpuSeconds() - c0) / Double(n) * 1000, bytes / 1024))
        }
        return true
    }

    /// Live drawing against the cached image for the same moment: the two rows must look the same.
    @MainActor
    private static func renderSpriteCheck(path: String, species: Species) -> Bool {
        let poses: [(String, Pose)] = [
            ("neutral", Pose(emotion: .neutral, phase: 7.77, outfit: Outfit(hair: .bow))),
            ("blink", Pose(emotion: .neutral, phase: Loop.period + 0.07, outfit: Outfit(hair: .bow))),
            ("sit", Pose(emotion: .happy, phase: 3.3, sit: 1, outfit: Outfit(hair: .bow))),
            ("walk", Pose(emotion: .happy, phase: 2.2, gait: 2.4, walk: 1, outfit: Outfit(hair: .bow))),
            ("look", Pose(emotion: .happy, phase: 5.1, look: CGVector(dx: -0.62, dy: -0.4), outfit: Outfit(hair: .bow))),
            ("sleep", Pose(emotion: .sleepy, phase: 4.4, sleep: 1, outfit: Outfit(hair: .bow))),
            ("turning", Pose(emotion: .happy, phase: 1.1, facing: 0.35, outfit: Outfit(hair: .bow))),
        ]
        let scale = Stage.dogScale
        var live: [AnyView] = [], cached: [AnyView] = []
        for (_, p) in poses {
            let (snapped, key) = p.snapped(species: species, coat: 1, scale: scale, backing: 2)
            live.append(AnyView(CritterView(species: species, coat: 1, pose: p, scale: scale).stickerOutline(max(1.4, scale * 3.6))
                .frame(width: Design.width * scale, height: Design.height * scale).padding(SpriteRenderer.margin)))
            if let img = SpriteCache.shared.image(for: key, render: { SpriteRenderer.render(species: species, coat: 1, pose: snapped, scale: scale, backing: 2) }) {
                cached.append(AnyView(Image(decorative: img, scale: 2).padding(0)))
            }
        }
        let view = VStack(spacing: 4) {
            HStack(spacing: 4) { ForEach(0..<live.count, id: \.self) { live[$0] } }
            HStack(spacing: 4) { ForEach(0..<cached.count, id: \.self) { cached[$0] } }
        }.padding(8).background(Color(white: 0.93))
        write(view, path, scale: 2)
        return true
    }

    /// The pet's brain alone, with no window: what one tick costs.
    @MainActor
    private static func benchTick() -> Bool {
        let pet = Pet()
        pet.species = .panda
        let n = Int(ProcessInfo.processInfo.environment["BENCH_N"] ?? "") ?? 20000
        for _ in 0..<500 { pet.tick(0.08) }
        let t0 = CFAbsoluteTimeGetCurrent()
        for _ in 0..<n { pet.tick(0.08) }
        let ms = (CFAbsoluteTimeGetCurrent() - t0) / Double(n) * 1000
        let t1 = CFAbsoluteTimeGetCurrent()
        var acc = 0.0
        for _ in 0..<n { acc += pet.pose.phase + pet.desiredFrameInterval }
        let ms2 = (CFAbsoluteTimeGetCurrent() - t1) / Double(n) * 1000
        print(String(format: "  Pet.tick: %.3f ms   pose + desiredFrameInterval: %.3f ms (%.0f)", ms, ms2, acc))
        return true
    }

    /// Is the cached picture exactly where live drawing puts her? Both are drawn offscreen at the window's size and
    /// compared pixel by pixel.
    @MainActor
    private static func renderPlacement(path: String) -> Bool {
        let pet = Pet()
        pet.species = .panda; pet.coatIndex = 1
        pet.outfit = Outfit(hair: .bow)
        let w = Int(Stage.size.width * 2), h = Int(Stage.size.height * 2)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

        // live: the whole scene drawn by SwiftUI
        let r = ImageRenderer(content: SceneView(pet: pet).frame(width: Stage.size.width, height: Stage.size.height))
        r.scale = 2; r.isOpaque = false
        guard let liveImage = r.cgImage else { return true }

        // cached: the same pose through the sprite layer, composited by Core Animation's own renderer
        let rect = NSRect(origin: .zero, size: Stage.size)
        let view = PetSpriteView(frame: rect)
        let (snapped, key) = pet.pose.snapped(species: pet.species, coat: pet.coatIndex, scale: pet.scale, backing: 2)
        guard let sprite = SpriteRenderer.render(species: pet.species, coat: pet.coatIndex, pose: snapped, scale: pet.scale, backing: 2) else { return true }
        _ = key
        view.show(sprite, backing: 2)
        view.layoutSubtreeIfNeeded()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info) else { return true }
        ctx.scaleBy(x: 2, y: 2)
        view.layer?.render(in: ctx)
        guard let layerImage = ctx.makeImage() else { return true }

        func pixels(_ img: CGImage) -> [UInt8] {
            var buf = [UInt8](repeating: 0, count: w * h * 4)
            let c = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space, bitmapInfo: info)!
            c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return buf
        }
        let a = pixels(liveImage), b = pixels(layerImage)
        var diff = 0.0, ax = 0.0, ay = 0.0, bx = 0.0, by = 0.0, an = 0.0, bn = 0.0
        for y in 0..<h { for x in 0..<w {
            let i = (y * w + x) * 4
            diff += abs(Double(a[i + 3]) - Double(b[i + 3]))
            ax += Double(x) * Double(a[i + 3]); ay += Double(y) * Double(a[i + 3]); an += Double(a[i + 3])
            bx += Double(x) * Double(b[i + 3]); by += Double(y) * Double(b[i + 3]); bn += Double(b[i + 3])
        } }
        print(String(format: "  alpha mean abs diff %.2f / 255; centre of the pet live (%.1f, %.1f) vs cached (%.1f, %.1f) px", diff / Double(w * h), ax / an, ay / an, bx / bn, by / bn))
        // side by side, for eyes
        let both = HStack(spacing: 6) { Image(decorative: liveImage, scale: 2); Image(decorative: layerImage, scale: 2) }.padding(6).background(Color(white: 0.9))
        write(both, path, scale: 2)
        return true
    }

    @MainActor
    private static func benchStats() -> Bool {
        let pet = statsView().pet
        let host = NSHostingView(rootView: StatsView(pet: pet))
        let win = NSWindow(contentRect: NSRect(x: 80, y: 80, width: StatsView.width, height: 820), styleMask: [.titled], backing: .buffered, defer: false)
        win.contentView = host
        win.makeKeyAndOrderFront(nil)
        print("stats open, pet animating:")
        measure("Stats window", pet: pet)
        win.close()
        return true
    }

    /// The control panel uses real controls, which `ImageRenderer` can't draw, so it is hosted
    /// in an offscreen window and snapshotted instead.
    @MainActor
    private static func renderPanel(path: String) -> Bool {
        let pet = samplePet()
        var shots: [NSImage] = []
        for tab in PanelView.Tab.allCases {
            let view = PanelView(pet: pet, actions: PanelActions(pet: pet, controller: nil, monitor: ActivityMonitor()),
                                 startTab: tab, welcome: false)
            let t0 = CFAbsoluteTimeGetCurrent()
            if let img = snapshot(view) { shots.append(img) }
            print(String(format: "  %@ tab: %.0f ms", tab.title, (CFAbsoluteTimeGetCurrent() - t0) * 1000 - 250))
        }
        stitch(shots, to: path)
        return true
    }

    /// The chat drawer, snapshotted through a real window (ImageRenderer can't draw a ScrollView).
    @MainActor
    private static func renderChat(path: String) -> Bool {
        let pet = Pet()
        let chat = ChatState()
        chat.pet = pet
        chat.messages = [
            ChatMessage(role: .pet, text: "hi bestie, I'm Cariberry 🐾 ask me anything, or say “focus 25”"),
            ChatMessage(role: .user, text: "can you explain photosynthesis like I'm five"),
            ChatMessage(role: .pet, text: "plants eat sunlight like snacks 🌞 they mix it with water and air to make their own food, and breathe out the oxygen we need 🌿"),
            ChatMessage(role: .user, text: "focus 25"),
            ChatMessage(role: .pet, text: "25 min. I'll supervise. 📖")]
        let host = NSHostingView(rootView: FloatingChatDrawer(chat: chat, pet: pet, onClose: {}, onStartBrain: {}))
        host.frame = NSRect(x: 0, y: 0, width: 366, height: 486)
        let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = host
        win.backgroundColor = NSColor(white: 0.85, alpha: 1)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return true }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path)")
        }
        return true
    }

    /// The Home tab in every aesthetic mood.
    @MainActor
    private static func renderThemes(path: String) -> Bool {
        let pet = samplePet()
        var shots: [NSImage] = []
        for theme in AppTheme.allCases {
            AppTheme.current = theme
            let view = PanelView(pet: pet, actions: PanelActions(pet: pet, controller: nil, monitor: ActivityMonitor()),
                                 startTab: .home, welcome: false)
            if let img = snapshot(view) { shots.append(img) }
        }
        AppTheme.current = Prefs.theme
        stitch(shots, to: path)
        return true
    }

    @MainActor
    private static func statsView() -> StatsView {
        let p = Pet()
        p.name = "Cariberry"
        p.totalFocusMinutes = 187
        p.treatsEaten = 14
        p.barksGiven = 6
        p.siteTime = ["github.com": 5200, "xcode": 4100, "youtube.com": 1800,
                      "twitter.com": 900, "notion.so": 700, "reddit.com": 320]
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let sample: [Double] = [12, 48, 0, 65, 30, 90, 22]
        for (i, minutes) in sample.enumerated() {
            let day = cal.date(byAdding: .day, value: -(6 - i), to: today)!
            p.dailyFocus[day] = minutes
        }
        p.xp = 1180
        p.categoryTime = ["Coding": 9364, "Studying & writing": 8, "Games": 3998,
                          "Social media": 158, "Reels & short-form video": 666,
                          "YouTube (might be learning, might not)": 374, "Other": 81770]
        p.dailyFocus[today] = 42.4
        p.dailyDistraction[today] = 11 * 60
        p.dailySessions[today] = 2
        p.dailyTasks[today] = 3
        p.dailyBarks[today] = 2
        for (i, m) in [30.0, 75, 0, 64, 90, 45, 20, 66, 80, 15].enumerated() {
            let d = cal.date(byAdding: .day, value: -(i + 1), to: today)!
            p.dailyFocus[d] = m
            p.dailySessions[d] = Int(m / 25)
            p.dailyDistraction[d] = m * 20
        }
        Prefs.badges = Set(["first", "streak3", "hour", "goal1", "sess5", "lvl5", "tasks10"])
        p.dailyAppTime[today] = ["Xcode": 4080, "Spotify": 3120, "Safari": 1860,
                                  "Slack": 900, "instagram.com": 660, "Mail": 180, "Notes": 90]
        p.siteKinds = ["Xcode": "work", "Notes": "work", "instagram.com": "distraction", "Spotify": "neutral", "Safari": "neutral"]
        p.dailyAway[today] = 840
        p.focusByHour = [9: 40, 10: 75, 11: 60, 14: 85, 15: 120, 16: 90, 20: 55, 21: 30]
        return StatsView(pet: p, scrolls: false)
    }
}

// MARK: - Views

/// Full window contents (pet + bubble + particles + bowl) so layout can be checked.
private struct SceneCheck: View {
    var species: Species

    @MainActor private func pet(_ text: String, _ mood: Emotion, particles: Particle.Kind?, bowl: Double = 0) -> Pet {
        let p = Pet()
        p.species = species
        p.bubbleText = text
        p.moodOverride = (mood, Date().addingTimeInterval(600))
        p.bowl = bowl
        if let k = particles { p.emit(k, count: 7, at: Stage.head, spread: 40) }
        return p
    }

    var body: some View {
        HStack(spacing: 8) {
            cell(pet("BARK BARK! reels again?! eyes UP", .angry, particles: .anger))
            cell(pet("you're doing amazing 💗", .love, particles: .heart))
            cell(pet("OM NOM NOM 🍖", .eating, particles: .crumb, bowl: 1))
            cell(decorated(pet("zzz…", .sleepy, particles: .zzz)))
        }
        .padding(8)
        .background(Color(white: 0.82))
    }

    @MainActor private func decorated(_ p: Pet) -> Pet {
        p.decorOn = Set(Decor.allCases.map(\.rawValue))
        p.outfit = Outfit(head: .halo, body: .angelWings, aura: .auraSparkles, rug: .rugY2K)
        return p
    }

    private func cell(_ p: Pet) -> some View {
        SceneView(pet: p)
            .frame(width: Stage.size.width, height: Stage.size.height)
            .background(Color(white: 0.93))
            .border(Color.red.opacity(0.35))
    }
}

private struct IconView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 230, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.92, blue: 0.90),
                                              Color(red: 0.93, green: 0.84, blue: 0.97)],
                                     startPoint: .top, endPoint: .bottom))
            CritterView(species: .cat, coat: 0, pose: Pose(emotion: .happy, phase: 0.42))
                .frame(width: Design.width, height: Design.height)
                .scaleEffect(4.4)
                .offset(y: 118)
        }
        .frame(width: 1024, height: 1024)
    }
}

private struct Labeled<Content: View>: View {
    var label: String
    var content: Content
    init(_ label: String, @ViewBuilder _ content: () -> Content) { self.label = label; self.content = content() }
    var body: some View {
        VStack(spacing: 0) {
            content.frame(width: Design.width, height: Design.height)
            Text(label).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                .padding(.bottom, 4)
        }
        .background(Color(white: 0.94))
    }
}

/// Every emotion plus the special poses, for one species.
private struct SheetView: View {
    var species: Species

    private var cells: [(String, Pose)] {
        var out: [(String, Pose)] = Emotion.allCases.map { ($0.rawValue, Pose(emotion: $0, phase: 0.42)) }
        out += [
            ("walking", Pose(emotion: .happy, phase: 0.30, gait: 1.2, walk: 1)),
            ("walk left", Pose(emotion: .neutral, phase: 0.9, gait: 3.4, walk: 1, facing: -1)),
            ("turning", Pose(emotion: .happy, phase: 0.3, facing: 0.3)),
            ("landed", Pose(emotion: .dizzy, phase: 0.2, squash: 0.9)),
            ("carried", Pose(emotion: .dizzy, phase: 0.5, dangling: true)),
            ("stretch", Pose(emotion: .happy, phase: 0.35, stretch: 1)),
            ("sniff", Pose(emotion: .curious, phase: 0.4, sniff: 1)),
            ("sit", Pose(emotion: .happy, phase: 0.2, sit: 1)),
            ("groom", Pose(emotion: .happy, phase: 0.227, sit: 1, groom: 1)),
            ("scratch", Pose(emotion: .neutral, phase: 0.3, sit: 1, scratch: 1)),
            ("sleep", Pose(emotion: .sleepy, phase: 0.6, sleep: 1)),
            ("tap", Pose(emotion: .alert, phase: 0.4, tapping: true, tapPhase: 0.5)),
            ("dance", Pose(emotion: .happy, phase: 0.55, dance: 1)),
            ("wave", Pose(emotion: .happy, phase: 0.3, sit: 1, wave: 1)),
            ("study", Pose(emotion: .neutral, phase: 0.7, sit: 1, prop: .book, propAmt: 1)),
            ("boba", Pose(emotion: .happy, phase: 0.9, sit: 1, prop: .boba, propAmt: 1)),
            ("perched", Pose(emotion: .happy, phase: 0.4, outfit: Outfit(head: .headphones, face: .sunglasses, neck: .bandana), perched: true)),
            ("collar t3", Pose(emotion: .happy, phase: 0.4, collarTier: 3)),
        ]
        return out
    }

    var body: some View {
        let cols = 5
        let list = cells
        VStack(spacing: 0) {
            Text("\(species.displayName) · expression sheet")
                .font(.system(size: 20, weight: .bold, design: .rounded)).padding(.vertical, 10)
            ForEach(0..<((list.count + cols - 1) / cols), id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<cols, id: \.self) { col in
                        let i = row * cols + col
                        if i < list.count {
                            Labeled(list[i].0) { CritterView(species: species, coat: 0, pose: list[i].1) }
                        } else {
                            Color(white: 0.94).frame(width: Design.width, height: Design.height + 20)
                        }
                    }
                }
            }
        }
        .background(Color(white: 0.94))
    }
}

/// One species: every colourway down the page, six moods across. The quick check for a redesign.
private struct LineupView: View {
    var species: Species

    private let poses: [(String, Pose)] = [
        ("neutral", Pose(emotion: .neutral, phase: 0.42)),
        ("happy", Pose(emotion: .happy, phase: 0.4)),
        ("excited", Pose(emotion: .excited, phase: 0.42)),
        ("sleepy", Pose(emotion: .sleepy, phase: 0.6)),
        ("walking", Pose(emotion: .happy, phase: 0.3, gait: 1.2, walk: 1)),
        ("sit + boba", Pose(emotion: .happy, phase: 0.9, sit: 1, prop: .boba, propAmt: 1)),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<species.coats.count, id: \.self) { i in
                HStack(spacing: 0) {
                    ForEach(0..<poses.count, id: \.self) { j in
                        Labeled("\(species.coats[i].name) · \(poses[j].0)") {
                            CritterView(species: species, coat: i, pose: poses[j].1)
                        }
                    }
                }
            }
        }
        .background(Color(white: 0.94))
    }
}

/// Every species in every colourway, side by side.
private struct GalleryView: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Species.allCases, id: \.self) { s in
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { i in
                        if i < s.coats.count {
                            Labeled("\(s.displayName) · \(s.coats[i].name)") {
                                CritterView(species: s, coat: i, pose: Pose(emotion: .happy, phase: 0.4))
                            }
                        } else {
                            Color(white: 0.94).frame(width: Design.width, height: Design.height + 20)
                        }
                    }
                }
            }
        }
        .background(Color(white: 0.94))
    }
}

/// Dress-up check: every accessory on a rotating cast of animals.
private struct AccessoryRow: View {
    var body: some View {
        let items = Accessory.allCases.filter { $0 != .none }
        VStack(spacing: 0) {
            ForEach(0..<((items.count + 6) / 7), id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { col in
                        let i = row * 7 + col
                        if i < items.count {
                            let a = items[i]
                            let sp = Species.allCases[i % Species.allCases.count]
                            var o = Outfit(); let _ = (o[a.slot] = a)
                            Labeled("\(sp.displayName) · \(a.title)") {
                                CritterView(species: sp, coat: 0, pose: Pose(emotion: .happy, phase: 0.4, outfit: o))
                            }
                        } else { Color(white: 0.94).frame(width: Design.width, height: Design.height + 20) }
                    }
                }
            }
            HStack(spacing: 0) {
                Labeled("coquette set") {
                    CritterView(species: .cat, coat: 0, pose: Pose(emotion: .cozy, phase: 0.4,
                        outfit: Outfit(head: .beret, face: .heartGlasses, neck: .pearls, hair: .bow, body: .knitSweater, aura: .auraHearts, rug: .rugCoquette)))
                }
                Labeled("study set") {
                    CritterView(species: .bunny, coat: 0, pose: Pose(emotion: .vibing, phase: 0.4,
                        outfit: Outfit(head: .headphones, face: .glasses, neck: .bell, body: .hoodie, aura: .auraSparkles, rug: .rugCottage)))
                }
                Labeled("angel") {
                    CritterView(species: .hamster, coat: 0, pose: Pose(emotion: .hyped, phase: 0.4,
                        outfit: Outfit(head: .halo, face: .lashes, body: .angelWings, aura: .auraStars, rug: .rugY2K)))
                }
                Labeled("hero") {
                    CritterView(species: .fox, coat: 0, pose: Pose(emotion: .moody, phase: 0.4,
                        outfit: Outfit(face: .sunglasses, body: .cape, rug: .rugCyber)))
                }
                Labeled("matcha break") {
                    CritterView(species: .panda, coat: 0, pose: Pose(emotion: .cozy, phase: 0.9, sit: 1, outfit: Outfit(), prop: .matcha, propAmt: 1))
                }
                Labeled("gaming") {
                    CritterView(species: .axolotl, coat: 0, pose: Pose(emotion: .hyped, phase: 0.9, sit: 1, outfit: Outfit(), prop: .console, propAmt: 1))
                }
            }
        }
        .background(Color(white: 0.94))
    }
}

/// Frame strips: walk cycle, hop, sit-down, turn, eat, sleep: motion checked as stills.
private struct MotionView: View {
    var species: Species

    private func strip(_ title: String, _ poses: [Pose]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13, weight: .bold, design: .rounded)).padding(.leading, 6)
            HStack(spacing: 0) {
                ForEach(0..<poses.count, id: \.self) { i in
                    CritterView(species: species, coat: 0, pose: poses[i])
                        .frame(width: Design.width, height: Design.height)
                        .scaleEffect(0.62)
                        .frame(width: Design.width * 0.62, height: Design.height * 0.62)
                        .background((i % 2 == 0) ? Color(white: 0.92) : Color(white: 0.95))
                }
            }
        }
    }

    var body: some View {
        let walk = (0..<8).map { i in Pose(emotion: .happy, phase: 0.3, gait: Double(i) * .pi / 4, walk: 1) }
        let run = (0..<8).map { i in Pose(emotion: .playful, phase: 0.1 + Double(i) * 0.04, gait: Double(i) * .pi / 4, walk: 1, run: 1) }
        let hop = (0..<8).map { i in Pose(emotion: .excited, phase: Double(i) * 0.12) }
        let sit = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0].map { Pose(emotion: .happy, phase: 0.3, sit: $0) }
        let turn = [1.0, 0.6, 0.2, -0.2, -0.6, -1.0].map { Pose(emotion: .happy, phase: 0.3, facing: $0) }
        let eat = (0..<6).map { i in Pose(emotion: .eating, phase: Double(i) * 0.15) }
        let sleep = [0.0, 0.25, 0.5, 0.75, 1.0].map { Pose(emotion: .sleepy, phase: 0.6, sleep: $0) }
        let groom = (0..<6).map { i in Pose(emotion: .happy, phase: 0.05 + Double(i) * 0.075, sit: 1, groom: 1) }
        VStack(alignment: .leading, spacing: 6) {
            Text("\(species.displayName) · motion").font(.system(size: 18, weight: .bold, design: .rounded)).padding(.leading, 6)
            strip("walk cycle", walk)
            strip("run", run)
            strip("excited hop", hop)
            strip("sit down", sit)
            strip("turn around", turn)
            strip("eating", eat)
            strip("falling asleep", sleep)
            strip("face wash", groom)
        }
        .padding(8)
        .background(Color(white: 0.97))
    }
}


/// The floating cards: mood check-in, sticky note and chat drawer.
private struct CardsCheck: View {
    var body: some View {
        let pet = Pet()
        let chat = ChatState()
        let _ = (chat.pet = pet,
                 chat.messages = [
                    ChatMessage(role: .pet, text: "hi bestie, I'm Cariberry 🐾 ask me anything, or say “focus 25”"),
                    ChatMessage(role: .user, text: "can you explain photosynthesis like I'm five"),
                    ChatMessage(role: .pet, text: "plants eat sunlight like snacks 🌞 they mix it with water and air to make their own food, and breathe out the oxygen we need 🌿"),
                    ChatMessage(role: .user, text: "focus 25")])
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                MoodCheckInView(pet: pet) { _ in }
                StickyNoteView(mood: .cozy, text: "soft hours are productive hours too", extras: "lucky colour: lilac 💜 · lucky snack: strawberry mochi 🍓") {}
            }
            FloatingChatDrawer(chat: chat, pet: pet, onClose: {}, onStartBrain: {})
        }
        .padding(8)
        .background(Color(white: 0.8))
    }
}

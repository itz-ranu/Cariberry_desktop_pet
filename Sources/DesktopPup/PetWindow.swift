import AppKit
import SwiftUI

// MARK: - Panel

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Container view (hit testing + mouse)

final class PetContainerView: NSView {
    var onPress: ((NSPoint) -> Void)?
    var onDragMove: ((NSPoint, NSPoint) -> Void)?      // current, delta
    var onRelease: ((NSPoint, CGVector) -> Void)?
    var onScrub: ((CGFloat) -> Void)?                  // accumulated wiggle distance
    var onRightClick: ((NSEvent) -> Void)?

    private var pressOrigin: NSPoint = .zero
    private var lastPoint: NSPoint = .zero
    private var lastTime: TimeInterval = 0
    private var travelled: CGFloat = 0
    private var scrubBudget: CGFloat = 0
    private var carrying = false

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return Stage.hitRect.contains(local) ? self : nil
    }

    override func resetCursorRects() {
        addCursorRect(Stage.hitRect, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        pressOrigin = event.locationInWindow
        lastPoint = pressOrigin
        lastTime = event.timestamp
        travelled = 0
        scrubBudget = 0
        carrying = false
        onPress?(pressOrigin)
    }

    override func mouseDragged(with event: NSEvent) {
        let p = event.locationInWindow
        let d = CGVector(dx: p.x - lastPoint.x, dy: p.y - lastPoint.y)
        let step = hypot(d.dx, d.dy)
        travelled += step

        if !carrying && hypot(p.x - pressOrigin.x, p.y - pressOrigin.y) > 46 {
            carrying = true
            NSCursor.closedHand.push()
        }

        if carrying {
            onDragMove?(p, NSPoint(x: d.dx, y: d.dy))
        } else {
            scrubBudget += step
            if scrubBudget > 18 { scrubBudget = 0; onScrub?(travelled) }
        }
        lastPoint = p
        lastTime = event.timestamp
    }

    override func mouseUp(with event: NSEvent) {
        let p = event.locationInWindow
        if carrying {
            NSCursor.pop()
            let dt = max(0.008, event.timestamp - lastTime)
            let v = CGVector(dx: (p.x - lastPoint.x) / dt, dy: (p.y - lastPoint.y) / dt)
            onRelease?(p, v)
        } else {
            onScrub?(0)
        }
        carrying = false
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }
}

// MARK: - Controller

@MainActor
final class PetController {
    let pet: Pet
    private var panel: PetPanel!
    private var container: PetContainerView!
    private var timer: Timer?
    private var saveTimer: Timer?
    private var lastFrame = CACurrentMediaTime()
    private var carryGrabOffset: CGSize = .zero
    private var wasAway = false
    /// Called on right-click with the view and rect to anchor the control panel to.
    var openPanel: ((NSView, NSRect) -> Void)?
    private var lastScale = Stage.dogScale
    /// Her frames come from a cache of ready-made images (see Sprites.swift). `CARI_LIVE=1` draws her live instead.
    private let useSprites = ProcessInfo.processInfo.environment["CARI_LIVE"] == nil && !UserDefaults.standard.bool(forKey: "liveDrawing")
    private var sprite: PetSpriteView!
    private var lastSpriteKey: SpriteKey?
    private var spriteFailures = 0
    private var usingLive = false

    /// If a frame can't be made (it never should happen), she is drawn live instead of vanishing.
    private func fallBackToLive() {
        guard !usingLive else { return }
        usingLive = true
        sprite.isHidden = true
        let live = NSHostingView(rootView: LivePet(pet: pet))
        live.frame = NSRect(origin: .zero, size: Stage.size)
        live.autoresizingMask = [.width, .height]
        live.layer?.backgroundColor = .clear
        container.addSubview(live, positioned: .above, relativeTo: sprite)
    }

    init(pet: Pet) {
        self.pet = pet
    }

    func start() {
        buildWindow()
        pet.placeAtStart()
        syncWindow(force: true)
        panel.orderFrontRegardless()
        updateSprite()

        pet.onBark  = { [weak pet] in SoundKit.shared.bark(species: pet?.species ?? .dog, times: Int.random(in: 2...3)) }
        pet.onBell  = { SoundKit.shared.bell() }
        pet.onYip   = { [weak pet] in SoundKit.shared.yip(species: pet?.species ?? .dog) }
        pet.onMunch = { [weak pet] in SoundKit.shared.munch(species: pet?.species ?? .dog) }
        pet.onWhine = { [weak pet] in SoundKit.shared.whine(species: pet?.species ?? .dog) }

        pet.onNeedsSave = { [weak self] in self?.persist() }
        pet.refreshAmbience()
        scheduleTimer(pet.desiredFrameInterval)

        let s = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.persist() }
        }
        s.tolerance = 10
        RunLoop.main.add(s, forMode: .common)
        saveTimer = s

        // her eyes follow your cursor, so when it moves she needs lively frames at once, not at her next
        // slow tick. A global monitor only fires while the mouse is actually moving, and costs nothing at rest.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated { self?.cursorMoved() }
        }

        // how hard to ease off drawing: re-read a few times a minute, not per frame
        Throttle.refresh()
        let th = Timer(timeInterval: 8, repeats: true) { _ in MainActor.assumeIsolated { Throttle.refresh() } }
        th.tolerance = 4
        RunLoop.main.add(th, forMode: .common)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.pet.screensChanged()
                    self.pet.position.x = min(max(self.pet.position.x, self.pet.minX), self.pet.maxX)
                    if self.pet.perched { self.pet.restY = self.pet.clampY(self.pet.restY ?? 0) }
                    self.pet.position.y = self.pet.floorY
                }
            }

        // entrance: greeting matches the time of day
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            let greeting = Dialogue.greeting(self.pet.species, name: self.pet.name)
            self.pet.say(greeting, .excited, 5)
            self.pet.wave()
            self.pet.emit(.sparkle, count: 8, at: Stage.head, spread: 50)
            SoundKit.shared.happy(species: self.pet.species)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.8) { [weak self] in
            self?.pet.say("made with 💗 by Ranu", nil, 2.6)
        }
    }

    private func buildWindow() {
        let rect = NSRect(origin: .zero, size: Stage.size)
        panel = PetPanel(contentRect: rect,
                         styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        applyLevel()

        container = PetContainerView(frame: rect)
        container.autoresizingMask = [.width, .height]

        if useSprites {
            // behind her (room decor), her as a ready-made image, then everything that sits in front of her
            let back = NSHostingView(rootView: SceneView(pet: pet, layer: .back))
            back.frame = rect
            back.autoresizingMask = [.width, .height]
            back.layer?.backgroundColor = .clear
            container.addSubview(back)
            sprite = PetSpriteView(frame: rect)
            sprite.autoresizingMask = [.width, .height]
            container.addSubview(sprite)
            let front = NSHostingView(rootView: SceneView(pet: pet, layer: .front))
            front.frame = rect
            front.autoresizingMask = [.width, .height]
            front.layer?.backgroundColor = .clear
            container.addSubview(front)
        } else {
            let host = NSHostingView(rootView: SceneView(pet: pet))
            host.frame = rect
            host.autoresizingMask = [.width, .height]
            host.layer?.backgroundColor = .clear
            container.addSubview(host)
        }
        panel.contentView = container

        container.onPress = { [weak self] p in
            guard let self else { return }
            self.carryGrabOffset = CGSize(width: p.x - Stage.size.width / 2,
                                          height: p.y - Stage.pawInset)
        }
        container.onScrub = { [weak self] _ in self?.pet.petMe() }
        container.onDragMove = { [weak self] p, _ in
            guard let self else { return }
            if self.pet.act != .carried { self.pet.beginCarry() }
            let mouse = NSEvent.mouseLocation
            let newPos = CGPoint(x: mouse.x - self.carryGrabOffset.width,
                                 y: mouse.y - self.carryGrabOffset.height)
            self.pet.carry(to: newPos, velocity: .zero)
            _ = p
        }
        container.onRelease = { [weak self] _, v in
            self?.pet.drop(velocity: v)
        }
        container.onRightClick = { [weak self] _ in
            guard let self else { return }
            self.openPanel?(self.container, Stage.hitRect)
        }
    }

    func applyLevel() {
        panel.level = Prefs.aboveFullscreen ? .screenSaver : .floating
    }

    // MARK: Frame loop

    private var timerInterval: Double = 0

    private func scheduleTimer(_ interval: Double) {
        timer?.invalidate()
        timerInterval = interval
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.frame() }
        }
        t.tolerance = interval * 0.25      // lets the system batch her wake-ups with everyone else's
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private var awayCheckedAt: CFTimeInterval = 0
    private var mouseMonitor: Any?
    private var lastKick: CFTimeInterval = 0

    /// The cursor moved: if she is resting slowly, speed up so her eyes follow it.
    private func cursorMoved() {
        let now = CACurrentMediaTime()
        guard now - lastKick > 0.12 else { return }
        // her gaze stops changing once the cursor is far away, so only movement near her matters
        let m = NSEvent.mouseLocation, o = panel.frame.origin
        guard abs(m.x - (o.x + Stage.head.x)) < 420, abs(m.y - (o.y + Stage.size.height - Stage.head.y)) < 340 else { return }
        lastKick = now
        pet.attentionUntil = now + 1.4
        if timerInterval > 1.0 / 12 { scheduleTimer(1.0 / 12) }
    }

    private func frame() {
        let now = CACurrentMediaTime()
        let dt = now - lastFrame
        guard dt >= pet.desiredFrameInterval else { return }
        lastFrame = now

        if now - awayCheckedAt > 1 {
            awayCheckedAt = now
            checkAway()
        }
        if lastScale != Stage.dogScale {
            // she changed size: the clickable area moved with her
            lastScale = Stage.dogScale
            panel.invalidateCursorRects(for: container)
        }
        // a window nobody can see (covered by a full-screen app, another Space, a locked screen) needs no frames
        let hidden = !panel.occlusionState.contains(.visible)
        if hidden != pet.drawPaused { pet.drawPaused = hidden; if !hidden { pet.clock.frame &+= 1; lastSpriteKey = nil } }
        pet.cursor = NSEvent.mouseLocation
        updateLook()
        pet.tick(min(1.0, dt))
        syncWindow(force: false)
        updateSprite()

        let wanted = pet.desiredFrameInterval
        if wanted != timerInterval { scheduleTimer(wanted) }
    }

    /// Puts the frame she is in on screen: from the cache if she has been drawn like this before, drawn and kept
    /// if not. Nothing happens when the picture is the one already showing.
    private func updateSprite() {
        guard useSprites, !usingLive, !pet.drawPaused else { return }
        let backing = Int(panel.backingScaleFactor.rounded())
        let (snapped, key) = pet.pose.snapped(species: pet.species, coat: pet.coatIndex, scale: pet.scale, backing: backing)
        sprite.setResting(pet.species.stillWhenResting && snapped.isCalm(snapped), sleeping: snapped.sleep > 0.5)
        guard key != lastSpriteKey else { return }
        lastSpriteKey = key
        let scale = pet.scale
        if let image = SpriteCache.shared.image(for: key, render: {
            SpriteRenderer.render(species: pet.species, coat: pet.coatIndex, pose: snapped, scale: scale, backing: CGFloat(backing))
        }) {
            spriteFailures = 0
            sprite.show(image, backing: CGFloat(backing))
        } else {
            lastSpriteKey = nil
            spriteFailures += 1
            if spriteFailures >= 3 { fallBackToLive() }
        }
    }

    private func updateLook() {
        // while she's reaching for the Reels close button, she's looking at the
        // button, not the cursor — performCloseTap() drives `look` itself
        guard pet.act != .tap else { return }
        let mouse = NSEvent.mouseLocation
        let origin = panel.frame.origin
        let headScreen = CGPoint(x: origin.x + Stage.head.x,
                                 y: origin.y + (Stage.size.height - Stage.head.y))
        let dx = max(-1, min(1, (mouse.x - headScreen.x) / 260))
        let dy = max(-1, min(1, (headScreen.y - mouse.y) / 220))
        if abs(dx - pet.look.dx) > 0.04 || abs(dy - pet.look.dy) > 0.04 {
            pet.look = CGVector(dx: dx, dy: dy)
        }
        pet.nearCursor = hypot(mouse.x - headScreen.x, mouse.y - headScreen.y) < 130

        // turn to face the human's cursor while loafing
        if pet.act == .idle || pet.act == .sit {
            if abs(mouse.x - headScreen.x) > 90 {
                pet.facing = mouse.x > headScreen.x ? 1 : -1
            }
        }
    }

    private func checkAway() {
        let presence = Presence.shared
        let away = presence.idleSeconds > 240 || presence.screenOff
        if away != wasAway {
            wasAway = away
            pet.humanIsAway(away)
        }
    }

    private var lastOrigin: CGPoint = .init(x: -99999, y: -99999)

    private func syncWindow(force: Bool) {
        let o = CGPoint(x: pet.position.x - Stage.size.width / 2,
                        y: pet.position.y - Stage.pawInset)
        if force || abs(o.x - lastOrigin.x) > 0.25 || abs(o.y - lastOrigin.y) > 0.25 {
            panel.setFrameOrigin(o)
            lastOrigin = o
        }
    }

    // MARK: Persistence

    func persist() {
        Store.save(PetSave(name: pet.name,
                           hunger: pet.hunger,
                           happiness: pet.happiness,
                           energy: pet.energy,
                           affection: pet.affection,
                           totalFocusMinutes: pet.totalFocusMinutes,
                           treatsEaten: pet.treatsEaten,
                           barksGiven: pet.barksGiven,
                           born: pet.born,
                           siteTime: pet.siteTime,
                           dailyFocus: pet.dailyFocus,
                           categoryTime: pet.categoryTime,
                           xp: pet.xp,
                           lastXPDay: pet.lastXPDay,
                           dailyAppTime: pet.dailyAppTime,
                           timerEndsAt: pet.timerEndsAt,
                           timerIsBreak: pet.timerIsBreak,
                           timerTotal: pet.timerTotal,
                           tasks: pet.tasks,
                           dailySessions: pet.dailySessions,
                           dailyDistraction: pet.dailyDistraction,
                           dailyBarks: pet.dailyBarks,
                           dailyTasks: pet.dailyTasks,
                           berries: pet.berries,
                           owned: Array(pet.owned).sorted(),
                           moods: pet.moods,
                           dailyAway: pet.dailyAway,
                           focusByHour: pet.focusByHour,
                           siteKinds: pet.siteKinds))
        Prefs.petSpot = pet.spot
    }

    func callPetToCursor() {
        pet.cursor = NSEvent.mouseLocation
        pet.comeHere()
    }
}

import AppKit
import ServiceManagement
import SwiftUI

@main
struct DesktopPupApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let pet = Pet()
    let monitor = ActivityMonitor()
    var controller: PetController!
    var menuBar: MenuBarController!
    var cranberry: CranberryBridge!
    let chat = ChatState()
    var floating: FloatingWindows!
    let music = MusicBeatDetector()

    func applicationDidFinishLaunching(_ note: Notification) {
        // Dev helpers: `DesktopPup --render-sheet out.png [species]` and friends draw the art
        // to a PNG and quit, so it can be checked without launching the whole pet.
        let args = CommandLine.arguments
        if let flag = RenderSheet.flags.first(where: { args.contains($0) }) {
            _ = RenderSheet.run(flag: flag, args: args)
            NSApp.terminate(nil)
            return
        }

        // Dev helper: `DesktopPup --render-lofi outdir` writes each lo-fi station as a .wav
        // (and prints how long it took to compose), so the music can be checked by ear.
        if let i = args.firstIndex(of: "--render-lofi") {
            let dir = i + 1 < args.count ? args[i + 1] : NSTemporaryDirectory()
            for kind in Ambience.stations {
                let t0 = Date()
                guard let track = LoFi.render(kind) else { continue }
                let url = URL(fileURLWithPath: dir).appendingPathComponent("\(kind.rawValue).wav")
                try? LoFi.wav(track.samples).write(to: url)
                print("\(kind.rawValue): \(track.samples.count / 44_100)s, beat \(track.beatSeconds)s, composed in \(Date().timeIntervalSince(t0))s")
            }
            NSApp.terminate(nil)
            return
        }

        // Dev helper: `DesktopPup --render-voices dir` writes every synthesised voice as a .wav.
        if let i = args.firstIndex(of: "--render-voices") {
            let dir = i + 1 < args.count ? args[i + 1] : NSTemporaryDirectory()
            SoundKit.shared.exportVoices(to: URL(fileURLWithPath: dir))
            NSApp.terminate(nil)
            return
        }

        // Dev helper: play every species' voice in turn, so a sound change can be
        // checked by ear without launching the whole pet.
        if CommandLine.arguments.contains("--test-sounds") {
            var delay = 0.0
            for species in Species.allCases {
                for voice: (Species) -> Void in
                    [{ SoundKit.shared.bark(species: $0) },
                     { SoundKit.shared.yip(species: $0) },
                     { SoundKit.shared.whine(species: $0) },
                     { SoundKit.shared.munch(species: $0) },
                     { SoundKit.shared.happy(species: $0) }] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { voice(species) }
                    delay += 0.9
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 1) { NSApp.terminate(nil) }
            return
        }

        NSApp.setActivationPolicy(.accessory)

        let saved = Store.load()
        pet.name = Prefs.petName
        pet.species = Prefs.species
        pet.coatIndex = Prefs.coat(for: pet.species)
        pet.sizeLevel = Prefs.sizeLevel
        pet.outfit = Prefs.outfit
        pet.staying = Prefs.stay
        pet.hunger = saved.hunger
        pet.happiness = saved.happiness
        pet.energy = saved.energy
        pet.affection = saved.affection
        pet.totalFocusMinutes = saved.totalFocusMinutes
        pet.treatsEaten = saved.treatsEaten
        pet.barksGiven = saved.barksGiven
        pet.born = saved.born
        pet.siteTime = saved.siteTime
        pet.dailyFocus = saved.dailyFocus
        pet.categoryTime = saved.categoryTime
        pet.xp = saved.xp
        pet.lastXPDay = saved.lastXPDay
        pet.dailyAppTime = saved.dailyAppTime
        // Store.load() already dropped this if it would have finished while the app
        // was closed, so anything left here is a genuinely still-running timer to
        // resume exactly where it was
        pet.timerEndsAt = saved.timerEndsAt
        pet.timerIsBreak = saved.timerIsBreak
        pet.timerTotal = saved.timerTotal
        pet.tasks = saved.tasks
        pet.dailySessions = saved.dailySessions
        pet.dailyDistraction = saved.dailyDistraction
        pet.dailyBarks = saved.dailyBarks
        pet.dailyTasks = saved.dailyTasks
        pet.dailyAway = saved.dailyAway
        pet.focusByHour = saved.focusByHour
        pet.siteKinds = saved.siteKinds
        pet.owned = Set(saved.owned)
        pet.moods = saved.moods
        // the Sanctuary starts you off with a welcome gift, plus a berry for every focused
        // minute you'd already put in, so existing pets don't start from nothing
        pet.berries = saved.berries ?? (40 + Int(saved.totalFocusMinutes))
        pet.decorOn = Prefs.decorOn
        pet.ambience = Prefs.ambience

        _ = RuleStore.shared

        controller = PetController(pet: pet)
        controller.start()

        menuBar = MenuBarController(pet: pet, controller: controller, monitor: monitor)
        controller.openPanel = { [weak self] view, rect in
            self?.menuBar.showPanel(relativeTo: rect, of: view)
        }

        monitor.onVerdict = { [weak self] verdict, dt, idle in
            self?.pet.observe(verdict, dt: dt, idle: idle)
        }
        monitor.onPaused = { [weak self] in self?.pet.noteScreenOff() }
        pet.onCloseReelsTab = { [weak self] in
            self?.monitor.closeCurrentTab { [weak self] closed in
                guard closed, let pet = self?.pet else { return }
                pet.say(Dialogue.line(.closedTab, pet.species), .proud, 3)
                pet.emit(.sparkle, count: 6, at: Stage.aura, spread: 40)
            }
        }
        pet.onTapSound = { SoundKit.shared.click() }
        monitor.start()

        cranberry = CranberryBridge(pet: pet)
        cranberry.chat = chat
        cranberry.start()

        // the floating chat, mood card and sticky note
        chat.pet = pet
        chat.bridge = cranberry
        floating = FloatingWindows(pet: pet, chat: chat)
        floating.startBrain = { [weak self] in self?.menuBar.actions.startBrainIfNeeded() }
        menuBar.actions.floating = floating
        pet.onBadge = { [weak self] badge in self?.floating.showAchievement(badge) }
        menuBar.actions.bridge = cranberry

        // bop to the music, if she's been allowed to listen
        music.onBeat = { [weak self] strength in self?.pet.beat(strength: strength) }
        music.onFailure = { [weak self] why in
            Prefs.musicBop = false
            self?.pet.say(why, .worried, 7)
        }
        menuBar.actions.onMusicBopChanged = { [weak self] on in on ? self?.music.start() : self?.music.stop() }
        if Prefs.musicBop { music.start() }

        // Starting with the Mac is opt-in: it is off until the user turns on Settings ▸ Launch at login,
        // and that choice is then remembered.
        LaunchAtLogin.syncToStoredPreference()

        // once a day, a soft "how are we feeling?" (not on the very first launch: that has the
        // welcome tour, and she'll ask tomorrow)
        let firstRun = !Prefs.welcomed
        if !firstRun {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.askMoodIfNeeded() }
        }
        // ...and again if the app stays open past midnight
        Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.askMoodIfNeeded() }
        }

        // the first time she's ever opened, introduce her and let you choose who she is
        if !Prefs.welcomed {
            Prefs.welcomed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                self?.menuBar.showWelcome()
            }
        }
    }

    private func askMoodIfNeeded() {
        guard !Prefs.inQuietHours, pet.act != .sleep, !floating.chatIsOpen else { return }
        if pet.needsCheckIn { floating.showMoodCheckIn() } else { floating.showDailyNoteIfNeeded() }
    }

    func applicationWillTerminate(_ note: Notification) {
        music.stop()
        controller?.persist()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }
}

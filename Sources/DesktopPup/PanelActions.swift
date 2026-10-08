import AppKit
import SwiftUI

/// Everything the control panel can do. Kept apart from the view so the panel stays
/// declarative: a button just calls one of these.
@MainActor
final class PanelActions: ObservableObject {
    let pet: Pet
    private let controller: PetController?
    let monitor: ActivityMonitor

    @Published private(set) var cranberryRunning = false
    private var cranberryProcess: Process?
    private var statsWindow: NSWindow?

    /// The floating chat / mood / note windows: set by the app.
    var floating: FloatingWindows?
    var bridge: CranberryBridge?

    func openChat() { dismiss(); floating?.toggleChat() }
    /// Starts the Python brain if it isn't already running (the chat drawer offers this).
    func startBrainIfNeeded() { if !cranberryRunning { toggleCranberry() } }
    func openMoodCheckIn() { dismiss(); floating?.showMoodCheckIn() }
    func showNote() { dismiss(); floating?.showNote() }
    func showStory() { dismiss(); floating?.showStory() }
    func sendChatConfig() { bridge?.sendConfig() }
    func setMusicBop(_ on: Bool) {
        Prefs.musicBop = on
        pet.say(on ? "ooh, I'll bop along 🎧 (say yes to the audio permission)" : "okay, no more head bopping 🤫", .happy, 3.5)
        onMusicBopChanged?(on)
    }
    var onMusicBopChanged: ((Bool) -> Void)?

    /// Opens the macOS pane where a browser can be allowed to be controlled.
    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Closes the popover: set by `MenuBarController`.
    var dismiss: () -> Void = {}

    init(pet: Pet, controller: PetController?, monitor: ActivityMonitor) {
        self.pet = pet
        self.controller = controller
        self.monitor = monitor
    }

    // MARK: Care

    func feed() { pet.feed(); pet.touch() }
    func treat() { pet.feed(treat: true); pet.touch() }
    func play() { pet.play(); pet.touch() }
    func dance() { pet.dance(); pet.touch() }
    func toggleStay() { pet.toggleStay(); pet.touch() }
    func petIt() { pet.petMe(); pet.petMe(); pet.touch() }
    /// Closes the panel first, then calls her: the cursor is still on the button for a
    /// moment, so she waits until it's had time to move off.
    func come() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.controller?.callPetToCursor()
        }
    }
    func nap() {
        if pet.act == .sleep { pet.humanIsAway(false) } else { pet.nap() }
        pet.touch()
    }

    // MARK: Timer

    func startTimer(_ minutes: Double) { pet.startTimer(minutes: min(max(1, minutes), 240)) }
    /// Starts a focus session on whatever she's been told you're working on.
    func startFocus(_ minutes: Double) { pet.startFocus(minutes: min(max(1, minutes), 240), intention: pet.intention) }
    func stopTimer() { pet.stopTimer() }

    // MARK: Preferences that need a side effect

    func setSounds(_ on: Bool) {
        Prefs.sounds = on
        pet.refreshAmbience()
        if on { SoundKit.shared.yip(species: pet.species) }
    }

    func setAboveFullscreen(_ on: Bool) {
        Prefs.aboveFullscreen = on
        controller?.applyLevel()
    }

    func setRoams(_ on: Bool) {
        Prefs.roams = on
        if on {
            pet.say("time to explore again! 🐾", .happy, 3)
        } else {
            pet.stayPut()
            pet.say("okay, staying right here 🐾", .neutral, 3)
        }
    }

    func setBrowserAwareness(_ on: Bool) {
        Prefs.browserAwareness = on
        pet.say(on ? "sniffing your tabs now 👃 (say yes to the macOS prompt)" : "ok, tabs are private 🙈",
                on ? .alert : .neutral, on ? 6 : 3)
    }

    func setAutoClose(_ on: Bool) {
        Prefs.autoCloseReels = on
        pet.say(on ? "one warning, then I'll jump up and close the tab myself 😤🐾" : Dialogue.flavor("ok, I'll just bark from now on 🐾", pet.species),
                on ? .alert : .neutral, on ? 5 : 3)
    }

    func setQuietHours(_ on: Bool) {
        Prefs.quietHoursEnabled = on
        pet.say(on ? "quiet hours on 🌙 I'll stay soft \(Self.clock(Prefs.quietHoursStart))–\(Self.clock(Prefs.quietHoursEnd))"
                   : "quiet hours off, back to full volume 🐾", .neutral, 4)
    }

    func setLaunchAtLogin(_ on: Bool) { LaunchAtLogin.set(on) }

    static func clock(_ hour: Int) -> String {
        let h = hour % 24
        let h12 = h % 12 == 0 ? 12 : h % 12
        return "\(h12)\(h < 12 ? "am" : "pm")"
    }

    // MARK: Rules

    func block(_ raw: String) {
        let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        RuleStore.shared.addBlock(term)
        pet.say("\(term) is BANNED now 😤 don't test me", .angry, 4)
        pet.onBark?()
    }

    func editRules() {
        RuleStore.shared.save()
        NSWorkspace.shared.open(RuleStore.shared.url)
        pet.say("edit the file, then hit Reload 📝", .alert, 5)
    }

    func reloadRules() {
        RuleStore.shared.load()
        pet.say("new rules learned! 🐾", .excited, 3)
        SoundKit.shared.happy(species: pet.species)
    }

    func resetRules() {
        RuleStore.shared.writeDefaults()
        pet.say("back to my default instincts 🐾", .neutral, 3)
    }

    func undoLastClose() {
        monitor.undoLastClose()
        pet.say("brought it back 🐾", .shy, 2.5)
    }

    func rename(_ raw: String) {
        let n = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, n != pet.name else { return }
        pet.name = n
        Prefs.petName = n
        pet.say("I'm \(n)! \(pet.species.emoji)", .excited, 3)
        controller?.persist()
    }

    // MARK: Windows & apps

    func showStats() {
        dismiss()
        if let existing = statsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: StatsView.width, height: 820),
                           styleMask: [.titled, .closable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        win.title = "\(pet.name)'s Stats"
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        // We keep our own strong reference to reopen it later. Without this, closing the
        // window over-releases it on top of that and the next open crashes.
        win.isReleasedWhenClosed = false
        win.contentView = NSHostingView(rootView: StatsView(pet: pet))
        win.center()
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                               object: win, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.statsWindow = nil }
        }
        statsWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Launches (or stops) the separate `cranberry/` Python service, so reaching its
    /// chat window never needs a terminal. `run_cranberry.sh` lives in the source
    /// checkout, not the app bundle, so its path is baked into Info.plist by build.sh.
    func toggleCranberry() {
        if let running = cranberryProcess, running.isRunning {
            running.terminate()
            cranberryProcess = nil
            cranberryRunning = false
            return
        }
        let process = Process()
        // Installed from the .dmg: the voice assistant ships inside the app as a compiled
        // program, so there's no Python, no terminal and no setup. Running from a source
        // checkout: fall back to run_cranberry.sh.
        let bundled = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("cranberry")
        if let bundled, FileManager.default.isExecutableFile(atPath: bundled.path) {
            process.executableURL = bundled
        } else {
            guard let projectPath = Bundle.main.object(forInfoDictionaryKey: "CranberryProjectPath") as? String else {
                pet.say("my voice assistant isn't installed in this copy 😟 try the latest download", .worried, 4)
                return
            }
            let script = "\(projectPath)/run_cranberry.sh"
            guard FileManager.default.fileExists(atPath: script) else {
                pet.say("run_cranberry.sh is missing from \(projectPath) 😟", .worried, 4)
                return
            }
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script]
        }
        let logPath = NSTemporaryDirectory() + "cranberry.log"
        FileManager.default.createFile(atPath: logPath, contents: nil)
        if let handle = FileHandle(forWritingAtPath: logPath) {
            process.standardOutput = handle
            process.standardError = handle
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                if self?.cranberryProcess === process {
                    self?.cranberryProcess = nil
                    self?.cranberryRunning = false
                }
            }
        }
        do {
            try process.run()
            cranberryProcess = process
            cranberryRunning = true
            pet.say("waking Cranberry up... 🐾", .curious, 4)
        } catch {
            pet.say("couldn't start Cranberry: \(error.localizedDescription) 😟", .worried, 4)
        }
    }

    func quit() {
        controller?.persist()
        NSApp.terminate(nil)
    }
}

import AppKit
import SwiftUI

/// The menu bar icon and the control panel it opens. There is deliberately no menu:
/// one click opens a single panel with everything in it (see `PanelView`). Right-clicking
/// the pet opens the same panel beside her.
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let pet: Pet
    private let monitor: ActivityMonitor
    let actions: PanelActions
    private var item: NSStatusItem!
    private var refresh: Timer?
    private let popover = NSPopover()

    init(pet: Pet, controller: PetController, monitor: ActivityMonitor) {
        self.pet = pet
        self.monitor = monitor
        self.actions = PanelActions(pet: pet, controller: controller, monitor: monitor)
        super.init()

        popover.behavior = .transient          // clicking anywhere else closes it
        popover.appearance = NSAppearance(named: .aqua)   // the panel is a light, pastel design
        popover.delegate = self
        popover.contentSize = NSSize(width: PanelView.width, height: PanelView.height)
        actions.dismiss = { [weak self] in self?.popover.performClose(nil) }

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        item.button?.toolTip = "\(pet.name): click for everything"

        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateTitle() }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        refresh = t
        updateTitle()
    }

    private var lastIconKey = ""

    /// Her actual face in the menu bar, redrawn only when it would look different.
    private func updateIcon() {
        let key = "\(pet.species.rawValue)-\(pet.coatIndex)-\(pet.emotion.rawValue)-\(pet.outfit.head.rawValue)\(pet.outfit.face.rawValue)"
        guard key != lastIconKey else { return }
        lastIconKey = key
        // a neutral face reads as blank at this size, so it borrows a smile
        let mood: Emotion = (pet.emotion == .neutral || pet.emotion == .alert) ? .happy : pet.emotion
        let s: CGFloat = 0.155
        let face = CritterView(species: pet.species, coat: pet.coatIndex,
                               pose: Pose(emotion: mood, phase: 0.4, outfit: Outfit(head: pet.outfit.head, face: pet.outfit.face)),
                               scale: s)
            .offset(x: 10 - 116 * s, y: 11 - 96 * s)
            .frame(width: 20, height: 20, alignment: .topLeading)
            .clipped()
        let renderer = ImageRenderer(content: face)
        renderer.scale = 3
        if let img = renderer.nsImage {
            img.isTemplate = false
            item.button?.image = img
            item.button?.imagePosition = .imageLeft
        }
    }

    private func updateTitle() {
        updateIcon()
        var title = ""
        if let left = pet.timerRemaining {
            let m = Int(left) / 60, s = Int(left) % 60
            title = (pet.onBreak ? "☕️ " : "") + "\(m):\(String(format: "%02d", s))"
        } else if pet.lastVerdict == .work && pet.focusSeconds > 60 {
            title = "\(Int(pet.focusSeconds / 60))m"
        } else if pet.lastVerdict == .distraction && pet.distractSeconds > 15 {
            title = "👀"
        }
        if !title.isEmpty { title = " " + title }
        if item.button?.title != title { item.button?.title = title }
    }

    // MARK: Panel

    @objc private func togglePanel() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = item.button else { return }
        present(relativeTo: button.bounds, of: button, edge: .minY)
    }

    /// First launch: opens straight onto the Pets tab so the very first thing she does is
    /// let you choose who she is.
    func showWelcome() {
        guard !popover.isShown, let button = item.button else { return }
        present(relativeTo: button.bounds, of: button, edge: .minY, tab: .closet, welcome: true)
    }

    /// Opens the panel next to her: used by right-click on the pet.
    func showPanel(relativeTo rect: NSRect, of view: NSView) {
        if popover.isShown { popover.performClose(nil); return }
        present(relativeTo: rect, of: view, edge: .maxY)
    }

    private func present(relativeTo rect: NSRect, of view: NSView, edge: NSRectEdge,
                         tab: PanelView.Tab = .home, welcome: Bool = false) {
        // a fresh view each time, so it always opens on Home with current values
        popover.contentViewController = NSHostingController(
            rootView: PanelView(pet: pet, actions: actions, startTab: tab, welcome: welcome))
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        pet.holdStill = true
        // text fields in the panel need the app active to take typing
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: rect, of: view, preferredEdge: edge)
    }

    func popoverDidClose(_ notification: Notification) {
        pet.holdStill = false
    }
}

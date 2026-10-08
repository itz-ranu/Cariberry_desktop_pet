import AppKit
import Foundation

/// Observes human user activity and returns a status evaluation periodically.
@MainActor
final class ActivityMonitor {

    static let browsers: [String: String] = [
        "com.apple.safari": "Safari",
        "com.google.chrome": "Google Chrome",
        "com.google.chrome.canary": "Google Chrome Canary",
        "company.thebrowser.browser": "Arc",
        "com.brave.browser": "Brave Browser",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.vivaldi.vivaldi": "Vivaldi",
        "com.operasoftware.opera": "Opera",
        "com.kagi.kagimacos": "Orion",
    ]

    /// (what you're doing, seconds since the last look, seconds since you last touched anything)
    var onVerdict: ((Verdict, Double, Double) -> Void)?
    /// The screen is locked or the Mac is asleep: nothing to watch, nothing to count.
    var onPaused: (() -> Void)?
    private var lastSampleAt: Date?
    private(set) var lastPage: String = ""
    private(set) var lastTitle: String = ""
    private(set) var automationDenied = false

    private var timer: Timer?
    private let interval: Double = 2.0
    private let queue = DispatchQueue(label: "pup.applescript")
    private let probe = BrowserProbe()
    private var querying = false
    private var queryGeneration = 0
    private var lastBrowserBundle = ""

    func start() {
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
        sample()
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func sample() {
        // Measure the real time since the last look instead of assuming the timer fired on the
        // dot. After a sleep, a stalled run loop or the very first look, the gap isn't time she
        // actually watched, so it counts for nothing.
        let now = Date()
        let gap = lastSampleAt.map { now.timeIntervalSince($0) } ?? 0
        lastSampleAt = now
        let dt = (gap > 0 && gap <= interval * 3) ? gap : 0

        guard Prefs.focusCoaching else { return }
        if Presence.shared.screenOff { onPaused?(); return }
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        let bundle = (front.bundleIdentifier ?? "").lowercased()
        let appName = front.localizedName ?? "something"

        // Exclude our own application from monitoring.
        if bundle == (Bundle.main.bundleIdentifier ?? "com.desktoppup.app").lowercased() { return }

        if let _ = ActivityMonitor.browsers[bundle] {
            if Prefs.browserAwareness {
                if bundle != lastBrowserBundle { lastPage = ""; lastTitle = "" }
                lastBrowserBundle = bundle
                queryBrowser(bundle: bundle)
            } else {
                lastPage = ""; lastTitle = ""
            }
        } else {
            lastPage = ""; lastTitle = ""
            lastBrowserBundle = ""
        }

        let verdict = RuleStore.shared.evaluate(bundle: bundle, appName: appName,
                                                url: lastPage, title: lastTitle)
        onVerdict?(verdict, dt, Presence.shared.idleSeconds)
    }

    // MARK: AppleScript

    private func queryBrowser(bundle: String) {
        guard !querying else { return }
        guard let source = script(for: bundle) else { return }
        querying = true
        queryGeneration += 1
        let generation = queryGeneration
        let probe = self.probe
        queue.async { [weak self] in
            let (text, denied, _) = probe.run(bundle: bundle, source: source)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    // a stale completion from a query the timeout below already gave
                    // up on shouldn't clobber whatever's happened since
                    guard let self, self.queryGeneration == generation else { return }
                    self.querying = false
                    if denied { self.automationDenied = true; return }
                    guard !text.isEmpty else { return }
                    self.automationDenied = false
                    let parts = text.components(separatedBy: "\u{241F}")
                    self.lastPage = parts.first?.lowercased() ?? ""
                    self.lastTitle = parts.count > 1 ? parts[1] : ""
                }
            }
        }
        // NSAppleScript has no cancellation API, so a hung/beachballed browser can
        // block `probe.run` indefinitely. Without this, `querying` would stay true
        // forever and every future poll would silently no-op until the app restarts.
        // The generation check means this can't stomp on a newer query that started
        // after this one finally did (or never) return.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.queryGeneration == generation else { return }
            self.querying = false
        }
    }

    // MARK: Closing a tab

    /// Closes whatever tab is currently active in the last browser she saw you in.
    /// Uses the browser's own "close this tab" AppleScript command rather than
    /// simulating a click on the visual close button: a simulated click has to guess
    /// a screen coordinate that shifts with tab count, window size and Retina
    /// scaling, and can miss onto whatever else happens to be under that pixel. This
    /// targets the actual tab object, so it can't misfire onto the wrong thing.
    func closeCurrentTab(completion: @escaping (Bool) -> Void) {
        guard Prefs.browserAwareness, !lastBrowserBundle.isEmpty,
              let source = closeScript(for: lastBrowserBundle) else {
            completion(false)
            return
        }
        // captured before the close fires, so `undo()` has something to reopen —
        // closing a tab is destructive, so every auto-close leaves a way back
        let closingBundle = lastBrowserBundle
        let closingURL = lastPage
        let closingTitle = lastTitle
        let probe = self.probe
        // a distinct cache key from the read-probe's, so the two scripts (read vs.
        // close) for the same browser never collide in BrowserProbe's cache
        let cacheKey = "close:" + lastBrowserBundle
        queue.async { [weak self] in
            let (_, denied, ok) = probe.run(bundle: cacheKey, source: source)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let success = ok && !denied
                    if success, !closingURL.isEmpty {
                        self?.lastClosedTab = (url: closingURL, title: closingTitle,
                                                bundle: closingBundle, closedAt: Date())
                    }
                    completion(success)
                }
            }
        }
    }

    /// What she just auto-closed, so long as it's still within the undo window —
    /// `nil` once too much time has passed or nothing's been undone yet.
    private(set) var lastClosedTab: (url: String, title: String, bundle: String, closedAt: Date)?
    private let undoWindow: TimeInterval = 45

    /// A short label for the "Reopen …" menu item, or nil if there's nothing
    /// (recent enough) to offer undoing.
    var undoLabel: String? {
        guard let last = lastClosedTab, Date().timeIntervalSince(last.closedAt) < undoWindow else { return nil }
        return last.title.isEmpty ? last.url : last.title
    }

    /// Reopens whatever tab was last auto-closed, as a new tab in the same browser.
    /// Best-effort: if the browser's since quit or the window's gone, this just
    /// silently does nothing rather than erroring.
    func undoLastClose() {
        guard let last = lastClosedTab, undoLabel != nil,
              let source = reopenScript(for: last.bundle, url: last.url) else { return }
        lastClosedTab = nil
        let probe = self.probe
        queue.async {
            _ = probe.run(bundle: "reopen:" + last.bundle, source: source)
        }
    }

    private func reopenScript(for bundle: String, url: String) -> String? {
        // URLs from `lastPage` never contain a literal quote in practice, but escape
        // defensively anyway since this string gets spliced straight into AppleScript
        let escaped = url.replacingOccurrences(of: "\"", with: "\\\"")
        if bundle == "com.apple.safari" {
            return """
            tell application id "com.apple.Safari"
                if (count of windows) is 0 then make new document
                tell front window to make new tab with properties {URL:"\(escaped)"}
            end tell
            """
        }
        guard let name = ActivityMonitor.browsers[bundle] else { return nil }
        return """
        tell application "\(name)"
            if (count of windows) is 0 then make new window
            tell front window to make new tab with properties {URL:"\(escaped)"}
        end tell
        """
    }

    private func closeScript(for bundle: String) -> String? {
        if bundle == "com.apple.safari" {
            return """
            tell application id "com.apple.Safari"
                if (count of windows) is 0 then return
                close current tab of front window
            end tell
            """
        }
        guard let name = ActivityMonitor.browsers[bundle] else { return nil }
        return """
        tell application "\(name)"
            if (count of windows) is 0 then return
            close active tab of front window
        end tell
        """
    }

    private func script(for bundle: String) -> String? {
        let sep = "\u{241F}"
        if bundle == "com.apple.safari" {
            return """
            tell application id "com.apple.Safari"
                if (count of windows) is 0 then return ""
                set theURL to URL of front document
                set theName to name of front document
                return theURL & "\(sep)" & theName
            end tell
            """
        }
        guard let name = ActivityMonitor.browsers[bundle] else { return nil }
        return """
        tell application "\(name)"
            if (count of windows) is 0 then return ""
            set t to active tab of front window
            return (URL of t) & "\(sep)" & (title of t)
        end tell
        """
    }
}

/// Manages the compilation state of AppleScripts. Because compilation is expensive,
/// scripts for each supported browser are built only once and retained in memory.
/// This object is strictly accessed from within ActivityMonitor's serial dispatch queue.
private final class BrowserProbe: @unchecked Sendable {
    private var cache: [String: NSAppleScript] = [:]

    func run(bundle: String, source: String) -> (text: String, denied: Bool, ok: Bool) {
        let script: NSAppleScript
        if let cached = cache[bundle] {
            script = cached
        } else {
            guard let fresh = NSAppleScript(source: source) else { return ("", false, false) }
            var compileError: NSDictionary?
            fresh.compileAndReturnError(&compileError)
            cache[bundle] = fresh
            script = fresh
        }
        var err: NSDictionary?
        let result = script.executeAndReturnError(&err)
        let code = err?[NSAppleScript.errorNumber] as? Int
        return (result.stringValue ?? "", code == -1743 || code == -1728, err == nil)
    }
}


/// Whether you're actually at your Mac: how long since you touched the keyboard or mouse, and
/// whether the screen is locked or the machine asleep. Cheap to ask, so she can check often.
@MainActor
final class Presence {
    static let shared = Presence()

    private(set) var screenOff = false

    var idleSeconds: Double {
        let types: [CGEventType] = [.mouseMoved, .keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel, .leftMouseDragged, .flagsChanged]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }

    private init() {
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.screenOff = true }
            }
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.screenOff = false }
            }
        }
        let dc = DistributedNotificationCenter.default()
        dc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenOff = true }
        }
        dc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenOff = false }
        }
    }
}

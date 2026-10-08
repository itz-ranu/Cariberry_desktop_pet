import Foundation
import OSLog

private let storeLogger = Logger(subsystem: "com.desktoppup.cariberry", category: "storage")

struct PetSave: Codable {
    var name = "Cariberry"
    var hunger = 0.85
    var happiness = 0.8
    var energy = 0.9
    var affection = 0.5
    var totalFocusMinutes = 0.0
    var treatsEaten = 0
    var barksGiven = 0
    var born = Date()
    var lastSeen = Date()
    var siteTime: [String: Double] = [:]
    var dailyFocus: [Date: Double] = [:]   // start-of-day -> minutes focused that day
    var categoryTime: [String: Double] = [:]   // rule name -> seconds, every kind included
    var xp = 0.0                               // lifetime XP; level is derived from it
    var lastXPDay = Date.distantPast           // so the daily bonus lands once a day
    /// start-of-day -> domain/app -> seconds spent, every app, every kind included:
    /// see the comment on `Pet.dailyAppTime` for why this exists alongside siteTime.
    var dailyAppTime: [Date: [String: Double]] = [:]
    // a running focus timer used to just vanish on quit/relaunch with no trace it
    // ever existed. persisting these three lets Store.load() resume it if it's
    // still genuinely in progress, or quietly drop it if time has already run out.
    var timerEndsAt: Date? = nil
    var timerIsBreak = false
    var timerTotal: Double = 0
    var tasks: [FocusTask] = []                // her to-do list
    var dailySessions: [Date: Int] = [:]       // start-of-day -> finished focus sessions
    var dailyDistraction: [Date: Double] = [:] // start-of-day -> seconds spent on things she barked about
    var dailyBarks: [Date: Int] = [:]          // start-of-day -> times she told you off
    var dailyTasks: [Date: Int] = [:]          // start-of-day -> to-dos finished
    var berries: Int? = nil                    // the Sanctuary currency (nil = never had any: see App)
    var owned: [String] = []                   // Sanctuary items bought
    var moods: [Date: String] = [:]            // start-of-day -> how you said you felt
    var dailyAway: [Date: Double] = [:]        // start-of-day -> seconds you were at the computer but idle
    var focusByHour: [Int: Double] = [:]       // hour of day (0...23) -> lifetime focused minutes
    var siteKinds: [String: String] = [:]      // app/site -> "work" | "distraction" | "neutral", as last seen

    init(name: String = "Cariberry", hunger: Double = 0.85, happiness: Double = 0.8,
         energy: Double = 0.9, affection: Double = 0.5, totalFocusMinutes: Double = 0,
         treatsEaten: Int = 0, barksGiven: Int = 0, born: Date = Date(), lastSeen: Date = Date(),
         siteTime: [String: Double] = [:], dailyFocus: [Date: Double] = [:],
         categoryTime: [String: Double] = [:], xp: Double = 0,
         lastXPDay: Date = .distantPast, dailyAppTime: [Date: [String: Double]] = [:],
         timerEndsAt: Date? = nil, timerIsBreak: Bool = false, timerTotal: Double = 0,
         tasks: [FocusTask] = [], dailySessions: [Date: Int] = [:],
         dailyDistraction: [Date: Double] = [:], dailyBarks: [Date: Int] = [:], dailyTasks: [Date: Int] = [:],
         berries: Int? = nil, owned: [String] = [], moods: [Date: String] = [:],
         dailyAway: [Date: Double] = [:], focusByHour: [Int: Double] = [:], siteKinds: [String: String] = [:]) {
        self.name = name
        self.hunger = hunger
        self.happiness = happiness
        self.energy = energy
        self.affection = affection
        self.totalFocusMinutes = totalFocusMinutes
        self.treatsEaten = treatsEaten
        self.barksGiven = barksGiven
        self.born = born
        self.lastSeen = lastSeen
        self.siteTime = siteTime
        self.dailyFocus = dailyFocus
        self.categoryTime = categoryTime
        self.xp = xp
        self.lastXPDay = lastXPDay
        self.dailyAppTime = dailyAppTime
        self.timerEndsAt = timerEndsAt
        self.timerIsBreak = timerIsBreak
        self.timerTotal = timerTotal
        self.tasks = tasks
        self.dailySessions = dailySessions
        self.dailyDistraction = dailyDistraction
        self.dailyBarks = dailyBarks
        self.dailyTasks = dailyTasks
        self.berries = berries
        self.owned = owned
        self.moods = moods
        self.dailyAway = dailyAway
        self.focusByHour = focusByHour
        self.siteKinds = siteKinds
    }

    // A plain `Codable` struct fails to decode its *entire* save the moment one field
    // is missing: which happens every time a new field is added, wiping everything
    // back to defaults. Decode each field on its own instead, so adding a field later
    // never costs anyone their save again.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Cariberry"
        hunger = try c.decodeIfPresent(Double.self, forKey: .hunger) ?? 0.85
        happiness = try c.decodeIfPresent(Double.self, forKey: .happiness) ?? 0.8
        energy = try c.decodeIfPresent(Double.self, forKey: .energy) ?? 0.9
        affection = try c.decodeIfPresent(Double.self, forKey: .affection) ?? 0.5
        totalFocusMinutes = try c.decodeIfPresent(Double.self, forKey: .totalFocusMinutes) ?? 0
        treatsEaten = try c.decodeIfPresent(Int.self, forKey: .treatsEaten) ?? 0
        barksGiven = try c.decodeIfPresent(Int.self, forKey: .barksGiven) ?? 0
        born = try c.decodeIfPresent(Date.self, forKey: .born) ?? Date()
        lastSeen = try c.decodeIfPresent(Date.self, forKey: .lastSeen) ?? Date()
        siteTime = try c.decodeIfPresent([String: Double].self, forKey: .siteTime) ?? [:]
        dailyFocus = try c.decodeIfPresent([Date: Double].self, forKey: .dailyFocus) ?? [:]
        categoryTime = try c.decodeIfPresent([String: Double].self, forKey: .categoryTime) ?? [:]
        xp = try c.decodeIfPresent(Double.self, forKey: .xp) ?? 0
        lastXPDay = try c.decodeIfPresent(Date.self, forKey: .lastXPDay) ?? .distantPast
        dailyAppTime = try c.decodeIfPresent([Date: [String: Double]].self, forKey: .dailyAppTime) ?? [:]
        timerEndsAt = try c.decodeIfPresent(Date.self, forKey: .timerEndsAt)
        timerIsBreak = try c.decodeIfPresent(Bool.self, forKey: .timerIsBreak) ?? false
        timerTotal = try c.decodeIfPresent(Double.self, forKey: .timerTotal) ?? 0
        tasks = try c.decodeIfPresent([FocusTask].self, forKey: .tasks) ?? []
        dailySessions = try c.decodeIfPresent([Date: Int].self, forKey: .dailySessions) ?? [:]
        dailyDistraction = try c.decodeIfPresent([Date: Double].self, forKey: .dailyDistraction) ?? [:]
        dailyBarks = try c.decodeIfPresent([Date: Int].self, forKey: .dailyBarks) ?? [:]
        dailyTasks = try c.decodeIfPresent([Date: Int].self, forKey: .dailyTasks) ?? [:]
        berries = try c.decodeIfPresent(Int.self, forKey: .berries)
        owned = try c.decodeIfPresent([String].self, forKey: .owned) ?? []
        moods = try c.decodeIfPresent([Date: String].self, forKey: .moods) ?? [:]
        dailyAway = try c.decodeIfPresent([Date: Double].self, forKey: .dailyAway) ?? [:]
        focusByHour = try c.decodeIfPresent([Int: Double].self, forKey: .focusByHour) ?? [:]
        siteKinds = try c.decodeIfPresent([String: String].self, forKey: .siteKinds) ?? [:]
    }
}

enum Store {
    static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("DesktopPup", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static var saveURL: URL { dir.appendingPathComponent("pet.json") }

    static func load() -> PetSave {
        guard FileManager.default.fileExists(atPath: saveURL.path) else { return PetSave() }
        do {
            let data = try Data(contentsOf: saveURL)
            var s = try JSONDecoder().decode(PetSave.self, from: data)
            // The pup keeps living while the app is closed: it gets hungrier, but rests.
            let away = Date().timeIntervalSince(s.lastSeen)
            s.hunger = max(0, s.hunger - away / (60 * 60 * 6))
            s.energy = min(1, s.energy + away / (60 * 60 * 3))
            s.happiness = max(0.15, s.happiness - away / (60 * 60 * 24))

            // streaks need history, but not forever: keep four months of daily totals,
            // and only the last month of the heavier per-app breakdown
            if let cutoff = Calendar.current.date(byAdding: .day, value: -120, to: Date()),
               let appCutoff = Calendar.current.date(byAdding: .day, value: -60, to: Date()) {
                s.dailyFocus = s.dailyFocus.filter { $0.key >= cutoff }
                s.dailySessions = s.dailySessions.filter { $0.key >= cutoff }
                s.dailyDistraction = s.dailyDistraction.filter { $0.key >= cutoff }
                s.dailyBarks = s.dailyBarks.filter { $0.key >= cutoff }
                s.dailyTasks = s.dailyTasks.filter { $0.key >= cutoff }
                s.dailyAway = s.dailyAway.filter { $0.key >= cutoff }
                s.dailyAppTime = s.dailyAppTime.filter { $0.key >= appCutoff }
            }

            // a timer that would already be over by now doesn't get resumed or
            // retroactively "finished" (that would fire its celebration/break-chaining
            // the moment the app opens, using nudge timing from a session that's long
            // gone) — it just quietly wasn't running
            if let end = s.timerEndsAt, end <= Date() {
                s.timerEndsAt = nil
                s.timerIsBreak = false
                s.timerTotal = 0
            }
            return s
        } catch {
            storeLogger.error("Could not load save file: \(error.localizedDescription, privacy: .public)")
            return PetSave()
        }
    }

    static func save(_ s: PetSave) {
        var s = s
        s.lastSeen = Date()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try enc.encode(s)
            try data.write(to: saveURL, options: .atomic)
        } catch {
            storeLogger.error("Could not save pet data: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Simple UserDefaults-backed toggles.
enum Prefs {
    private static let d = UserDefaults.standard

    private static func bool(_ key: String, _ fallback: Bool) -> Bool {
        d.object(forKey: key) == nil ? fallback : d.bool(forKey: key)
    }

    static var focusCoaching: Bool {
        get { bool("focusCoaching", true) }
        set { d.set(newValue, forKey: "focusCoaching") }
    }
    static var browserAwareness: Bool {
        get { bool("browserAwareness", false) }
        set { d.set(newValue, forKey: "browserAwareness") }
    }
    /// Off by default: closing a tab is destructive (lost scroll position, an
    /// unsubmitted form, whatever was on it), so unlike barking it needs a
    /// deliberate opt-in, not just Browser awareness being on.
    static var autoCloseReels: Bool {
        get { bool("autoCloseReels", false) }
        set { d.set(newValue, forKey: "autoCloseReels") }
    }
    static var sounds: Bool {
        get { bool("sounds", true) }
        set { d.set(newValue, forKey: "sounds") }
    }
    static var aboveFullscreen: Bool {
        get { bool("aboveFullscreen", false) }
        set { d.set(newValue, forKey: "aboveFullscreen") }
    }
    static var roams: Bool {
        get { bool("roams", true) }
        set { d.set(newValue, forKey: "roams") }
    }
    static var petName: String {
        get { d.string(forKey: "petName") ?? "Cariberry" }
        set { d.set(newValue, forKey: "petName") }
    }
    static var species: Species {
        get { Species(rawValue: d.string(forKey: "species") ?? "") ?? .panda }
        set { d.set(newValue.rawValue, forKey: "species") }
    }
    /// Which colourway she wears, remembered per species so switching back is painless.
    static func coat(for s: Species) -> Int {
        // a new pet is a Cocoa panda: the panda's second colourway
        if d.object(forKey: "coat.\(s.rawValue)") == nil { return s == .panda ? min(1, s.coats.count - 1) : 0 }
        return min(max(0, d.integer(forKey: "coat.\(s.rawValue)")), s.coats.count - 1)
    }
    static func setCoat(_ i: Int, for s: Species) { d.set(i, forKey: "coat.\(s.rawValue)") }
    /// "Stay": she sits right where she is until you let her roam again.
    static var stay: Bool {
        get { d.bool(forKey: "stay") }
        set { d.set(newValue, forKey: "stay") }
    }

    // MARK: Placement
    /// On (default): wherever she's dropped is where she stays, on a cushion. Off: she
    /// always falls back to the floor.
    static var placeAnywhere: Bool {
        get { bool("placeAnywhere", true) }
        set { d.set(newValue, forKey: "placeAnywhere") }
    }
    /// Last resting spot: x, and y (or -1 for the floor), so she's where you left her.
    static var petSpot: (x: Double, y: Double)? {
        get {
            guard let a = d.array(forKey: "petSpot") as? [Double], a.count == 2 else { return nil }
            return (a[0], a[1])
        }
        set { d.set(newValue.map { [$0.x, $0.y] }, forKey: "petSpot") }
    }

    // MARK: Focus
    static var dailyGoal: Int {
        get { d.object(forKey: "dailyGoal") == nil ? 60 : min(480, max(10, d.integer(forKey: "dailyGoal"))) }
        set { d.set(newValue, forKey: "dailyGoal") }
    }
    /// The last day the goal was celebrated, so it happens once a day.
    static var goalDay: Date {
        get { (d.object(forKey: "goalDay") as? Date) ?? .distantPast }
        set { d.set(newValue, forKey: "goalDay") }
    }
    static var reminders: Bool {
        get { bool("reminders", true) }
        set { d.set(newValue, forKey: "reminders") }
    }
    static var ambience: Ambience {
        get { Ambience(rawValue: d.string(forKey: "ambience") ?? "") ?? .lofi }
        set { d.set(newValue.rawValue, forKey: "ambience") }
    }
    static var ambienceVolume: Double {
        get { d.object(forKey: "ambienceVolume") == nil ? 0.5 : d.double(forKey: "ambienceVolume") }
        set { d.set(newValue, forKey: "ambienceVolume") }
    }
    /// Badges already earned (kept so they never un-earn), and whether the existing history
    /// has been counted yet (so an update doesn't announce a pile of old badges at once).
    static var badges: Set<String> {
        get { Set(d.stringArray(forKey: "badges") ?? []) }
        set { d.set(Array(newValue).sorted(), forKey: "badges") }
    }
    /// Set the first time you focus before 8am or after 11pm (for the "Early bird" and "Night owl" badges).
    static var earlyBird: Bool {
        get { d.bool(forKey: "earlyBird") }
        set { d.set(newValue, forKey: "earlyBird") }
    }
    static var nightOwl: Bool {
        get { d.bool(forKey: "nightOwl") }
        set { d.set(newValue, forKey: "nightOwl") }
    }
    /// Minutes of her lo-fi (or rain, or waves) you've studied to.
    static var musicMinutes: Double {
        get { d.double(forKey: "musicMinutes") }
        set { d.set(newValue, forKey: "musicMinutes") }
    }
    static var badgesSeeded: Bool {
        get { d.bool(forKey: "badgesSeeded") }
        set { d.set(newValue, forKey: "badgesSeeded") }
    }
    // MARK: Coaching vibe, mood, chat, music
    static var vibe: Vibe {
        get { Vibe(rawValue: d.string(forKey: "vibe") ?? "") ?? .own }
        set { d.set(newValue.rawValue, forKey: "vibe") }
    }
    /// Today's mood from the daily check-in (nil on a new day until you answer).
    static var todayMood: Mood? {
        get {
            guard let day = d.object(forKey: "moodDay") as? Date, Calendar.current.isDateInToday(day) else { return nil }
            return Mood(rawValue: d.string(forKey: "moodToday") ?? "")
        }
        set {
            if let m = newValue { d.set(Date(), forKey: "moodDay"); d.set(m.rawValue, forKey: "moodToday") }
            else { d.removeObject(forKey: "moodDay"); d.removeObject(forKey: "moodToday") }
        }
    }
    /// The day the sticky note last appeared, and whether you pinned it to the desktop.
    static var noteDay: Date? {
        get { d.object(forKey: "noteDay") as? Date }
        set { d.set(newValue, forKey: "noteDay") }
    }
    static var notePinned: Bool {
        get { d.bool(forKey: "notePinned") }
        set { d.set(newValue, forKey: "notePinned") }
    }
    /// Ask "how are we feeling?" once a day.
    static var dailyCheckIn: Bool {
        get { bool("dailyCheckIn", true) }
        set { d.set(newValue, forKey: "dailyCheckIn") }
    }
    /// She bops her head to the music you're playing (needs the Screen & System Audio permission).
    static var musicBop: Bool {
        get { bool("musicBop", false) }
        set { d.set(newValue, forKey: "musicBop") }
    }
    /// Which decor items are out on show.
    static var decorOn: Set<String> {
        get { Set(d.stringArray(forKey: "decorOn") ?? []) }
        set { d.set(Array(newValue).sorted(), forKey: "decorOn") }
    }
    static var chatProvider: String {
        get { d.string(forKey: "chatProvider") ?? "local" }
        set { d.set(newValue, forKey: "chatProvider") }
    }
    static var chatModel: String {
        get { d.string(forKey: "chatModel") ?? "" }
        set { d.set(newValue, forKey: "chatModel") }
    }

    static var theme: AppTheme {
        get { AppTheme(legacy: d.string(forKey: "theme") ?? "") ?? .coquette }
        set { d.set(newValue.rawValue, forKey: "theme"); AppTheme.current = newValue }
    }
    static var welcomed: Bool {
        get { d.bool(forKey: "welcomed") }
        set { d.set(newValue, forKey: "welcomed") }
    }

    /// What she's wearing: one item per slot. Older versions had fewer slots (and kept the
    /// bow, flower and star clip under "head"), so every stored item is put in the slot it
    /// belongs to now, not the one it was saved under.
    static var outfit: Outfit {
        get {
            var o = Outfit()
            for key in ["rug", "aura", "body", "neck", "face", "head", "hair", "held"] {
                if let raw = d.string(forKey: "outfit.\(key)"), let a = Accessory(rawValue: raw), a != .none {
                    o[a.slot] = a
                }
            }
            if o.isEmpty, let old = Accessory(rawValue: d.string(forKey: "accessory") ?? ""), old != .none {
                o[old.slot] = old
            }
            // a new pet wears a bow and nothing else (once anything has been chosen, even "nothing", that wins)
            if o.isEmpty, d.object(forKey: "outfit.hair") == nil, d.object(forKey: "outfit.head") == nil,
               d.object(forKey: "accessory") == nil {
                o[.hair] = .bow
            }
            return o
        }
        set {
            for slot in AccessorySlot.allCases { d.set(newValue[slot].rawValue, forKey: "outfit.\(slot.rawValue)") }
            d.removeObject(forKey: "accessory")
        }
    }
    /// 0 = Small, 1 = Medium (default), 2 = Large.
    static var sizeLevel: Int {
        get { d.object(forKey: "sizeLevel") == nil ? 1 : min(max(0, d.integer(forKey: "sizeLevel")), 2) }
        set { d.set(newValue, forKey: "sizeLevel") }
    }
    static var launchAtLogin: Bool {
        get { bool("launchAtLogin", false) }
        set { d.set(newValue, forKey: "launchAtLogin"); d.set(true, forKey: "launchAtLoginPreferenceSet") }
    }
    static var launchAtLoginPreferenceSet: Bool {
        d.bool(forKey: "launchAtLoginPreferenceSet")
    }

    // MARK: Quiet hours: no barking/scolding in this window, even if distracted.
    static var quietHoursEnabled: Bool {
        get { bool("quietHoursEnabled", false) }
        set { d.set(newValue, forKey: "quietHoursEnabled") }
    }
    static var quietHoursStart: Int {
        get { d.object(forKey: "quietHoursStart") == nil ? 22 : d.integer(forKey: "quietHoursStart") }
        set { d.set(min(23, max(0, newValue)), forKey: "quietHoursStart") }
    }
    static var quietHoursEnd: Int {
        get { d.object(forKey: "quietHoursEnd") == nil ? 8 : d.integer(forKey: "quietHoursEnd") }
        set { d.set(min(23, max(0, newValue)), forKey: "quietHoursEnd") }
    }
    /// Handles overnight windows (e.g. 22 -> 8) as well as same-day ones (e.g. 12 -> 13).
    static var inQuietHours: Bool {
        guard quietHoursEnabled else { return false }
        let hour = Calendar.current.component(.hour, from: Date())
        let s = quietHoursStart, e = quietHoursEnd
        if s == e { return false }
        return s < e ? (hour >= s && hour < e) : (hour >= s || hour < e)
    }
}

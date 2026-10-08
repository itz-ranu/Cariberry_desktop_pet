import Foundation

/// Little collectables for real milestones. They're worked out from her saved history, so
/// they can never get out of step with the numbers, and once earned they stay earned.
struct Badge: Identifiable {
    let id: String
    let emoji: String
    let title: String
    let detail: String
    /// What "done" looks like, and how far along you are, so a locked badge can show a progress bar.
    let target: Double
    let value: @MainActor (Pet) -> Double
    /// How it's counted in the progress line ("3 of 7 days").
    var unit = ""

    @MainActor func isEarned(_ pet: Pet) -> Bool { value(pet) >= target }
    @MainActor func progress(_ pet: Pet) -> Double { min(1, max(0, value(pet) / max(1, target))) }
    @MainActor func progressText(_ pet: Pet) -> String {
        let v = min(value(pet), target)
        return "\(Int(v)) of \(Int(target))\(unit.isEmpty ? "" : " " + unit)"
    }
}

enum Badges {
    static let all: [Badge] = [
        // getting started
        Badge(id: "first", emoji: "🌱", title: "First steps", detail: "Focus for your first few minutes", target: 3, value: { $0.totalFocusMinutes }, unit: "min"),
        Badge(id: "sess1", emoji: "🍵", title: "First sip", detail: "Finish your first focus session", target: 1, value: { Double($0.totalSessions) }, unit: "session"),
        Badge(id: "mood1", emoji: "💌", title: "Checked in", detail: "Tell her how you feel", target: 1, value: { Double($0.moods.count) }, unit: "check-in"),
        Badge(id: "habit1", emoji: "🌷", title: "Little habits", detail: "Tick off every daily habit in one day", target: 1, value: { _ in Double(Habits.perfectDays) }, unit: "day"),

        // streaks
        Badge(id: "streak3", emoji: "🔥", title: "On a roll", detail: "A 3 day streak", target: 3, value: { Double($0.bestStreakDays) }, unit: "days"),
        Badge(id: "streak7", emoji: "💪", title: "Week warrior", detail: "A 7 day streak", target: 7, value: { Double($0.bestStreakDays) }, unit: "days"),
        Badge(id: "streak14", emoji: "⚡️", title: "Unstoppable", detail: "A 14 day streak", target: 14, value: { Double($0.bestStreakDays) }, unit: "days"),
        Badge(id: "streak30", emoji: "👑", title: "Legend", detail: "A 30 day streak", target: 30, value: { Double($0.bestStreakDays) }, unit: "days"),
        Badge(id: "streak100", emoji: "🏰", title: "Forever bestie", detail: "A 100 day streak", target: 100, value: { Double($0.bestStreakDays) }, unit: "days"),

        // how long you stayed
        Badge(id: "hour", emoji: "⏱", title: "Focus hour", detail: "An hour of focus in one day", target: 60, value: { $0.mostFocusInADay }, unit: "min"),
        Badge(id: "deep", emoji: "🧠", title: "Deep work", detail: "3 hours of focus in one day", target: 180, value: { $0.mostFocusInADay }, unit: "min"),
        Badge(id: "marathon", emoji: "🏔", title: "Study marathon", detail: "5 hours of focus in one day", target: 300, value: { $0.mostFocusInADay }, unit: "min"),
        Badge(id: "total10", emoji: "📚", title: "10 hours in", detail: "10 hours of focus, all time", target: 600, value: { $0.totalFocusMinutes }, unit: "min"),
        Badge(id: "total50", emoji: "🎓", title: "50 hour scholar", detail: "50 hours of focus, all time", target: 3000, value: { $0.totalFocusMinutes }, unit: "min"),
        Badge(id: "total100", emoji: "🌟", title: "100 hour club", detail: "100 hours of focus, all time", target: 6000, value: { $0.totalFocusMinutes }, unit: "min"),

        // goals and sessions
        Badge(id: "goal1", emoji: "🎯", title: "Goal getter", detail: "Hit your daily goal", target: 1, value: { Double($0.daysAtGoal) }, unit: "day"),
        Badge(id: "goal7", emoji: "🏆", title: "Goal machine", detail: "Hit your goal on 7 days", target: 7, value: { Double($0.daysAtGoal) }, unit: "days"),
        Badge(id: "goal30", emoji: "💎", title: "Diamond habits", detail: "Hit your goal on 30 days", target: 30, value: { Double($0.daysAtGoal) }, unit: "days"),
        Badge(id: "sess5", emoji: "🍅", title: "Pomodoro pro", detail: "Finish 5 focus sessions", target: 5, value: { Double($0.totalSessions) }, unit: "sessions"),
        Badge(id: "sess25", emoji: "🌟", title: "Session star", detail: "Finish 25 focus sessions", target: 25, value: { Double($0.totalSessions) }, unit: "sessions"),
        Badge(id: "sess100", emoji: "🪐", title: "Orbit master", detail: "Finish 100 focus sessions", target: 100, value: { Double($0.totalSessions) }, unit: "sessions"),
        Badge(id: "angel", emoji: "😇", title: "Angel day", detail: "An hour of focus without a single bark", target: 1, value: { Double($0.angelDays) }, unit: "day"),

        // to-dos
        Badge(id: "tasks10", emoji: "✅", title: "Task tamer", detail: "Finish 10 to-dos", target: 10, value: { Double($0.totalTasksDone) }, unit: "to-dos"),
        Badge(id: "tasks50", emoji: "👸", title: "Productivity queen", detail: "Finish 50 to-dos", target: 50, value: { Double($0.totalTasksDone) }, unit: "to-dos"),
        Badge(id: "tasks200", emoji: "🦄", title: "Unicorn energy", detail: "Finish 200 to-dos", target: 200, value: { Double($0.totalTasksDone) }, unit: "to-dos"),

        // time of day and mood
        Badge(id: "early", emoji: "🌅", title: "Early bird", detail: "Focus before 8am", target: 1, value: { _ in Prefs.earlyBird ? 1 : 0 }),
        Badge(id: "owl", emoji: "🦉", title: "Night owl", detail: "Focus after 11pm", target: 1, value: { _ in Prefs.nightOwl ? 1 : 0 }),
        Badge(id: "selfaware", emoji: "🪞", title: "Self-aware", detail: "Check in on your mood on 7 days", target: 7, value: { Double($0.moods.count) }, unit: "days"),

        // music, snacks and style
        Badge(id: "lofi", emoji: "🎧", title: "Lo-fi girl", detail: "Study to an hour of music", target: 60, value: { _ in Prefs.musicMinutes }, unit: "min"),
        Badge(id: "snack", emoji: "🍓", title: "Snack time", detail: "Feed her 10 treats", target: 10, value: { Double($0.treatsEaten) }, unit: "treats"),
        Badge(id: "dressed", emoji: "🎀", title: "Dress-up queen", detail: "Wear something in all three spots", target: 1, value: {
            $0.outfit.head != .none && $0.outfit.face != .none && $0.outfit.neck != .none ? 1 : 0 }),
        Badge(id: "decor", emoji: "🛋", title: "Cosy corner", detail: "Put 3 things in her room", target: 3, value: { Double($0.decorOn.count) }, unit: "things"),

        // growing up
        Badge(id: "lvl5", emoji: "🌿", title: "Growing up", detail: "Reach level 5", target: 5, value: { Double($0.level) }, unit: "levels"),
        Badge(id: "lvl10", emoji: "✨", title: "Besties", detail: "Reach level 10", target: 10, value: { Double($0.level) }, unit: "levels"),
        Badge(id: "lvl20", emoji: "💫", title: "Soulmates", detail: "Reach level 20", target: 20, value: { Double($0.level) }, unit: "levels"),
    ]

    /// The unearned badge you're closest to: "next up".
    @MainActor static func nextUp(for pet: Pet) -> Badge? {
        let earned = Prefs.badges
        return all.filter { !earned.contains($0.id) }.max { $0.progress(pet) < $1.progress(pet) }
    }
}

/// A few tiny daily rituals, ready from the first minute so there's something to tick off and
/// some XP to earn on day one. They reset every morning. A habit marked "auto" ticks itself.
struct Habit: Identifiable {
    let id: String
    let emoji: String
    let title: String
    let auto: (@MainActor (Pet) -> Bool)?
}

@MainActor
enum Habits {
    static let all: [Habit] = [
        Habit(id: "water", emoji: "💧", title: "Drink some water", auto: nil),
        Habit(id: "stretch", emoji: "🧘", title: "Stretch for a minute", auto: nil),
        Habit(id: "eyes", emoji: "👀", title: "Rest your eyes (20-20-20)", auto: nil),
        Habit(id: "focus", emoji: "📚", title: "Focus for 25 minutes", auto: { $0.focusTodayMinutes >= 25 }),
        Habit(id: "tidy", emoji: "🌸", title: "Tidy your desk", auto: nil),
    ]

    static let xp = 4.0, berries = 3, bonusBerries = 10

    private static var d: UserDefaults { .standard }
    private static func key(_ day: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: day)
        return String(format: "habits.%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func done(on day: Date = Date()) -> Set<String> { Set(d.stringArray(forKey: key(day)) ?? []) }
    static func set(_ ids: Set<String>, on day: Date = Date()) { d.set(Array(ids).sorted(), forKey: key(day)) }

    /// How many days you ticked every habit.
    static var perfectDays: Int {
        get { d.integer(forKey: "habits.perfectDays") }
        set { d.set(newValue, forKey: "habits.perfectDays") }
    }
}

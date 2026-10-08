import Foundation

/// How you're feeling today: a gentle daily check-in. Stored per day, so Stats can show how
/// the week felt, and she adjusts (softer when you're stressed or tired).
enum Mood: String, CaseIterable, Codable {
    case radiant, cozy, stressed, tired, excited

    var title: String {
        switch self {
        case .radiant: return "Radiant"
        case .cozy: return "Cozy"
        case .stressed: return "Stressed"
        case .tired: return "Tired"
        case .excited: return "Excited"
        }
    }
    var emoji: String {
        switch self {
        case .radiant: return "✨"
        case .cozy: return "☕"
        case .stressed: return "💭"
        case .tired: return "☁️"
        case .excited: return "🎉"
        }
    }
    /// She's gentler with you on these days.
    var needsGentleness: Bool { self == .stressed || self == .tired }

    /// What she says right after you pick it.
    func reply(_ species: Species) -> String {
        let name = species.displayName.lowercased()
        switch self {
        case .radiant: return ["you're GLOWING today ✨ let's make it count", "radiant?! okay main character 💗", "love that energy, bestie ✨"].randomElement() ?? ""
        case .cozy: return ["cozy it is ☕ soft day, soft goals", "*curls up next to you* perfect weather for a \(name) 🧸", "cozy vibes only 🤍"].randomElement() ?? ""
        case .stressed: return ["come here 🫂 one thing at a time, okay?", "I'm right here 💗 we'll go gently today", "breathe in… out… I've got you 🌿"].randomElement() ?? ""
        case .tired: return ["rest counts as progress ☁️ small goals today", "tired is allowed 🤍 let's keep it easy", "water, a stretch, then one tiny task? 🌷"].randomElement() ?? ""
        case .excited: return ["YES 🎉 what are we celebrating?!", "excited?! I'm vibrating 🎊", "big energy day, let's go!! ✨"].randomElement() ?? ""
        }
    }
}

/// The little note stuck to your desktop after you check in: an affirmation, a fortune and
/// a lucky snack, the same all day for the same mood (so it never feels random-noisy).
enum Fortune {
    private static let byMood: [Mood: [String]] = [
        .radiant: [
            "you're the main character and the plot is going great",
            "today, everything you touch turns a little more golden",
            "someone is quietly proud of you. (it's me.)",
            "your energy is a free gift to everyone around you",
            "a small win is already on its way to you",
        ],
        .cozy: [
            "soft hours are productive hours too",
            "a warm drink and one gentle task. that's a whole day",
            "you don't have to earn rest",
            "the cosiest version of you is also the most capable",
            "go slow. the cosy things last longest",
        ],
        .stressed: [
            "you only have to do the next small thing",
            "this feeling is weather, not climate. it will pass",
            "you've survived 100% of your hard days so far",
            "unclench your jaw. drop your shoulders. okay, better",
            "done is better than perfect, and breaks are part of the work",
        ],
        .tired: [
            "your best today can look different, and that's okay",
            "drink some water, then decide. you're doing fine",
            "even a tiny bit of progress still counts",
            "rest is not laziness. it's maintenance",
            "be as kind to yourself as you'd be to a friend",
        ],
        .excited: [
            "ride this wave, it's yours",
            "good things are circling you. say yes to one of them",
            "your excitement is contagious. spread it kindly",
            "today is a day for starting the thing",
            "celebrate before it's finished, you've earned it",
        ],
    ]
    private static let colours = ["lilac 💜", "butter yellow 💛", "mint 💚", "blush pink 🩷", "sky blue 💙", "peach 🧡", "cream 🤍"]
    private static let snacks = ["onigiri 🍙", "strawberry mochi 🍓", "a warm cookie 🍪", "boba 🧋", "toast with honey 🍯", "clementines 🍊", "iced matcha 🍵", "pretzels 🥨"]

    private static let tips = [
        "25 minutes on, 5 minutes off. Start with just one",
        "write down the one thing to do first",
        "phone in another room, brain in this one",
        "water first, then work",
        "do the hard thing before lunch",
        "if it takes under two minutes, do it now",
        "close the tabs you're not using",
        "stand up and stretch once an hour",
        "a tidy desk is a tiny fresh start",
    ]

    /// Deterministic per day + mood: the note doesn't change every time you open it.
    static func note(for mood: Mood, on day: Date) -> (text: String, extras: String) {
        let seed = Int(day.timeIntervalSinceReferenceDate / 86400) &+ mood.hashValue.magnitude.hashValue
        func pick<T>(_ a: [T], _ salt: Int) -> T { a[abs(seed &+ salt &* 7919) % a.count] }
        let fortune = pick(byMood[mood] ?? ["you're doing great"], 0)
        return (fortune, "💡 study tip: \(pick(tips, 3))\nlucky colour: \(pick(colours, 1)) · lucky snack: \(pick(snacks, 2))")
    }
}

import Foundation

/// How she coaches you when you drift. Her own voice (the default) is whatever her animal
/// would say; the three vibes override the *coaching* lines (scolding, praise, closing a tab)
/// and change how patient she is, so you can pick the kind of accountability you actually want.
enum Vibe: String, CaseIterable, Codable {
    case own, gentle, sassy, drill

    var title: String {
        switch self {
        case .own: return "Her own voice"
        case .gentle: return "Gentle Cozy"
        case .sassy: return "Sassy Bestie"
        case .drill: return "Drill Sergeant"
        }
    }
    var emoji: String {
        switch self {
        case .own: return "🐾"
        case .gentle: return "🌸"
        case .sassy: return "💅"
        case .drill: return "🫡"
        }
    }
    var blurb: String {
        switch self {
        case .own: return "Each animal scolds in her own personality."
        case .gentle: return "Soft nudges. Longer to react, kinder words."
        case .sassy: return "Loving, witty roasting from your bestie."
        case .drill: return "Loud, fast and relentless. No excuses."
        }
    }
    /// A taste of how she'll sound, shown under the picker.
    var example: String {
        switch self {
        case .own: return "(depends on who she is: a kitten hisses, a capybara says “excuse me”)"
        case .gentle: return "“Bestie… maybe a quick break from reels? Let's finish that study goal 🥺🌸”"
        case .sassy: return "“Not another 30 minutes on Pinterest 💅 your essay isn't gonna write itself!”"
        case .drill: return "“BARK! 🐶 reels again?! Eyes UP! No treats until focus time is done!”"
        }
    }

    /// How long she waits before reacting, as a multiple of the rule's own delay.
    var patience: Double {
        switch self {
        case .own, .sassy: return 1
        case .gentle: return 1.6
        case .drill: return 0.55
        }
    }
    /// How long between repeat warnings, as a multiple of the usual gap.
    var gap: Double {
        switch self {
        case .own, .sassy: return 1
        case .gentle: return 1.5
        case .drill: return 0.6
        }
    }

    // MARK: Lines

    enum Kind { case scold, scoldHard, tapClose, closedTab, backToWork, praise }

    /// Coaching lines for a vibe. `{x}` is what you were distracted by. Written in a dog's
    /// voice where there's barking: `Dialogue.flavor` swaps it for hers.
    func lines(_ kind: Kind) -> [String] {
        switch (self, kind) {
        case (.own, _): return []

        case (.gentle, .scold): return [
            "bestie… maybe a quick break from {x}? let's finish that study goal 🥺🌸",
            "hey you 🌷 {x} is calling, but your goals are louder. shall we go back?",
            "no pressure, but {x} might not be helping right now 💗",
            "gentle nudge: close {x} and take one deep breath? you've got this 🌿",
            "I believe in you, truly. {x} can wait 🤍",
        ]
        case (.gentle, .scoldHard): return [
            "okay love, I'm a little worried now… can we close {x} together? 🥺",
            "you're stronger than {x}. one tab. just close it 💗",
            "I'll sit right here until we're back on track 🌸",
        ]
        case (.gentle, .tapClose): return [
            "I'll close it for you, sweetie 🌷", "let me help, just this once 🌸", "there, a fresh start 💗",
        ]
        case (.gentle, .closedTab): return [
            "all closed 🌷 deep breath. you're doing great", "gone! no judgment 🤍", "ready when you are, bestie 🌸",
        ]
        case (.gentle, .backToWork): return [
            "oh, I'm so proud of you 🥹🌸", "there you are 💗 welcome back", "that took courage. thank you 🌷",
        ]
        case (.gentle, .praise): return [
            "you're doing beautifully 🌸", "I'm right here with you 🤍", "slow and steady, bestie 🌿", "so proud of you 💗",
        ]

        case (.sassy, .scold): return [
            "not another 30 minutes on {x} 💅… your essay isn't gonna write itself!",
            "{x} again?? babe. no. 😒",
            "I'm not mad, I'm just disappointed. and slightly mad. close {x} 💅",
            "bestie, {x} is not a personality. back to work ✨",
            "the way you opened {x} like I wouldn't notice 👀",
        ]
        case (.sassy, .scoldHard): return [
            "I will start a group chat about this 😤 close {x}.",
            "this is an intervention. {x}. closed. now. 💅",
            "you have exactly zero excuses left 🙄 close {x}",
        ]
        case (.sassy, .tapClose): return ["allow me 💅", "I'll do it myself, as per usual", "watch and learn 😼"]
        case (.sassy, .closedTab): return ["closed. you're welcome 💅", "gone. I'm that girl 😼", "next time, listen the first time ✨"]
        case (.sassy, .backToWork): return ["thank you. that wasn't so hard 💅", "oh we're productive now? iconic 💗", "knew you had it in you ✨"]
        case (.sassy, .praise): return ["look at you being productive 💅", "slay the study session ✨", "okay main character energy 💗", "I'm obsessed with this focus 😭"]

        case (.drill, .scold): return [
            "BARK! 🐶 {x} again?! Eyes UP!",
            "BARK! No treats until focus time is done!",
            "Drop {x}. Right now. MOVE MOVE MOVE 😤",
            "That's not in the plan, soldier! Close {x}! 🫡",
            "BARK BARK! Focus is NOT optional!",
        ]
        case (.drill, .scoldHard): return [
            "BARK BARK BARK!!! CLOSE IT NOW!!! 😡",
            "I'm not asking again. {x}. GONE. 🚫",
            "DROP AND GIVE ME 25 MINUTES OF FOCUS! 🫡",
        ]
        case (.drill, .tapClose): return ["I'm closing it MYSELF! 🫡", "STAND BACK! 🐾", "executing close order 🫡"]
        case (.drill, .closedTab): return ["TARGET ELIMINATED 🫡", "tab down. back to work, soldier!", "GONE. now move! 💪"]
        case (.drill, .backToWork): return ["good soldier! keep that pace 🫡", "THAT'S what I like to see! 💪", "at ease. now keep going"]
        case (.drill, .praise): return ["steady pace, soldier! 🫡", "discipline looks good on you 💪", "keep it up! no slacking!"]
        }
    }
}

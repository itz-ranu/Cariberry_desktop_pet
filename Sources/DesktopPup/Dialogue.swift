import Foundation

/// Everything she says. Each animal has her own voice for every situation (see `Voices.swift`):
/// a kitten is a sassy diva, a puppy a hype best friend, a capybara is unbothered. Ask for a
/// situation and an animal and you get a line in her voice; the same line is never picked
/// twice in a row.
enum Dialogue {
    private static var lastPick: [Line: String] = [:]

    static func pool(_ kind: Line, _ species: Species) -> [String] {
        voices[species]?[kind] ?? voices[.cat]?[kind] ?? []
    }

    /// `{name}` is her name, `{n}` a number (minutes, days, level), `{x}` what you were
    /// distracted by, `{item}` a collar.
    static func line(_ kind: Line, _ species: Species, name: String = "", _ vars: [String: String] = [:]) -> String {
        let all = pool(kind, species)
        guard var pick = all.randomElement() else { return "" }
        if all.count > 1, pick == lastPick[kind] {
            pick = all.filter { $0 != pick }.randomElement() ?? pick
        }
        lastPick[kind] = pick
        return fill(pick, name: name, vars)
    }

    private static func fill(_ text: String, name: String, _ vars: [String: String]) -> String {
        var out = text.replacingOccurrences(of: "{name}", with: name)
        for (k, v) in vars { out = out.replacingOccurrences(of: "{\(k)}", with: v) }
        return out
    }

    // MARK: Persona

    /// A one-line description of how she talks, for the chat brain's system prompt.
    static func persona(_ s: Species) -> String {
        switch s {
        case .cat: return "a sassy, dramatic kitten diva who acts aloof but secretly adores the user"
        case .dog: return "an over-the-moon enthusiastic puppy who LOVES the user and uses CAPS for excitement"
        case .bunny: return "a sweet, soft-spoken bunny who is gentle, bouncy and encouraging"
        case .fox: return "a sly, witty fox who loves clever plans, playful teasing and plot twists"
        case .panda: return "a sleepy, snack-loving panda who is calm, slow and endlessly comforting"
        case .hamster: return "a tiny, hyper, slightly anxious hamster who squeaks, loves seeds and runs on a wheel"
        case .axolotl: return "a wholesome, always-smiling axolotl who gives gentle affirmations and says glub"
        case .capybara: return "an unbothered, chill capybara who is relaxed, welcoming and says everything will be fine"
        }
    }

    // MARK: Time of day

    /// The line she opens with when the app starts: it knows what time it is.
    static func greeting(_ species: Species, name: String) -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 23, 0...4: return line(.greetNight, species, name: name)
        case 5...11: return line(.greetMorning, species, name: name)
        default: return line(.greetDay, species, name: name)
        }
    }

    // MARK: Coaching

    /// The built-in rules ship with a "dog" voice written into their saved lines, so for
    /// these she ignores the stored text and speaks as herself. Rules you made yourself
    /// (a blocked site) keep their wording, with the dog noises swapped for hers.
    private static let builtIn: Set<String> = [
        "Reels & short-form video", "Social media", "Streaming & twitch", "Music & media",
        "YouTube (might be learning, might not)", "Games", "Coding", "Studying & writing",
    ]

    /// What `{x}` stands for in a scolding.
    static func topic(forRule rule: String) -> String {
        if rule.hasPrefix("Blocked: ") { return String(rule.dropFirst("Blocked: ".count)) }
        if rule.hasPrefix("Guard: ") { return String(rule.dropFirst("Guard: ".count)) }
        if rule.contains("Reels") { return "reels" }
        if rule.contains("Social") { return "the feed" }
        if rule.contains("Streaming") { return "this show" }
        if rule.contains("YouTube") { return "YouTube" }
        if rule.contains("Games") { return "the game" }
        return "that"
    }

    /// The vibe she's coaching in right now. On a day you said you were stressed or tired she
    /// goes gentle whatever you picked.
    static var effectiveVibe: Vibe {
        let v = Prefs.vibe
        if v != .gentle, let m = Prefs.todayMood, m.needsGentleness { return .gentle }
        return v
    }

    /// A coaching line in the chosen vibe, or in her own voice when the vibe is "her own".
    static func coach(_ kind: Vibe.Kind, _ species: Species, _ vars: [String: String] = [:]) -> String {
        let vibe = effectiveVibe
        let pool = vibe.lines(kind)
        guard let raw = pool.randomElement() else {
            switch kind {
            case .scold: return line(.scold, species, vars)
            case .scoldHard: return line(.scoldHard, species, vars)
            case .tapClose: return line(.tapClose, species, vars)
            case .closedTab: return line(.closedTab, species, vars)
            case .backToWork: return line(.backToWork, species, vars)
            case .praise: return line(.praise, species, vars)
            }
        }
        var out = raw
        for (k, v) in vars { out = out.replacingOccurrences(of: "{\(k)}", with: v) }
        return flavor(out, species)
    }

    static func scold(rule: String, storedLines: [String], species: Species, count: Int) -> String {
        if count >= 3 { return coach(.scoldHard, species, ["x": topic(forRule: rule)]) }
        if !builtIn.contains(rule), !storedLines.isEmpty {
            let pick = storedLines[min(storedLines.count - 1, (count - 1) % storedLines.count)]
            return flavor(pick, species)
        }
        return coach(.scold, species, ["x": topic(forRule: rule)])
    }

    static func praise(rule: String, storedLines: [String], species: Species) -> String {
        if !builtIn.contains(rule), let pick = storedLines.randomElement() { return flavor(pick, species) }
        return coach(.praise, species)
    }

    // MARK: Swapping dog noises

    private static func noise(_ s: Species) -> (loud: String, soft: String) {
        switch s {
        case .dog: return ("BARK", "woof")
        case .cat: return ("HISS", "mrow")
        case .bunny: return ("THUMP", "thump")
        case .fox: return ("YIP", "yip")
        case .panda: return ("GRR", "grr")
        case .hamster: return ("SQUEAK", "squeak")
        case .axolotl: return ("GLUB", "glub")
        case .capybara: return ("EXCUSE ME", "ahem")
        }
    }

    /// Rewrites a line written in a dog's voice ("BARK! woof 🐶") into hers.
    static func flavor(_ text: String, _ species: Species) -> String {
        guard species != .dog else { return text }
        let n = noise(species)
        return text
            .replacingOccurrences(of: "BARK", with: n.loud)
            .replacingOccurrences(of: "Bark", with: n.loud.capitalized)
            .replacingOccurrences(of: "bark", with: n.soft)
            .replacingOccurrences(of: "WOOF", with: n.loud)
            .replacingOccurrences(of: "Woof", with: n.soft.capitalized)
            .replacingOccurrences(of: "woof", with: n.soft)
            .replacingOccurrences(of: "🐶", with: species.emoji)
            .replacingOccurrences(of: "🐕", with: species.emoji)
    }
}

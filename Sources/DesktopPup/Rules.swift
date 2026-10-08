import Foundation
import OSLog

private let rulesLogger = Logger(subsystem: "com.desktoppup.cariberry", category: "rules")

/// One user-editable behaviour rule. Lives in ~/Library/Application Support/DesktopPup/rules.json
struct FocusRule: Codable {
    var name: String
    var mode: String            // "distraction" | "work" | "neutral"
    var apps: [String] = []     // matched against bundle id + app name (case-insensitive substring)
    var urls: [String] = []     // matched against browser URL + tab title
    var delay: Double = 25      // seconds of tolerance before the pup reacts
    var severity: Int = 2       // 1 = whine/nudge, 2 = full bark
    var lines: [String] = []

    var kind: ActivityKind {
        switch mode.lowercased() {
        case "distraction": return .distraction
        case "work":        return .work
        default:            return .neutral
        }
    }

    func matches(bundle: String, appName: String, page: String) -> Bool {
        let appHay = (bundle + " " + appName).lowercased()
        for a in apps where !a.isEmpty && appHay.contains(a.lowercased()) { return true }
        if !page.isEmpty {
            for u in urls where !u.isEmpty && page.contains(u.lowercased()) { return true }
        }
        return false
    }
}

struct RuleBook: Codable {
    var version = 1
    var rules: [FocusRule]

    static let `default` = RuleBook(rules: [

        // short-form video, the big one
        FocusRule(name: "Reels & short-form video", mode: "distraction",
                  apps: ["com.zhiliaoapp.musically", "tiktok"],
                  urls: ["instagram.com/reels", "/reels/", "instagram.com/stories",
                         "youtube.com/shorts", "/shorts/", "tiktok.com",
                         "facebook.com/reel", "snapchat.com/spotlight", "· reels", "reels ·"],
                  delay: 20, severity: 2,
                  lines: ["BARK! 🐶 reels again?! eyes UP",
                          "woof!! that's 20 seconds you're not getting back 😤",
                          "scrolling is not a personality. FOCUS 🐾",
                          "BARK BARK! the algorithm is winning 😡",
                          "put. the. phone-website. down. 🐕"]),

        FocusRule(name: "Social media", mode: "distraction",
                  apps: ["com.burbn.instagram", "com.facebook", "com.atebits.tweetie", "twitter", "reddit"],
                  urls: ["instagram.com", "twitter.com", "x.com/home", "facebook.com",
                         "reddit.com", "threads.net", "9gag", "pinterest.com", "tumblr.com"],
                  delay: 40, severity: 2,
                  lines: ["hey! 🐶 you said you'd focus today",
                          "woof — the internet will still be there later",
                          "BARK! close the tab, I believe in you 💪"]),

        FocusRule(name: "Streaming & twitch", mode: "distraction",
                  apps: ["com.netflix", "tv.twitch", "com.spotify.client.video"],
                  urls: ["netflix.com/watch", "hulu.com/watch", "twitch.tv", "primevideo.com",
                         "disneyplus.com", "hotstar.com", "crunchyroll.com/watch"],
                  delay: 60, severity: 2,
                  lines: ["is this a study break or a season finale? 🐕",
                          "BARK! one more episode… said the human, 4 hours ago 😤"]),

        // neutral, not a distraction: she just labels it cleanly instead of it
        // vanishing into "Other". Placed after "Streaming & twitch" (which already
        // claims Spotify's video component ahead of this) and before the YouTube
        // rule, which would otherwise claim music.youtube.com for itself.
        FocusRule(name: "Music & media", mode: "neutral",
                  apps: ["com.spotify.client", "com.apple.music", "com.apple.itunes",
                         "com.apple.podcasts", "soundcloud"],
                  urls: ["music.apple.com", "music.youtube.com", "soundcloud.com",
                         "open.spotify.com"],
                  delay: 999, severity: 0,
                  lines: []),

        FocusRule(name: "YouTube (might be learning, might not)", mode: "distraction",
                  apps: [],
                  urls: ["youtube.com/watch", "youtube.com/feed", "- youtube"],
                  delay: 150, severity: 1,
                  lines: ["…is this a tutorial? 👀 (I'm watching)",
                          "*soft whine* 🥺 it's been a while on YouTube",
                          "woof? still learning something? 🐾"]),

        FocusRule(name: "Games", mode: "distraction",
                  apps: ["com.valvesoftware.steam", "com.epicgames", "com.riotgames",
                         "minecraft", "com.blizzard", "discord"],
                  urls: ["chess.com", "poki.com", "roblox.com"],
                  delay: 90, severity: 1,
                  lines: ["gaming already? 🐶 did we finish the thing?",
                          "woof! I want to play too — after your work 🎾"]),

        // work rules: she goes soft here
        FocusRule(name: "Coding", mode: "work",
                  apps: ["com.apple.dt.xcode", "com.microsoft.vscode", "com.todesktop", "cursor",
                         "com.jetbrains", "dev.zed", "com.sublimetext", "com.apple.terminal",
                         "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp", "neovim",
                         "com.figma.desktop", "com.postmanlabs", "com.docker.docker",
                         "com.tinyapp.tablepro", "android studio"],
                  urls: ["github.com", "gitlab.com", "stackoverflow.com", "developer.apple.com",
                         "leetcode.com", "localhost:", "127.0.0.1", "docs.", "mdn web docs"],
                  delay: 0, severity: 0,
                  lines: ["look at you writing code 💗",
                          "my human is a genius 🥹 keep going",
                          "*curls up next to the keyboard* 🐾",
                          "I don't understand any of this but I'm SO proud 💕",
                          "compile it! I believe in you ✨"]),

        FocusRule(name: "Studying & writing", mode: "work",
                  apps: ["com.apple.preview", "com.adobe.acrobat", "com.apple.pages",
                         "com.microsoft.word", "com.apple.notes", "md.obsidian", "notion",
                         "com.literatureandlatte.scrivener", "com.apple.iBooksX", "goodnotes",
                         "com.apple.numbers", "com.microsoft.excel", "anki"],
                  urls: ["notion.so", "overleaf.com", "coursera.org", "khanacademy.org",
                         "wikipedia.org", "scholar.google", "arxiv.org", "canvas.", "brightspace",
                         "quizlet.com", "docs.google.com"],
                  delay: 0, severity: 0,
                  lines: ["study mode 📚 I'll keep you company",
                          "you're so smart it's unfair 🥹",
                          "*rests head on your notes* 💗",
                          "every page is a win 🐾",
                          "future you is going to thank present you ✨"]),
    ])
}

@MainActor
final class RuleStore {
    static let shared = RuleStore()
    private(set) var book: RuleBook = .default

    var url: URL { Store.dir.appendingPathComponent("rules.json") }

    init() { load() }

    func load() {
        guard FileManager.default.fileExists(atPath: url.path) else {
            writeDefaults()
            return
        }
        do {
            let data = try Data(contentsOf: url)
            book = try JSONDecoder().decode(RuleBook.self, from: data)
        } catch {
            rulesLogger.error("Could not load rules: \(error.localizedDescription, privacy: .public)")
            // a broken file used to just get silently overwritten with defaults here,
            // permanently destroying whatever custom rules the person had written.
            // back it up first so a stray comma in rules.json never costs them their
            // whole rule set.
            backupBrokenFile()
            writeDefaults()
        }
    }

    /// Copies the unreadable rules.json aside (e.g. `rules.broken-2026-09-08T121500.json`)
    /// before it gets replaced with defaults, so nothing the person wrote is lost.
    private func backupBrokenFile() {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "")
        let backupURL = Store.dir.appendingPathComponent("rules.broken-\(stamp).json")
        do {
            try FileManager.default.copyItem(at: url, to: backupURL)
            rulesLogger.notice("Backed up unreadable rules.json to \(backupURL.lastPathComponent, privacy: .public)")
        } catch {
            rulesLogger.error("Could not back up broken rules.json: \(error.localizedDescription, privacy: .public)")
        }
    }

    func writeDefaults() {
        book = .default
        save()
    }

    /// From the "Block a site or app…" menu item. Goes in both apps and urls
    /// since we don't know which one the term is, and inserted first to win.
    func addBlock(_ term: String) {
        let t = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty else { return }
        book.rules.removeAll { $0.name == "Blocked: \(t)" }
        let rule = FocusRule(name: "Blocked: \(t)", mode: "distraction",
                             apps: [t], urls: [t],
                             delay: 5, severity: 2,
                             lines: ["BARK! 😡 \(t) is BANNED, you know this",
                                     "woof!! we agreed — no \(t) 😤",
                                     "put it away, \(t) is off limits 🐕",
                                     "BARK BARK! I saw that. close it. 😠",
                                     "you blocked this yourself! close it 🚫"])
        book.rules.insert(rule, at: 0)
        save()
    }

    // MARK: App Guard

    /// Turns a preset's rule on or off. Guard rules go first so they win over broader ones.
    func setGuard(_ preset: GuardPreset, on: Bool) {
        book.rules.removeAll { $0.name == preset.ruleName }
        if on {
            book.rules.insert(FocusRule(name: preset.ruleName, mode: "distraction",
                                        apps: preset.apps, urls: preset.urls, delay: 25, severity: 2, lines: []), at: 0)
        }
        save()
    }

    func isGuarded(_ preset: GuardPreset) -> Bool { book.rules.contains { $0.name == preset.ruleName } }

    /// Sites and apps you blocked yourself by name.
    var customBlocks: [String] {
        book.rules.compactMap { $0.name.hasPrefix("Blocked: ") ? String($0.name.dropFirst("Blocked: ".count)) : nil }
    }

    func removeBlock(_ term: String) {
        book.rules.removeAll { $0.name == "Blocked: \(term)" }
        save()
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: Store.dir, withIntermediateDirectories: true)
            let data = try enc.encode(book)
            try data.write(to: url, options: .atomic)
        } catch {
            rulesLogger.error("Could not save rules: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// First matching rule wins, so order the file most-specific first.
    func evaluate(bundle: String, appName: String, url page: String, title: String) -> Verdict {
        let hay = (page + " " + title).lowercased()
        let key = siteKey(appName: appName, page: page)
        for rule in book.rules where rule.matches(bundle: bundle, appName: appName, page: hay) {
            return Verdict(kind: rule.kind,
                           label: displayLabel(rule: rule, appName: appName, title: title),
                           siteKey: key,
                           ruleName: rule.name,
                           delay: rule.delay,
                           lines: rule.lines,
                           severity: rule.severity)
        }
        return Verdict(kind: .neutral, label: appName, siteKey: key, ruleName: "—",
                       delay: 999, lines: [], severity: 0)
    }

    private func displayLabel(rule: FocusRule, appName: String, title: String) -> String {
        if !title.isEmpty {
            let short = title.count > 42 ? String(title.prefix(42)) + "…" : title
            return short
        }
        return appName
    }

    /// The page title changes on every video/article, which is useless for "where did
    /// my time go": group by domain instead, and fall back to the app name off the web.
    private func siteKey(appName: String, page: String) -> String {
        guard !page.isEmpty, let host = URL(string: page)?.host else { return appName }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

import Foundation

/// The distracting apps and sites you can switch on with one tap in the App Guard tab.
/// Each one becomes an ordinary rule in rules.json (named "Guard: TikTok"), so they still
/// work with everything else (quiet hours, vibes, the timer) and can be edited by hand.
struct GuardPreset: Identifiable {
    let id: String
    let emoji: String
    let name: String
    let apps: [String]       // matched against bundle id + app name
    let urls: [String]       // matched against the browser's page address and tab title

    static let all: [GuardPreset] = [
        GuardPreset(id: "tiktok", emoji: "🎵", name: "TikTok",
                    apps: ["com.zhiliaoapp.musically", "tiktok"], urls: ["tiktok.com"]),
        GuardPreset(id: "instagram", emoji: "📸", name: "Instagram",
                    apps: ["com.burbn.instagram", "instagram"], urls: ["instagram.com"]),
        GuardPreset(id: "youtube", emoji: "▶️", name: "YouTube",
                    apps: ["youtube"], urls: ["youtube.com", "- youtube"]),
        GuardPreset(id: "shein", emoji: "🛍️", name: "Shein",
                    apps: ["shein"], urls: ["shein.com", "shein.in"]),
        GuardPreset(id: "pinterest", emoji: "📌", name: "Pinterest",
                    apps: ["pinterest"], urls: ["pinterest."]),
        GuardPreset(id: "netflix", emoji: "🍿", name: "Netflix",
                    apps: ["com.netflix", "netflix"], urls: ["netflix.com"]),
        GuardPreset(id: "roblox", emoji: "🎮", name: "Roblox",
                    apps: ["roblox"], urls: ["roblox.com"]),
        GuardPreset(id: "twitter", emoji: "🐦", name: "X / Twitter",
                    apps: ["com.atebits.tweetie", "twitter"], urls: ["twitter.com", "x.com/"]),
        GuardPreset(id: "reddit", emoji: "👽", name: "Reddit",
                    apps: ["reddit"], urls: ["reddit.com"]),
        GuardPreset(id: "snapchat", emoji: "👻", name: "Snapchat",
                    apps: ["snapchat"], urls: ["snapchat.com"]),
    ]

    var ruleName: String { "Guard: \(name)" }
}

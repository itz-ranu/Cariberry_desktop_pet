import Foundation

/// One line on her to-do list. Ticking it off makes her cheer, which is the point.
struct FocusTask: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var done = false
    var created = Date()
}

/// Background sound for studying, synthesised live like her voice (no audio files).
enum Ambience: String, CaseIterable, Codable {
    case off, lofi, rainy, cafe, night, rain, brown, waves

    /// The lo-fi stations (made by `LoFi`) and the plain nature sounds.
    static let stations: [Ambience] = [.lofi, .rainy, .cafe, .night]
    static let nature: [Ambience] = [.rain, .brown, .waves]

    var isMusic: Bool { Ambience.stations.contains(self) }

    var title: String {
        switch self {
        case .off: return "Off"
        case .lofi: return "Lo-fi Chill"
        case .rainy: return "Rainy Beats"
        case .cafe: return "Café Jazz"
        case .night: return "Night Study"
        case .rain: return "Rain"
        case .brown: return "Brown noise"
        case .waves: return "Waves"
        }
    }
    var short: String {
        switch self {
        case .lofi: return "Chill"
        case .rainy: return "Rainy"
        case .cafe: return "Café"
        case .night: return "Night"
        case .brown: return "Brown"
        default: return title
        }
    }
    var emoji: String {
        switch self {
        case .off: return "🔇"
        case .lofi: return "🎧"
        case .rainy: return "🌧️"
        case .cafe: return "☕️"
        case .night: return "🌙"
        case .rain: return "💧"
        case .brown: return "🌫️"
        case .waves: return "🌊"
        }
    }
    var mood: String {
        switch self {
        case .lofi: return "soft piano, mellow drums"
        case .rainy: return "rain on the window"
        case .cafe: return "swingy coffee-shop jazz"
        case .night: return "slow & glowy, for late shifts"
        case .rain: return "just rain"
        case .brown: return "deep, steady hush"
        case .waves: return "slow ocean swell"
        case .off: return ""
        }
    }
}

enum Focus {
    static let presets = [15, 25, 45, 60]
    static let goalChoices = [15, 30, 45, 60, 90, 120, 180, 240]

    static func timeText(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        if m >= 60 { return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m" }
        return "\(m)m"
    }
}

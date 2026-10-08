import SwiftUI

// fixed coordinate space the pup is drawn in, y down, facing right: the scene
// just scales this box to whatever window size it needs
enum Design {
    static let width: CGFloat = 200
    /// Headroom above the art's own top edge, so tall bunny ears and a hopping pet
    /// are never clipped by the canvas.
    static let lift: CGFloat = 26
    static let height: CGFloat = 168 + lift
    static let ground: CGFloat = 152     // where the paws touch, in art coordinates
    static let centerX: CGFloat = 100
}

// no outline: `ink` is the single dark tone for every facial mark so the face reads
// as plain linework on a painted body. These marks (eyes, tongue, love-heart, mood
// accents) stay identical across species so both still read as one family; only
// the coat itself (below, in `Coat`) is species-specific.
enum Fur {
    static let ink       = Color(red: 0.38, green: 0.34, blue: 0.40)
    static let tongue    = Color(red: 1.00, green: 0.58, blue: 0.68)
    static let tongueDk  = Color(red: 0.87, green: 0.40, blue: 0.52)
    static let heart     = Color(red: 0.93, green: 0.55, blue: 0.78)
    // no physical collar anymore, but keep these for the bubble border colours
    static let alertAccent = Color(red: 0.91, green: 0.40, blue: 0.45)
    static let warnAccent  = Color(red: 0.95, green: 0.72, blue: 0.40)
    static let blushAccent = Color(red: 0.95, green: 0.74, blue: 0.76)
}

/// The app's aesthetic moods. Pick one in Settings; it tints the control panel, the stats
/// window and every button. (The pets themselves never change.)
enum AppTheme: String, CaseIterable {
    case coquette, y2k, cottagecore, darkAcademia, boba, cyberPastel

    /// Read all over the UI every frame, so it's cached here and refreshed by `Prefs.theme`.
    nonisolated(unsafe) static var current: AppTheme = Prefs.theme

    /// Older versions had five plainer themes; they map onto the closest new mood.
    init?(legacy raw: String) {
        switch raw {
        case "lavender": self = .coquette
        case "strawberry": self = .y2k
        case "matcha": self = .cottagecore
        case "sky": self = .cyberPastel
        case "peach": self = .boba
        default: self.init(rawValue: raw)
        }
    }

    var title: String {
        switch self {
        case .coquette: return "Coquette Bows"
        case .y2k: return "Y2K Pink"
        case .cottagecore: return "Cottagecore"
        case .darkAcademia: return "Dark Academia"
        case .boba: return "Pastel Boba"
        case .cyberPastel: return "Cyber Pastel"
        }
    }
    var emoji: String {
        switch self {
        case .coquette: return "🎀"
        case .y2k: return "💿"
        case .cottagecore: return "🍵"
        case .darkAcademia: return "📜"
        case .boba: return "🧋"
        case .cyberPastel: return "🔮"
        }
    }
    var isDark: Bool { self == .darkAcademia }

    /// The main accent.
    var accent: Color {
        switch self {
        case .coquette: return Color(red: 0.80, green: 0.70, blue: 0.97)
        case .y2k: return Color(red: 1.00, green: 0.55, blue: 0.80)
        case .cottagecore: return Color(red: 0.62, green: 0.80, blue: 0.58)
        case .darkAcademia: return Color(red: 0.80, green: 0.60, blue: 0.40)
        case .boba: return Color(red: 0.86, green: 0.70, blue: 0.56)
        case .cyberPastel: return Color(red: 0.72, green: 0.66, blue: 1.00)
        }
    }
    /// The secondary accent, paired with it in gradients.
    var second: Color {
        switch self {
        case .coquette: return Color(red: 1.00, green: 0.74, blue: 0.84)
        case .y2k: return Color(red: 0.58, green: 0.90, blue: 1.00)
        case .cottagecore: return Color(red: 0.98, green: 0.88, blue: 0.66)
        case .darkAcademia: return Color(red: 0.72, green: 0.34, blue: 0.38)
        case .boba: return Color(red: 1.00, green: 0.80, blue: 0.82)
        case .cyberPastel: return Color(red: 0.62, green: 0.95, blue: 0.86)
        }
    }
    /// The saturated pair behind primary buttons and the active tab.
    var hot: (Color, Color) {
        switch self {
        case .coquette: return (Color(red: 0.96, green: 0.48, blue: 0.70), Color(red: 0.72, green: 0.54, blue: 0.95))
        case .y2k: return (Color(red: 1.00, green: 0.32, blue: 0.64), Color(red: 0.56, green: 0.50, blue: 1.00))
        case .cottagecore: return (Color(red: 0.46, green: 0.72, blue: 0.50), Color(red: 0.74, green: 0.82, blue: 0.40))
        case .darkAcademia: return (Color(red: 0.60, green: 0.24, blue: 0.30), Color(red: 0.78, green: 0.58, blue: 0.34))
        case .boba: return (Color(red: 0.80, green: 0.56, blue: 0.42), Color(red: 0.96, green: 0.66, blue: 0.74))
        case .cyberPastel: return (Color(red: 0.48, green: 0.42, blue: 1.00), Color(red: 0.24, green: 0.88, blue: 0.76))
        }
    }
    var pageTop: Color {
        switch self {
        case .coquette: return Color(red: 1.00, green: 0.968, blue: 0.978)
        case .y2k: return Color(red: 1.00, green: 0.950, blue: 0.980)
        case .cottagecore: return Color(red: 0.975, green: 0.985, blue: 0.955)
        case .darkAcademia: return Color(red: 0.145, green: 0.115, blue: 0.108)
        case .boba: return Color(red: 0.990, green: 0.965, blue: 0.940)
        case .cyberPastel: return Color(red: 0.960, green: 0.955, blue: 1.000)
        }
    }
    var pageBottom: Color {
        switch self {
        case .coquette: return Color(red: 0.965, green: 0.950, blue: 0.995)
        case .y2k: return Color(red: 0.925, green: 0.945, blue: 1.000)
        case .cottagecore: return Color(red: 0.925, green: 0.965, blue: 0.915)
        case .darkAcademia: return Color(red: 0.205, green: 0.150, blue: 0.135)
        case .boba: return Color(red: 0.970, green: 0.930, blue: 0.905)
        case .cyberPastel: return Color(red: 0.915, green: 0.975, blue: 0.965)
        }
    }
    var ink: Color {
        isDark ? Color(red: 0.96, green: 0.92, blue: 0.84) : Color(red: 0.32, green: 0.26, blue: 0.39)
    }
    /// A translucent surface colour: white on the light themes, warm parchment-dark on the dark one.
    var surface: Color { isDark ? Color(red: 0.92, green: 0.80, blue: 0.66) : .white }
}

/// Window chrome: the control panel, the stats window and anything else with a surface. A
/// soft milky pastel world, tinted by the chosen `AppTheme`.
enum UI {
    static var bg: Color { AppTheme.current.pageTop }
    static var bgLow: Color { AppTheme.current.pageBottom }
    static var card: Color { AppTheme.current.surface.opacity(AppTheme.current.isDark ? 0.09 : 0.80) }
    static var ink: Color { AppTheme.current.ink }
    static var inkSoft: Color { AppTheme.current.ink.opacity(0.58) }
    /// The theme's main accent (named for the original lavender).
    static var lilac: Color { AppTheme.current.accent }
    static var blush: Color { AppTheme.current.second }
    static let sage     = Color(red: 0.66, green: 0.88, blue: 0.78)   // "good" signal (mint)
    static let butter   = Color(red: 1.00, green: 0.88, blue: 0.64)   // "warn" signal
    static let peach    = Color(red: 1.00, green: 0.78, blue: 0.68)
    static let sky      = Color(red: 0.70, green: 0.85, blue: 1.00)
    static var track: Color { AppTheme.current.ink.opacity(0.09) }
    /// A translucent layer of the theme's surface colour: the frosted "glass" behind tiles,
    /// the tab bar and chips. White on light themes.
    static func glass(_ opacity: Double) -> Color {
        AppTheme.current.surface.opacity(AppTheme.current.isDark ? opacity * 0.14 : opacity)
    }
    /// The saturated gradient of every primary button and the active tab.
    static var hot: LinearGradient {
        let h = AppTheme.current.hot
        return LinearGradient(colors: [h.0, h.1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var page: LinearGradient {
        LinearGradient(colors: [bg, bgLow], startPoint: .top, endPoint: .bottom)
    }
    /// The same pair as plain colours, for angular gradients (progress rings).
    static var ringColors: [Color] { let h = AppTheme.current.hot; return [h.0, h.1, h.0] }
}

/// The original pastel-blue palette, kept for things that aren't any one species'
/// coat: food bowls/saucers, generic particles.
enum Dish {
    static let light = Color(red: 0.95, green: 0.96, blue: 1.00)
    static let mid   = Color(red: 0.85, green: 0.89, blue: 0.99)
    static let shade = Color(red: 0.70, green: 0.77, blue: 0.95)
}

/// One colourway for a species. Three coat tones sit close together on purpose (big
/// colour jumps are what make flat art look busy), plus a belly/muzzle tone and a
/// `patch` for whatever is dark on that animal (panda ears, fox socks, dog ears).
struct Coat: Equatable {
    let name: String
    let light: Color
    let mid: Color
    let shade: Color
    let belly: Color
    let patch: Color
    var stripes = false
    /// The same five tones as raw components (light, mid, shade, belly, patch) so
    /// gradients along a tail or a fur ruff can be mixed without resolving `Color`s.
    private let raw: [(Double, Double, Double)]

    init(_ name: String, light: (Double, Double, Double), mid: (Double, Double, Double),
         shade: (Double, Double, Double), belly: (Double, Double, Double),
         patch: (Double, Double, Double), stripes: Bool = false) {
        func c(_ t: (Double, Double, Double)) -> Color { Color(red: t.0, green: t.1, blue: t.2) }
        self.name = name
        self.light = c(light); self.mid = c(mid); self.shade = c(shade)
        self.belly = c(belly); self.patch = c(patch)
        self.stripes = stripes
        self.raw = [light, mid, shade, belly, patch]
    }

    static func == (a: Coat, b: Coat) -> Bool { a.name == b.name && a.raw[1] == b.raw[1] }

    /// A point `t` (0...1) of the way from one tone to another, by index into
    /// (light, mid, shade, belly, patch).
    func blend(_ i: Int, _ j: Int, _ t: Double) -> Color {
        let a = raw[i], b = raw[j]
        return Color(red: a.0 + (b.0 - a.0) * t, green: a.1 + (b.1 - a.1) * t, blue: a.2 + (b.2 - a.2) * t)
    }
}

enum AccessorySlot: String, CaseIterable {
    case rug, aura, body, neck, face, head, hair, held

    var title: String {
        switch self {
        case .rug: return "Rug under her"
        case .aura: return "Aura"
        case .body: return "Clothes"
        case .neck: return "Around her neck"
        case .face: return "On her face"
        case .head: return "On her head"
        case .hair: return "In her hair"
        case .held: return "In her paws"
        }
    }
}

/// Dress-up. She wears one item in each of eight slots at once (a beret, heart glasses, a
/// bow, a hoodie, pearls, an aura, a boba cup *and* a rug under her), so there are a lot of
/// looks to build. Most things are free; the fancy ones cost berries in the Sanctuary.
enum Accessory: String, CaseIterable, Codable {
    case none
    // rug
    case rugCoquette, rugCottage, rugY2K, rugCyber
    // aura
    case auraSparkles, auraHearts, auraStars
    // clothes
    case knitSweater, hoodie, angelWings, cape
    // neck
    case scarf, bandana, pearls, bell, bowtie
    // face
    case glasses, sunglasses, heartGlasses, lashes
    // head
    case crown, headphones, yuzu, beret, partyHat, halo
    // hair
    case bow, flower, starClip
    // held
    case boba, matcha, book, console

    var slot: AccessorySlot {
        switch self {
        case .none, .crown, .headphones, .yuzu, .beret, .partyHat, .halo: return .head
        case .rugCoquette, .rugCottage, .rugY2K, .rugCyber: return .rug
        case .auraSparkles, .auraHearts, .auraStars: return .aura
        case .knitSweater, .hoodie, .angelWings, .cape: return .body
        case .scarf, .bandana, .pearls, .bell, .bowtie: return .neck
        case .glasses, .sunglasses, .heartGlasses, .lashes: return .face
        case .bow, .flower, .starClip: return .hair
        case .boba, .matcha, .book, .console: return .held
        }
    }

    static func items(for slot: AccessorySlot) -> [Accessory] {
        allCases.filter { $0 != .none && $0.slot == slot }
    }

    /// Berries to unlock it in the Sanctuary. Zero means it's free from the start.
    var price: Int {
        switch self {
        case .rugCottage, .rugY2K, .rugCyber: return 45
        case .auraSparkles, .auraHearts: return 70
        case .auraStars: return 90
        case .knitSweater: return 50
        case .hoodie: return 60
        case .cape: return 75
        case .angelWings: return 90
        case .matcha: return 40
        case .console: return 55
        default: return 0
        }
    }

    var title: String {
        switch self {
        case .none: return "None"
        case .rugCoquette: return "Ribbon rug"
        case .rugCottage: return "Leaf rug"
        case .rugY2K: return "Heart rug"
        case .rugCyber: return "Glow rug"
        case .auraSparkles: return "Sparkles"
        case .auraHearts: return "Hearts"
        case .auraStars: return "Stars"
        case .knitSweater: return "Knit sweater"
        case .hoodie: return "Hoodie"
        case .angelWings: return "Angel wings"
        case .cape: return "Cape"
        case .scarf: return "Scarf"
        case .bandana: return "Bandana"
        case .pearls: return "Pearls"
        case .bell: return "Bell"
        case .bowtie: return "Bow tie"
        case .glasses: return "Glasses"
        case .sunglasses: return "Shades"
        case .heartGlasses: return "Hearts"
        case .lashes: return "Lashes"
        case .crown: return "Crown"
        case .headphones: return "Headphones"
        case .yuzu: return "Yuzu"
        case .beret: return "Beret"
        case .partyHat: return "Party hat"
        case .halo: return "Halo"
        case .bow: return "Bow"
        case .flower: return "Flower"
        case .starClip: return "Star clip"
        case .boba: return "Boba"
        case .matcha: return "Matcha"
        case .book: return "Book"
        case .console: return "Game"
        }
    }
    var emoji: String {
        switch self {
        case .none: return "✨"
        case .rugCoquette: return "🎀"
        case .rugCottage: return "🍃"
        case .rugY2K: return "💖"
        case .rugCyber: return "🔮"
        case .auraSparkles: return "✨"
        case .auraHearts: return "💕"
        case .auraStars: return "⭐️"
        case .knitSweater: return "🧶"
        case .hoodie: return "👚"
        case .angelWings: return "🪽"
        case .cape: return "🦸‍♀️"
        case .scarf: return "🧣"
        case .bandana: return "🏴‍☠️"
        case .pearls: return "📿"
        case .bell: return "🔔"
        case .bowtie: return "🎩"
        case .glasses: return "🤓"
        case .sunglasses: return "😎"
        case .heartGlasses: return "😍"
        case .lashes: return "💅"
        case .crown: return "👑"
        case .headphones: return "🎧"
        case .yuzu: return "🍊"
        case .beret: return "🎨"
        case .partyHat: return "🥳"
        case .halo: return "😇"
        case .bow: return "🎀"
        case .flower: return "🌼"
        case .starClip: return "⭐️"
        case .boba: return "🧋"
        case .matcha: return "🍵"
        case .book: return "📖"
        case .console: return "🎮"
        }
    }
}

/// What she's wearing right now: at most one thing per slot.
struct Outfit: Hashable {
    var rug: Accessory = .none
    var aura: Accessory = .none
    var body: Accessory = .none
    var neck: Accessory = .none
    var face: Accessory = .none
    var head: Accessory = .none
    var hair: Accessory = .none
    var held: Accessory = .none

    init(head: Accessory = .none, face: Accessory = .none, neck: Accessory = .none,
         hair: Accessory = .none, body: Accessory = .none, held: Accessory = .none,
         aura: Accessory = .none, rug: Accessory = .none) {
        self.head = head; self.face = face; self.neck = neck; self.hair = hair
        self.body = body; self.held = held; self.aura = aura; self.rug = rug
    }

    subscript(slot: AccessorySlot) -> Accessory {
        get {
            switch slot {
            case .rug: return rug
            case .aura: return aura
            case .body: return body
            case .neck: return neck
            case .face: return face
            case .head: return head
            case .hair: return hair
            case .held: return held
            }
        }
        set {
            switch slot {
            case .rug: rug = newValue
            case .aura: aura = newValue
            case .body: body = newValue
            case .neck: neck = newValue
            case .face: face = newValue
            case .head: head = newValue
            case .hair: hair = newValue
            case .held: held = newValue
            }
        }
    }
    var isEmpty: Bool { AccessorySlot.allCases.allSatisfy { self[$0] == .none } }
    var count: Int { AccessorySlot.allCases.filter { self[$0] != .none }.count }
}

/// Little objects that make her corner of the screen feel lived-in. They sit beside her and
/// travel with her. Bought in the Sanctuary.
enum Decor: String, CaseIterable, Codable {
    case plant, lamp, books, fairyLights, teddy
    // little companions on the floor beside her
    case duck, bobaCup, cocoa
    // ambient particles drifting through her corner
    case sakura, leaves, rainDrops, starSparkles

    var title: String {
        switch self {
        case .plant: return "Plant"
        case .lamp: return "Lamp"
        case .books: return "Book stack"
        case .fairyLights: return "Fairy lights"
        case .teddy: return "Teddy"
        case .duck: return "Rubber duck"
        case .bobaCup: return "Mini boba"
        case .cocoa: return "Cocoa mug"
        case .sakura: return "Sakura"
        case .leaves: return "Autumn leaves"
        case .rainDrops: return "Cosy rain"
        case .starSparkles: return "Starry night"
        }
    }
    var emoji: String {
        switch self {
        case .plant: return "🪴"
        case .lamp: return "🛋️"
        case .books: return "📚"
        case .fairyLights: return "✨"
        case .teddy: return "🧸"
        case .duck: return "🦆"
        case .bobaCup: return "🧋"
        case .cocoa: return "☕️"
        case .sakura: return "🌸"
        case .leaves: return "🍂"
        case .rainDrops: return "🌧️"
        case .starSparkles: return "🌟"
        }
    }
    var price: Int {
        switch self {
        case .books: return 70
        case .lamp: return 90
        case .plant: return 100
        case .teddy: return 120
        case .fairyLights: return 150
        case .duck, .bobaCup, .cocoa: return 60
        case .sakura, .leaves, .rainDrops: return 80
        case .starSparkles: return 110
        }
    }
    /// Drifting particles rather than an object.
    var isAmbient: Bool { self == .sakura || self == .leaves || self == .rainDrops || self == .starSparkles }
}

/// Which synthesised voice a species uses: see `SoundKit`.
enum Voice { case dog, cat, squeak }

enum Species: String, CaseIterable, Codable {
    case cat, dog, bunny, fox, panda, hamster, axolotl, capybara

    var displayName: String {
        switch self {
        case .cat: return "Kitten"
        case .dog: return "Puppy"
        case .bunny: return "Bunny"
        case .fox: return "Fox"
        case .panda: return "Panda"
        case .hamster: return "Hamster"
        case .axolotl: return "Axolotl"
        case .capybara: return "Capybara"
        }
    }

    var emoji: String {
        switch self {
        case .cat: return "🐱"
        case .dog: return "🐶"
        case .bunny: return "🐰"
        case .fox: return "🦊"
        case .panda: return "🐼"
        case .hamster: return "🐹"
        case .axolotl: return "🦎"
        case .capybara: return "🦫"
        }
    }

    var blurb: String {
        switch self {
        case .cat: return "Washes her face, purrs"
        case .dog: return "Floppy ears, big wags"
        case .bunny: return "Long ears, tiny hops"
        case .fox: return "Bushy tail, cheeky"
        case .panda: return "Round, sleepy, huggable"
        case .hamster: return "Pocket-sized, stuffs cheeks"
        case .axolotl: return "Forever smiling, feathery gills"
        case .capybara: return "Calm. Unbothered. Loved by all"
        }
    }

    var voice: Voice {
        switch self {
        case .cat: return .cat
        case .dog, .fox, .panda: return .dog
        case .bunny, .hamster, .axolotl, .capybara: return .squeak
        }
    }

    /// Scales the dog voice's pitch so a fox yips and a panda woofs low.
    var pitch: Double {
        switch self {
        case .fox: return 1.35
        case .panda: return 0.8
        default: return 1
        }
    }

    /// Built once: `coats` is read every frame, and constructing colours that often is waste.
    private static let coatTable: [Species: [Coat]] = Dictionary(uniqueKeysWithValues: Species.allCases.map { ($0, $0.makeCoats()) })
    var coats: [Coat] { Self.coatTable[self] ?? [] }

    private func makeCoats() -> [Coat] {
        switch self {
        case .cat: return [
            Coat("Lilac", light: (0.98, 0.95, 1.0), mid: (0.84, 0.78, 0.97), shade: (0.66, 0.58, 0.88),
                 belly: (1, 0.98, 1.0), patch: (0.66, 0.58, 0.88)),
            Coat("Ginger", light: (1.0, 0.89, 0.72), mid: (0.98, 0.72, 0.45), shade: (0.84, 0.52, 0.28),
                 belly: (1, 0.95, 0.87), patch: (0.84, 0.50, 0.26), stripes: true),
            Coat("Cloud", light: (1, 1, 1), mid: (0.95, 0.94, 0.97), shade: (0.79, 0.78, 0.87),
                 belly: (1, 1, 1), patch: (0.79, 0.78, 0.87)),
        ]
        case .dog: return [
            Coat("Biscuit", light: (1.0, 0.93, 0.80), mid: (0.94, 0.79, 0.56), shade: (0.80, 0.60, 0.39),
                 belly: (1, 0.97, 0.90), patch: (0.72, 0.51, 0.32)),
            Coat("Snow", light: (1, 0.99, 0.99), mid: (0.97, 0.94, 0.94), shade: (0.82, 0.74, 0.74),
                 belly: (1, 1, 1), patch: (0.80, 0.68, 0.68)),
            Coat("Cocoa", light: (0.86, 0.70, 0.56), mid: (0.68, 0.50, 0.38), shade: (0.52, 0.36, 0.27),
                 belly: (0.97, 0.89, 0.78), patch: (0.40, 0.27, 0.20)),
        ]
        case .bunny: return [
            Coat("Snow", light: (1, 1, 1), mid: (0.96, 0.94, 0.97), shade: (0.82, 0.78, 0.89),
                 belly: (1, 1, 1), patch: (0.82, 0.78, 0.89)),
            Coat("Caramel", light: (1.0, 0.93, 0.83), mid: (0.91, 0.75, 0.59), shade: (0.77, 0.59, 0.45),
                 belly: (1, 0.97, 0.92), patch: (0.77, 0.59, 0.45)),
            Coat("Lavender", light: (0.97, 0.95, 1), mid: (0.85, 0.81, 0.95), shade: (0.69, 0.63, 0.87),
                 belly: (1, 0.99, 1), patch: (0.69, 0.63, 0.87)),
        ]
        case .fox: return [
            Coat("Ember", light: (1.0, 0.84, 0.64), mid: (0.98, 0.61, 0.31), shade: (0.83, 0.43, 0.21),
                 belly: (1, 0.97, 0.93), patch: (0.42, 0.29, 0.26)),
            Coat("Arctic", light: (1, 1, 1), mid: (0.89, 0.93, 0.98), shade: (0.67, 0.75, 0.89),
                 belly: (1, 1, 1), patch: (0.48, 0.53, 0.66)),
        ]
        case .panda: return [
            Coat("Classic", light: (1, 1, 1), mid: (0.96, 0.96, 0.98), shade: (0.80, 0.80, 0.87),
                 belly: (1, 1, 1), patch: (0.30, 0.29, 0.35)),
            Coat("Cocoa", light: (1, 0.98, 0.94), mid: (0.97, 0.92, 0.86), shade: (0.85, 0.76, 0.68),
                 belly: (1, 0.98, 0.95), patch: (0.52, 0.36, 0.29)),
        ]
        case .hamster: return [
            Coat("Peach", light: (1.0, 0.94, 0.84), mid: (0.99, 0.82, 0.60), shade: (0.89, 0.64, 0.42),
                 belly: (1, 0.98, 0.95), patch: (0.94, 0.72, 0.49)),
            Coat("Mochi", light: (1, 1, 1), mid: (0.95, 0.94, 0.96), shade: (0.79, 0.78, 0.85),
                 belly: (1, 1, 1), patch: (0.84, 0.79, 0.88)),
        ]
        case .axolotl: return [
            Coat("Strawberry", light: (1.0, 0.94, 0.96), mid: (1.0, 0.80, 0.87), shade: (0.94, 0.62, 0.74),
                 belly: (1, 0.97, 0.98), patch: (0.98, 0.50, 0.62)),
            Coat("Mint", light: (0.94, 1.0, 0.97), mid: (0.76, 0.94, 0.87), shade: (0.55, 0.79, 0.72),
                 belly: (0.98, 1, 0.99), patch: (0.98, 0.56, 0.66)),
            Coat("Lilac", light: (0.98, 0.95, 1.0), mid: (0.87, 0.80, 0.97), shade: (0.70, 0.60, 0.88),
                 belly: (1, 0.98, 1), patch: (0.96, 0.52, 0.72)),
        ]
        case .capybara: return [
            Coat("Toast", light: (0.90, 0.75, 0.57), mid: (0.76, 0.57, 0.40), shade: (0.60, 0.42, 0.29),
                 belly: (0.93, 0.80, 0.63), patch: (0.47, 0.31, 0.21)),
            Coat("Honey", light: (0.99, 0.86, 0.62), mid: (0.90, 0.69, 0.42), shade: (0.74, 0.52, 0.28),
                 belly: (1.0, 0.91, 0.74), patch: (0.58, 0.38, 0.20)),
        ]
        }
    }
}

enum Emotion: String, CaseIterable {
    case neutral
    case happy
    case love
    case excited
    case sleepy
    case hungry
    case angry      // the "GO BACK TO WORK" face
    case sad
    case playful
    case eating
    case alert
    case dizzy      // being carried around
    case curious    // your cursor is right next to her
    case shy        // just arrived after being called over
    case proud      // just crushed a focus timer
    case worried    // genuinely neglected, worse than plain sad/hungry
    case bored      // ignored for a long stretch while awake
    case blissful   // everything is perfect at once, rare and special
    case moody      // feeling meh: arms crossed, mildly unimpressed
    case cozy       // warm and snuggly
    case hyped      // buzzing with energy
    case vibing     // nodding along to music

    var emoji: String {
        switch self {
        case .neutral:  return "🐶"
        case .happy:    return "😊"
        case .love:     return "💗"
        case .excited:  return "🤩"
        case .sleepy:   return "😴"
        case .hungry:   return "🍖"
        case .angry:    return "😤"
        case .sad:      return "🥺"
        case .playful:  return "🎾"
        case .eating:   return "😋"
        case .alert:    return "👀"
        case .dizzy:    return "😵‍💫"
        case .curious:  return "🤔"
        case .shy:      return "🙈"
        case .proud:    return "🥹"
        case .worried:  return "😟"
        case .bored:    return "😑"
        case .blissful: return "✨"
        case .moody:    return "😒"
        case .cozy:     return "☕️"
        case .hyped:    return "🎉"
        case .vibing:   return "🎧"
        }
    }

    var label: String {
        switch self {
        case .neutral:  return "chilling"
        case .happy:    return "happy"
        case .love:     return "in love with you"
        case .excited:  return "SO excited"
        case .sleepy:   return "sleepy"
        case .hungry:   return "hungry"
        case .angry:    return "disappointed in you"
        case .sad:      return "a little sad"
        case .playful:  return "playful"
        case .eating:   return "eating"
        case .alert:    return "watching you"
        case .dizzy:    return "wheee"
        case .curious:  return "curious about you"
        case .shy:      return "a little shy"
        case .proud:    return "so proud"
        case .worried:  return "worried about you"
        case .bored:    return "bored"
        case .blissful: return "perfectly happy"
        case .moody:    return "in a mood"
        case .cozy:     return "all cozy"
        case .hyped:    return "so hyped"
        case .vibing:   return "vibing"
        }
    }

    var accent: Color {
        switch self {
        case .angry:   return Fur.alertAccent
        case .love, .proud, .blissful, .hyped: return UI.blush
        case .cozy: return UI.peach
        case .moody: return UI.butter
        case .sleepy:  return UI.lilac
        case .hungry, .worried: return UI.butter
        case .shy:     return UI.blush
        default:       return UI.lilac
        }
    }
}

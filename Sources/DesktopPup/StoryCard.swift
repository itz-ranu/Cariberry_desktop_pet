import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

/// What goes on a story card. Plain values so it can be drawn from the live pet or from sample data.
struct StoryData {
    var name: String
    var species: Species
    var coat: Int
    var outfit: Outfit
    var focusMinutes: Double
    var goalMinutes: Int
    var streak: Int
    var sessions: Int
    var level: Int
    var title: String
    var doneTasks: [String]
    var habitsDone: Int
    var habitsTotal: Int
    var badges: [String]            // emoji of earned badges, newest last
    var badgeTotal: Int
    var date: String

    @MainActor
    init(pet: Pet) {
        name = pet.name
        species = pet.species
        coat = pet.coatIndex
        outfit = pet.outfit
        focusMinutes = pet.focusTodayMinutes
        goalMinutes = pet.dailyGoal
        streak = pet.streakDays
        sessions = pet.sessionsToday
        level = pet.level
        title = pet.levelTitle
        doneTasks = pet.tasks.filter(\.done).map(\.title)
        habitsDone = Habits.done().count
        habitsTotal = Habits.all.count
        let earned = Prefs.badges
        badges = Badges.all.filter { earned.contains($0.id) }.map(\.emoji)
        badgeTotal = Badges.all.count
        date = Date().formatted(.dateTime.weekday(.wide).day().month(.wide)).lowercased()
    }

    init(name: String, species: Species, coat: Int, outfit: Outfit, focusMinutes: Double, goalMinutes: Int, streak: Int,
         sessions: Int, level: Int, title: String, doneTasks: [String], habitsDone: Int, habitsTotal: Int,
         badges: [String], badgeTotal: Int, date: String) {
        self.name = name; self.species = species; self.coat = coat; self.outfit = outfit
        self.focusMinutes = focusMinutes; self.goalMinutes = goalMinutes; self.streak = streak
        self.sessions = sessions; self.level = level; self.title = title; self.doneTasks = doneTasks
        self.habitsDone = habitsDone; self.habitsTotal = habitsTotal; self.badges = badges
        self.badgeTotal = badgeTotal; self.date = date
    }
}

/// A 9:16 "study card" for stories, BeReal-style posts and Pinterest: a polaroid of her holding a
/// little handwritten sign with today's focus time, plus the to-dos you finished and your badges.
/// Drawn at 360×640 points, so rendering it at 3x gives a crisp 1080×1920 image.
struct StoryCard: View {
    var data: StoryData

    static let size = CGSize(width: 360, height: 640)
    private let ink = Color(red: 0.34, green: 0.24, blue: 0.36)
    private var progress: Double { min(1, data.focusMinutes / Double(max(1, data.goalMinutes))) }
    private var coat: Coat { data.species.coats[min(max(0, data.coat), data.species.coats.count - 1)] }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 1.0, green: 0.88, blue: 0.86), Color(red: 0.99, green: 0.84, blue: 0.93), Color(red: 0.86, green: 0.82, blue: 1.0)],
                           startPoint: .top, endPoint: .bottom)
            Circle().fill(.white.opacity(0.35)).frame(width: 240).offset(x: 140, y: -250)
            Circle().fill(Color(red: 1.0, green: 0.72, blue: 0.82).opacity(0.45)).frame(width: 260).offset(x: -150, y: 250)
            sparkles

            VStack(spacing: 10) {
                VStack(spacing: 1) {
                    Text("my study day ✨")
                        .font(.custom("Noteworthy-Bold", size: 24)).foregroundStyle(ink)
                    Text(data.date)
                        .font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(ink.opacity(0.55))
                }
                .padding(.top, 22)

                polaroid

                HStack(spacing: 8) {
                    stat("🔥", "\(data.streak)", data.streak == 1 ? "day streak" : "day streak")
                    stat("🍅", "\(data.sessions)", data.sessions == 1 ? "session" : "sessions")
                    stat("⭐️", "Lv \(data.level)", data.title)
                }
                .padding(.horizontal, 24)

                checklist.padding(.horizontal, 24)
                achievements.padding(.horizontal, 24)

                Spacer(minLength: 0)
                footer.padding(.bottom, 18)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipped()
    }

    // MARK: Pieces

    private var polaroid: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    LinearGradient(colors: [Color(red: 0.80, green: 0.90, blue: 1.0), Color(red: 1.0, green: 0.86, blue: 0.90)],
                                   startPoint: .top, endPoint: .bottom)
                    // her rug, if she has one on, else a soft patch of floor
                    Ellipse().fill(rugColor).frame(width: 190, height: 30).offset(y: -8)
                    CritterView(species: data.species, coat: data.coat,
                                pose: Pose(emotion: progress >= 1 ? .proud : .happy, phase: 0.42, outfit: data.outfit), scale: 0.72)
                        .stickerOutline(2.0)
                        .offset(y: -40)
                        .frame(height: 200, alignment: .bottom)
                    sign.offset(y: -6)
                }
                .frame(width: 270, height: 196)
                .clipped()
                Text("studying with \(data.name) 🐾")
                    .font(.custom("Noteworthy-Light", size: 15)).foregroundStyle(ink)
                    .frame(width: 270, height: 38)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.white)
                .shadow(color: .black.opacity(0.18), radius: 10, x: 2, y: 6))
            // washi tape
            Rectangle()
                .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.74, blue: 0.84).opacity(0.9), Color(red: 0.84, green: 0.76, blue: 1.0).opacity(0.9)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 80, height: 22).rotationEffect(.degrees(-4)).offset(y: -10)
        }
        .rotationEffect(.degrees(-2))
        .padding(.top, 6)
    }

    /// The sign she's holding up, with her paws on the bottom edge.
    private var sign: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                Text(Focus.timeText(data.focusMinutes))
                    .font(.custom("Noteworthy-Bold", size: 24)).foregroundStyle(ink)
                Text("focused today \(progress >= 1 ? "🏆" : "🔥")")
                    .font(.custom("Noteworthy-Bold", size: 13)).foregroundStyle(ink.opacity(0.8))
            }
            .padding(.horizontal, 14).padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(red: 1.0, green: 0.97, blue: 0.84))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color(red: 0.92, green: 0.78, blue: 0.62), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 3)
            )
            HStack {
                Ellipse().fill(coat.mid).frame(width: 20, height: 15)
                Spacer()
                Ellipse().fill(coat.mid).frame(width: 20, height: 15)
            }
            .frame(width: 128).offset(y: 5)
        }
        .rotationEffect(.degrees(2))
    }

    private var rugColor: Color {
        switch data.outfit.rug {
        case .rugCoquette: return Color(red: 1.0, green: 0.78, blue: 0.86)
        case .rugCottage: return Color(red: 0.74, green: 0.90, blue: 0.70)
        case .rugY2K: return Color(red: 1.0, green: 0.66, blue: 0.80)
        case .rugCyber: return Color(red: 0.72, green: 0.70, blue: 1.0)
        default: return .white.opacity(0.5)
        }
    }

    private var checklist: some View {
        let tasks = Array(data.doneTasks.prefix(2))
        return VStack(alignment: .leading, spacing: 5) {
            Text(tasks.isEmpty ? "tiny habits \(data.habitsDone)/\(data.habitsTotal) 🌷" : "done today ✅")
                .font(.system(size: 10.5, weight: .heavy, design: .rounded)).foregroundStyle(ink.opacity(0.6)).textCase(.uppercase)
            if tasks.isEmpty {
                ProgressView(value: Double(data.habitsDone), total: Double(max(1, data.habitsTotal))).tint(Color(red: 0.95, green: 0.55, blue: 0.72))
            }
            ForEach(tasks, id: \.self) { t in
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(red: 0.95, green: 0.55, blue: 0.72)).font(.system(size: 14))
                    Text(t).font(.custom("Noteworthy-Light", size: 14)).foregroundStyle(ink).lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            if data.doneTasks.count > 2 {
                Text("+ \(data.doneTasks.count - 2) more").font(.system(size: 10.5, weight: .semibold, design: .rounded)).foregroundStyle(ink.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.62)))
    }

    private var achievements: some View {
        HStack(spacing: 6) {
            Text("🏆").font(.system(size: 15))
            Text(data.badges.suffix(7).joined(separator: " "))
                .font(.system(size: 17)).lineLimit(1)
            Spacer(minLength: 0)
            Text("\(data.badges.count)/\(data.badgeTotal)")
                .font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(ink.opacity(0.6))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Capsule().fill(.white.opacity(0.62)))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let qr = Self.qr(for: "https://github.com/itz-ranu/Cariberry") {
                Image(nsImage: qr).interpolation(.none).resizable().frame(width: 44, height: 44)
                    .padding(4).background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("studying with Cariberry 🐾")
                    .font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(ink)
                Text("a tiny pet who keeps you focused")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded)).foregroundStyle(ink.opacity(0.6))
            }
        }
    }

    private static let sparklePoints: [(String, CGFloat, CGFloat, CGFloat)] = [
        ("✨", 40, 70, 14), ("🌸", 310, 120, 16), ("⭐️", 24, 300, 12), ("💗", 330, 360, 13),
        ("✨", 16, 520, 15), ("🌸", 346, 560, 12), ("⭐️", 180, 40, 11), ("💗", 12, 430, 12), ("✨", 336, 250, 10),
    ]

    private var sparkles: some View {
        ZStack {
            ForEach(0..<Self.sparklePoints.count, id: \.self) { i in
                let p = Self.sparklePoints[i]
                Text(p.0).font(.system(size: p.3)).opacity(0.55).position(x: p.1, y: p.2)
            }
        }
    }

    private func stat(_ emoji: String, _ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(emoji).font(.system(size: 16))
            Text(value).font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(ink)
            Text(label).font(.system(size: 9, weight: .semibold, design: .rounded)).foregroundStyle(ink.opacity(0.6)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8).padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.62)))
    }

    static func qr(for text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let out = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: out.extent.width, height: out.extent.height))
    }
}

/// Turning the card into a picture you can save or paste.
@MainActor
enum StoryShare {
    /// 1080×1920, the size Stories and Reels want.
    static func image(_ data: StoryData) -> NSImage? {
        let r = ImageRenderer(content: StoryCard(data: data))
        r.scale = 3
        return r.nsImage
    }

    static func png(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Saves to the Desktop and reveals it. Returns the path, or nil if it couldn't be written.
    static func save(_ image: NSImage, name: String) -> URL? {
        guard let data = png(image),
              let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else { return nil }
        let stamp = Date().formatted(.iso8601.year().month().day())
        let url = desktop.appendingPathComponent("\(name) study card \(stamp).png")
        guard (try? data.write(to: url)) != nil else { return nil }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return url
    }

    static func copy(_ image: NSImage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }
}

/// The little preview window: the card, and three ways to send it off.
struct StoryPreview: View {
    var data: StoryData
    var image: NSImage?
    var save: () -> Void
    var copy: () -> Void
    var share: () -> Void
    var close: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                StoryCard(data: data)
                    .scaleEffect(0.6)
                    .frame(width: StoryCard.size.width * 0.6, height: StoryCard.size.height * 0.6)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 22, height: 22).background(Circle().fill(.black.opacity(0.45)))
                }
                .buttonStyle(.plain).padding(8)
            }
            HStack(spacing: 6) {
                Button("Save", action: save).buttonStyle(ChipStyle())
                Button("Copy", action: copy).buttonStyle(ChipStyle(tint: UI.blush))
                Button("Share…", action: share).buttonStyle(ChipStyle(tint: UI.sage))
            }
        }
        .padding(16)
    }
}

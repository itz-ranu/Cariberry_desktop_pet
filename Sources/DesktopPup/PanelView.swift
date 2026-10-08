import SwiftUI

/// The whole control surface in one place, four tabs along the bottom, everything a tap
/// away, no nested menus. Opens from the menu bar icon or by right-clicking her.
struct PanelView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case home, focus, closet, settings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .home: return "Home"
            case .focus: return "Focus"
            case .closet: return "Closet"
            case .settings: return "Settings"
            }
        }
        var icon: String {
            switch self {
            case .home: return "heart.fill"
            case .focus: return "timer"
            case .closet: return "sparkles"
            case .settings: return "gearshape.fill"
            }
        }
    }

    enum WardrobePage: String, CaseIterable {
        case her = "Her", closet = "Outfit", shop = "Shop"
    }

    static let width: CGFloat = 372
    static let height: CGFloat = 660

    @ObservedObject var pet: Pet
    @ObservedObject var actions: PanelActions
    @State var tab: Tab
    /// Bumped on a timer and after preference changes, so toggles re-read `Prefs`.
    @State var refresh = 0
    @State var customOpen = false
    @State var customMinutes = 30
    /// The session length the big Start button will use.
    @State var selectedMinutes = 25
    @State var moreCare = false
    @State var habitsOpen = false
    @State var moreOptions = false
    @State var nameDraft = ""
    @State var blockDraft = ""
    @State var taskDraft = ""
    @State var keyDraft = ""
    var welcome: Bool
    /// Which page of the Wardrobe tab is showing.
    @State var wardrobePage: WardrobePage = .her
    @State var shopMessage: String?
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    init(pet: Pet, actions: PanelActions, startTab: Tab = .home, welcome: Bool = false) {
        self.pet = pet
        self.actions = actions
        self.welcome = welcome
        _tab = State(initialValue: startTab)
        _nameDraft = State(initialValue: pet.name)
    }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                header
                ScrollView(.vertical, showsIndicators: false) {
                    Group {
                        switch tab {
                        case .home: home
                        case .focus: focus
                        case .closet: wardrobe
                        case .settings: settings
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                    .padding(.bottom, 12)
                }
                tabBar
            }
        }
        .frame(width: Self.width, height: Self.height)
        .environment(\.colorScheme, AppTheme.current.isDark ? .dark : .light)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in refresh += 1 }
    }

    /// Milky pink to lavender, with two soft blobs of colour so it never reads as a flat card.
    private var background: some View {
        ZStack {
            UI.page
            Circle().fill(UI.blush.opacity(0.35)).frame(width: 260).blur(radius: 60).offset(x: 130, y: -250)
            Circle().fill(UI.lilac.opacity(0.30)).frame(width: 280).blur(radius: 70).offset(x: -150, y: 260)
        }
        .clipped()
    }

    // MARK: Header

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12: return "good morning ☀️"
        case 12..<17: return "hi bestie 🌷"
        case 17..<22: return "good evening 🌙"
        default: return "night owl hours 🦉"
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [UI.blush.opacity(0.7), UI.lilac.opacity(0.6)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Circle().strokeBorder(UI.glass(0.9), lineWidth: 2.5)
                    AnimatedPet(pet: pet, scale: 0.42)
                        .offset(x: -3, y: -8)
                        .frame(width: 70, height: 70)
                        .clipShape(Circle())
                }
                .frame(width: 70, height: 70)
                .shadow(color: UI.lilac.opacity(0.4), radius: 8, y: 3)

                VStack(alignment: .leading, spacing: 3) {
                    Text(pet.name)
                        .font(.system(size: 21, weight: .heavy, design: .rounded))
                        .foregroundStyle(UI.ink)
                        .lineLimit(1)
                    Text("\(greeting) · \(pet.emotion.label)")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(UI.inkSoft)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { actions.openChat() } label: {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(UI.hot))
                }
                .buttonStyle(.plain)
                .help("Chat with \(pet.name)")
                .accessibilityLabel("Open chat")
                let sound = _refreshed(Prefs.sounds)
                Button { pet.toggleMute(); refresh += 1 } label: {
                    Image(systemName: sound ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(sound ? UI.inkSoft : Color.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(sound ? AnyShapeStyle(UI.glass(0.7)) : AnyShapeStyle(UI.hot)))
                }
                .buttonStyle(.plain)
                .help(sound ? "Mute everything (library mode)" : "Sound is off. Tap to turn it back on")
                .accessibilityLabel(sound ? "Mute sounds" : "Unmute sounds")
            }

            // level, streak and berries on one line, with the level bar filling the rest of it
            HStack(spacing: 10) {
                Text("Lv \(pet.level)").font(.system(size: 11.5, weight: .heavy, design: .rounded)).foregroundStyle(UI.ink)
                if pet.streakDays > 0 { Text("🔥 \(pet.streakDays)").font(.system(size: 11.5, weight: .heavy, design: .rounded)).foregroundStyle(UI.ink) }
                Text("🍓 \(pet.berries)").font(.system(size: 11.5, weight: .heavy, design: .rounded)).foregroundStyle(UI.ink)
                bar(pet.levelProgress, [UI.lilac, UI.blush], height: 8)
            }
            .help("\(pet.levelTitle): \(Int(pet.xpIntoLevel)) / \(Int(pet.xpForThisLevel)) XP")
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    // MARK: Tab bar

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { t in
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.78)) { tab = t }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.icon).font(.system(size: 15, weight: .bold))
                        Text(t.title).font(.system(size: 10.5, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(tab == t ? Color.white : UI.inkSoft)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(tab == t ? AnyShapeStyle(UI.hot) : AnyShapeStyle(Color.clear))
                            .shadow(color: tab == t ? UI.lilac.opacity(0.6) : .clear, radius: 6, y: 3)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == t ? .isSelected : [])
            }
        }
        .padding(6)
        .background(Capsule().fill(UI.glass(0.88)).shadow(color: UI.ink.opacity(0.10), radius: 10, y: 4))
        .clipShape(Capsule())
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .padding(.top, 4)
    }

    // MARK: Home

    private var home: some View {
        VStack(spacing: 12) {
            todayHero
            careSection
            moodCard
            vitalsCard
            watchCard
        }
    }

    /// Today at a glance, with the one button that matters. Tapping the numbers opens her scrapbook.
    private var todayHero: some View {
        card {
            VStack(spacing: 14) {
                Button { actions.showStats() } label: {
                    HStack(spacing: 14) {
                        ring(pet.goalProgress, size: 62, line: 8) {
                            Text("\(Int(pet.goalProgress * 100))%")
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundStyle(UI.ink)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Today's focus")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(UI.inkSoft).textCase(.uppercase).kerning(0.5)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(Focus.timeText(pet.focusTodayMinutes))
                                    .font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(UI.ink)
                                Text("of \(Focus.timeText(Double(pet.dailyGoal)))")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(UI.inkSoft)
                            }
                            let left = pet.tasks.filter { !$0.done }.count
                            Text(left == 0 ? "no tasks waiting ✨" : "\(left) task\(left == 1 ? "" : "s") to go")
                                .font(.system(size: 11.5, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
                        }
                        Spacer(minLength: 0)
                        VStack(spacing: 2) {
                            Image(systemName: "chart.bar.fill").font(.system(size: 13, weight: .bold))
                            Text("Stats").font(.system(size: 9.5, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(UI.inkSoft)
                        .padding(.horizontal, 9).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(UI.lilac.opacity(0.2)))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(reduce: reduceMotion))
                .help("Open your stats")
                .accessibilityLabel("Today's focus \(Focus.timeText(pet.focusTodayMinutes)) of \(Focus.timeText(Double(pet.dailyGoal))). Open stats")
                startButton
            }
        }
    }

    /// Starts a session, or, while one is running, shows how long is left and jumps to it.
    var startButton: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let left = pet.timerRemaining {
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.78)) { tab = .focus }
                } label: {
                    Text("\(pet.onBreak ? "🧋 break" : "📖 focusing") · \(String(format: "%d:%02d", Int(left) / 60, Int(left) % 60)) left")
                        .font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(UI.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Capsule().fill(UI.lilac.opacity(0.3)))
                }
                .buttonStyle(PressStyle(reduce: reduceMotion))
            } else {
                Button { actions.startFocus(Double(selectedMinutes)) } label: {
                    Text("Start \(selectedMinutes) min focus  ✨")
                        .font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Capsule().fill(UI.hot).shadow(color: UI.lilac.opacity(0.6), radius: 8, y: 4))
                }
                .buttonStyle(PressStyle(reduce: reduceMotion))
            }
        }
    }

    /// Four everyday ways to look after her, and a "More" for the rest.
    private var careSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Look after her").font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(UI.inkSoft)
                Spacer()
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) { moreCare.toggle() }
                } label: {
                    HStack(spacing: 3) {
                        Text(moreCare ? "Less" : "More")
                        Image(systemName: "chevron.right").rotationEffect(.degrees(moreCare ? -90 : 0))
                    }
                    .font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(UI.inkSoft)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            careGrid
        }
    }

    private var careGrid: some View {
        let napping = pet.act == .sleep
        // (emoji, title, tooltip, colour, highlighted?, action)
        let tiles: [(String, String, String, Color, Bool, () -> Void)] = [
            ("🍖", "Feed", "A full meal", UI.peach, false, actions.feed),
            ("🎾", "Play", "Zoomies! (or a happy dance if she's staying put)", UI.sky, false, actions.play),
            ("🫶", "Pet", "Scritch scritch", UI.blush, false, actions.petIt),
            (pet.staying ? "📍" : "🪑", pet.staying ? "Staying" : "Stay", pet.staying ? "She's sitting still. Tap to let her roam again." : "Tell her to sit still right where she is", UI.sage, pet.staying, actions.toggleStay),
            ("🦴", "Treat", "A little snack", UI.butter, false, actions.treat),
            ("📣", "Come", "Closes this, then she runs to your cursor. Move it where you want her!", UI.lilac, false, actions.come),
            ("💃", "Dance", "A little dance party", UI.blush, false, actions.dance),
            (napping ? "☀️" : "😴", napping ? "Wake" : "Nap", napping ? "Rise and shine" : "Tuck her in", UI.sky, false, actions.nap),
        ]
        let shown = moreCare ? tiles : Array(tiles.prefix(4))
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(0..<shown.count, id: \.self) { i in
                let t = shown[i]
                Button(action: t.5) {
                    VStack(spacing: 4) {
                        Text(t.0).font(.system(size: 24))
                        Text(t.1)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(UI.ink)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(LinearGradient(colors: [t.3.opacity(t.4 ? 0.9 : 0.55), t.3.opacity(t.4 ? 0.6 : 0.28)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(t.4 ? UI.ink.opacity(0.35) : .white.opacity(0.8), lineWidth: t.4 ? 2 : 1.5))
                }
                .buttonStyle(PressStyle(reduce: reduceMotion))
                .help(t.2)
                .accessibilityLabel(t.1)
            }
        }
    }

    private var watchCard: some View {
        let icon = pet.lastVerdict == .work ? "💗" : (pet.lastVerdict == .distraction ? "😤" : "😐")
        return card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(icon).font(.system(size: 24))
                    VStack(alignment: .leading, spacing: 1) {
                        label("Watching")
                        Text(pet.currentActivity)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(UI.ink).lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        label(pet.inFlow ? "🌊 In flow" : "Streak")
                        Text("\(Int(pet.focusSeconds / 60)) min")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(UI.ink)
                    }
                }
                if !pet.presenceNote.isEmpty {
                    Text("⏸ \(pet.presenceNote). Focus time isn't counting until you're back.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(UI.inkSoft)
                } else if pet.inFlow {
                    Text("20+ minutes without a break: XP and berries are ×1.5 🌊")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(UI.inkSoft)
                }
                if !Prefs.browserAwareness {
                    notice("Turn on browser awareness so I can catch Reels", "Turn on") {
                        actions.setBrowserAwareness(true); refresh += 1
                    }
                }
                if actions.monitor.automationDenied {
                    Text("macOS blocked browser access. Allow it in Settings ▸ Privacy ▸ Automation.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Fur.alertAccent)
                }
                if let undo = actions.monitor.undoLabel {
                    notice("Closed “\(undo.prefix(28))”", "Reopen") { actions.undoLastClose(); refresh += 1 }
                }
            }
        }
    }

    private var vitalsCard: some View {
        card {
            HStack(spacing: 14) {
                vitalColumn("🍖", "Belly", pet.hunger, UI.peach)
                vitalColumn("😊", "Happy", pet.happiness, UI.blush)
                vitalColumn("⚡️", "Energy", pet.energy, UI.sage)
                vitalColumn("💗", "Love", pet.affection, UI.lilac)
            }
        }
    }

    private func vitalColumn(_ emoji: String, _ title: String, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Text(emoji).font(.system(size: 18))
            bar(value, [color, color.opacity(0.8)], height: 6)
            Text(title).font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(UI.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(Int(value * 100)) percent")
    }

    private func vital(_ title: String, _ value: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(UI.inkSoft)
                Spacer()
                Text("\(Int(value * 100))%").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(UI.ink)
            }
            bar(value, [color, color.opacity(0.8)], height: 8)
        }
    }

    // MARK: Focus

    private var focus: some View {
        VStack(spacing: 12) {
            timerCard
            todayStrip
            soundCard
            tasksCard
            habitsFold
        }
    }

    /// The day's goal on one slim card: streak, sessions, minutes so far, and a goal picker.
    private var todayStrip: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    label("Today")
                    Spacer()
                    pill("🔥 \(pet.streakDays) day\(pet.streakDays == 1 ? "" : "s")", UI.peach)
                    pill("✅ \(pet.sessionsToday) session\(pet.sessionsToday == 1 ? "" : "s")", UI.sage)
                }
                HStack(spacing: 8) {
                    Text(Focus.timeText(pet.focusTodayMinutes))
                        .font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(UI.ink)
                    Text("of").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(UI.inkSoft)
                    Picker("Goal", selection: Binding(get: { pet.dailyGoal }, set: { pet.setGoal($0) })) {
                        ForEach(Array(Set(Focus.goalChoices + [pet.dailyGoal])).sorted(), id: \.self) {
                            Text(Focus.timeText(Double($0))).tag($0)
                        }
                    }
                    .labelsHidden().frame(maxWidth: 90).help("Change your daily goal")
                    Spacer(minLength: 0)
                    Button { actions.showStats() } label: { Label("Stats", systemImage: "chart.bar.fill") }
                        .buttonStyle(ChipStyle())
                }
                bar(pet.goalProgress, [UI.lilac, UI.blush], height: 10)
            }
        }
    }

    /// Tiny habits fold away: they're a nice-to-have, not the first thing on the Focus tab.
    private var habitsFold: some View {
        let done = _refreshed(pet.habitsDone)
        return VStack(spacing: 8) {
            if habitsOpen {
                habitsCard
            } else {
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) { habitsOpen = true }
                } label: {
                    card {
                        HStack {
                            label("🌷 Tiny habits")
                            Spacer()
                            pill("\(done.count)/\(Habits.all.count)", done.count == Habits.all.count ? UI.sage : UI.blush)
                            Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(UI.inkSoft)
                        }
                    }
                }
                .buttonStyle(PressStyle(reduce: reduceMotion))
            }
            if habitsOpen {
                Button("Hide habits") { withAnimation(reduceMotion ? nil : .default) { habitsOpen = false } }
                    .buttonStyle(ChipStyle(tint: UI.blush))
            }
        }
    }

    private var timerCard: some View {
        card {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                if let left = pet.timerRemaining { runningTimer(left) } else { idleTimer }
            }
        }
    }

    private func runningTimer(_ left: TimeInterval) -> some View {
        let m = Int(left) / 60, s = Int(left) % 60
        let progress = pet.timerTotal > 0 ? 1 - left / pet.timerTotal : 0
        return VStack(spacing: 10) {
            HStack {
                label(pet.onBreak ? "🧋 Break time" : "📖 Studying together")
                Spacer()
            }
            ring(progress, size: 130, line: 13, colors: pet.onBreak ? [UI.sage, UI.sky] : nil) {
                VStack(spacing: 0) {
                    Text(String(format: "%d:%02d", m, s))
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .monospacedDigit().foregroundStyle(UI.ink)
                    Text(pet.onBreak ? "sip sip" : "locked in")
                        .font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(UI.inkSoft)
                }
            }
            if !pet.onBreak, !pet.intention.isEmpty {
                Text("“\(pet.intention)”")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(UI.ink).lineLimit(2).multilineTextAlignment(.center)
            }
            Button(pet.onBreak ? "Skip break" : "Stop timer") { actions.stopTimer() }
                .buttonStyle(ChipStyle(tint: Fur.alertAccent))
        }
        .frame(maxWidth: .infinity)
    }

    private var idleTimer: some View {
        VStack(alignment: .leading, spacing: 11) {
            label("📖 Study with me")
            TextField("What are you working on?", text: $pet.intention)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(UI.track))
            HStack(spacing: 6) {
                ForEach(Focus.presets, id: \.self) { mins in
                    Button("\(mins)m") { selectedMinutes = mins; customOpen = false }
                        .buttonStyle(ChipStyle(tint: selectedMinutes == mins ? UI.lilac : UI.blush.opacity(0.6), on: selectedMinutes == mins))
                }
                Button(customOpen ? "Hide" : "Custom") {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { customOpen.toggle() }
                }
                .buttonStyle(ChipStyle(tint: UI.blush))
            }
            if customOpen {
                HStack {
                    Stepper(value: $selectedMinutes, in: 5...240, step: 5) {
                        Text("\(selectedMinutes) minutes")
                            .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(UI.ink)
                    }
                }
            }
            Button { actions.startFocus(Double(selectedMinutes)) } label: {
                Text("Start \(selectedMinutes) min focus  ✨")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(UI.hot).shadow(color: UI.lilac.opacity(0.6), radius: 8, y: 4))
            }
            .buttonStyle(PressStyle(reduce: reduceMotion))
            Text("She'll sit beside you with a book, and bring boba on your break.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(UI.inkSoft)
        }
    }

    private var soundCard: some View { musicCard(compact: false) }

    private var tasksCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    label("✅ Today's to-dos")
                    Spacer()
                    if pet.tasks.contains(where: \.done) {
                        Button("Clear done") { withAnimation(reduceMotion ? nil : .default) { pet.clearDoneTasks() } }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(UI.inkSoft)
                    }
                }
                HStack(spacing: 8) {
                    TextField("Add a tiny task…", text: $taskDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(UI.track))
                        .onSubmit(addTask)
                    Button(action: addTask) {
                        Image(systemName: "plus").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(UI.hot))
                    }
                    .buttonStyle(PressStyle(reduce: reduceMotion))
                    .disabled(taskDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Add task")
                }
                if pet.tasks.isEmpty {
                    Text("Nothing here yet. Add one small thing, and she'll cheer when you finish it.")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
                } else {
                    VStack(spacing: 6) {
                        ForEach(pet.tasks) { t in taskRow(t) }
                    }
                }
            }
        }
    }

    private func taskRow(_ t: FocusTask) -> some View {
        HStack(spacing: 10) {
            Button { withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6)) { pet.toggleTask(t.id) } } label: {
                Image(systemName: t.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(t.done ? AnyShapeStyle(UI.hot) : AnyShapeStyle(UI.inkSoft))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t.done ? "Mark not done" : "Mark done")
            Text(t.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(t.done ? UI.inkSoft : UI.ink)
                .strikethrough(t.done, color: UI.inkSoft)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button { pet.removeTask(t.id) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(UI.inkSoft)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete task")
        }
    }

    private func addTask() {
        pet.addTask(taskDraft)
        taskDraft = ""
    }

    // MARK: Settings

    private var settings: some View {
        VStack(spacing: 12) {
            card {
                VStack(alignment: .leading, spacing: 11) {
                    label("🎨 Look")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(AppTheme.allCases, id: \.self) { t in themeChip(t) }
                    }
                }
            }
            vibeCard
            card {
                VStack(alignment: .leading, spacing: 11) {
                    label("💗 Focus coach")
                    toggleRow("heart.fill", "Focus coaching", "Reacts to what you're doing",
                              bind({ Prefs.focusCoaching }, { Prefs.focusCoaching = $0 }))
                    toggleRow("safari.fill", "Watch my browser", "Reads your tab's title to spot Reels",
                              bind({ Prefs.browserAwareness }, actions.setBrowserAwareness))
                    toggleRow("xmark.circle.fill", "Close Reels tabs for me", "One warning first. Needs browser awareness",
                              bind({ Prefs.autoCloseReels }, actions.setAutoClose), enabled: Prefs.browserAwareness)
                    toggleRow("moon.fill", "Quiet hours", "No barking while you're winding down",
                              bind({ Prefs.quietHoursEnabled }, actions.setQuietHours))
                    if Prefs.quietHoursEnabled { quietHourPickers }
                }
            }
            appGuard
            card {
                VStack(alignment: .leading, spacing: 11) {
                    label("🐾 Her")
                    toggleRow("speaker.wave.2.fill", "Sounds", "Her little voice", bind({ Prefs.sounds }, actions.setSounds))
                    toggleRow("figure.walk", "Roam around", "Wander near where she sits", bind({ Prefs.roams }, actions.setRoams))
                    toggleRow("drop.fill", "Gentle reminders", "Water, a stretch, and an eye rest",
                              bind({ Prefs.reminders }, { Prefs.reminders = $0 }))
                    toggleRow("sun.max.fill", "Daily mood check-in", "A soft “how are we feeling?” each morning",
                              bind({ Prefs.dailyCheckIn }, { Prefs.dailyCheckIn = $0 }))
                    toggleRow("power.circle.fill", "Launch at login", nil,
                              bind({ LaunchAtLogin.isEnabled }, actions.setLaunchAtLogin))
                }
            }
            moreOptionsCard
            Button { actions.quit() } label: {
                Label("Quit \(pet.name)", systemImage: "power")
                    .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(UI.inkSoft)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(UI.glass(0.7)))
            }
            .buttonStyle(PressStyle(reduce: reduceMotion))
            Text("made with 💗 by Ranu")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(UI.inkSoft)
                .padding(.top, 2)
            HStack(spacing: 14) {
                Link("Privacy", destination: URL(string: "https://github.com/itz-ranu/Cariberry/blob/main/PRIVACY.md")!)
                Link("Terms", destination: URL(string: "https://github.com/itz-ranu/Cariberry/blob/main/TERMS.md")!)
                Link("Licences", destination: URL(string: "https://github.com/itz-ranu/Cariberry/blob/main/THIRD_PARTY_NOTICES.md")!)
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(UI.inkSoft)
            Text("For ages 13+. Independent: not affiliated with or endorsed by Apple, Microsoft, Google, OpenAI or any other company named here.")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(UI.inkSoft.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    /// The things most people never touch, folded away so Settings stays short.
    private var moreOptionsCard: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) { moreOptions.toggle() }
            } label: {
                card {
                    HStack {
                        label("⚙️ More options")
                        Spacer()
                        Image(systemName: "chevron.down").rotationEffect(.degrees(moreOptions ? 180 : 0))
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(UI.inkSoft)
                    }
                }
            }
            .buttonStyle(PressStyle(reduce: reduceMotion))
            if moreOptions {
                card {
                    VStack(alignment: .leading, spacing: 11) {
                        toggleRow("music.note", "Bop to my music", "Needs Screen & System Audio permission. She nods along",
                                  bind({ Prefs.musicBop }, actions.setMusicBop))
                        toggleRow("macwindow", "Above fullscreen apps", nil,
                                  bind({ Prefs.aboveFullscreen }, actions.setAboveFullscreen))
                        HStack(spacing: 6) {
                            Button("Edit rules") { actions.editRules() }.buttonStyle(ChipStyle(tint: UI.blush))
                            Button("Reload") { actions.reloadRules() }.buttonStyle(ChipStyle(tint: UI.blush))
                            Button("Reset") { actions.resetRules() }.buttonStyle(ChipStyle(tint: UI.blush))
                        }
                    }
                }
                brainCard
                card {
                    HStack(spacing: 10) {
                        iconBadge("mic.fill")
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Voice assistant").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(UI.ink)
                            Text(actions.cranberryRunning ? "Cranberry is listening" : "Talk to Cranberry hands-free")
                                .font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
                        }
                        Spacer()
                        Button(actions.cranberryRunning ? "Stop" : "Start") { actions.toggleCranberry() }
                            .buttonStyle(ChipStyle(tint: actions.cranberryRunning ? Fur.alertAccent : UI.lilac))
                    }
                }
            }
        }
    }

    func themeChip(_ t: AppTheme) -> some View {
        let selected = _refreshed(AppTheme.current) == t
        return Button { Prefs.theme = t; refresh += 1 } label: {
            VStack(spacing: 5) {
                Circle()
                    .fill(LinearGradient(colors: [t.hot.0, t.hot.1], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 30, height: 30)
                    .overlay(Text(t.emoji).font(.system(size: 14)))
                    .overlay(Circle().strokeBorder(UI.glass(0.9), lineWidth: 2))
                    .padding(3)
                    .overlay(Circle().strokeBorder(selected ? UI.ink.opacity(0.6) : .clear, lineWidth: 2))
                Text(t.title)
                    .font(.system(size: 10, weight: selected ? .heavy : .semibold, design: .rounded))
                    .foregroundStyle(UI.ink).lineLimit(1).minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(t.title) theme")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Reads a value while depending on `refresh`, so the view redraws when a preference changes.
    func _refreshed<T>(_ v: T) -> T { _ = refresh; return v }

    private var quietHourPickers: some View {
        HStack(spacing: 8) {
            Text("From").font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
            hourPicker(Binding(get: { Prefs.quietHoursStart }, set: { Prefs.quietHoursStart = $0; refresh += 1 }))
            Text("to").font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
            hourPicker(Binding(get: { Prefs.quietHoursEnd }, set: { Prefs.quietHoursEnd = $0; refresh += 1 }))
            Spacer()
        }
        .padding(.leading, 38)
    }

    func hourPicker(_ sel: Binding<Int>) -> some View {
        Picker("Hour", selection: sel) {
            ForEach(0..<24, id: \.self) { Text(PanelActions.clock($0)).tag($0) }
        }
        .labelsHidden()
        .frame(width: 78)
    }

    private func addBlock() {
        actions.block(blockDraft)
        blockDraft = ""
    }

    // MARK: Building blocks

    func bind(_ get: @escaping () -> Bool, _ set: @escaping (Bool) -> Void) -> Binding<Bool> {
        Binding(get: { _ = refresh; return get() }, set: { set($0); refresh += 1 })
    }

    func toggleRow(_ icon: String, _ title: String, _ subtitle: String?,
                           _ isOn: Binding<Bool>, enabled: Bool = true) -> some View {
        HStack(spacing: 10) {
            iconBadge(icon)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(UI.ink)
                if let subtitle {
                    Text(subtitle).font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(UI.inkSoft).lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small).tint(UI.lilac)
        }
        .opacity(enabled ? 1 : 0.45)
        .disabled(!enabled)
    }

    func iconBadge(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(UI.ink.opacity(0.75))
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(UI.lilac.opacity(0.22)))
    }

    func notice(_ text: String, _ action: String, _ run: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(text).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft).lineLimit(2)
            Spacer(minLength: 4)
            Button(action, action: run).buttonStyle(ChipStyle())
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(UI.butter.opacity(0.32)))
    }

    func pill(_ text: String, _ tint: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundStyle(UI.ink)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.5)))
    }

    func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(UI.inkSoft)
            .textCase(.uppercase)
            .kerning(0.5)
    }

    var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(UI.card)
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(UI.glass(0.9), lineWidth: 1.5))
            .shadow(color: UI.ink.opacity(0.07), radius: 12, y: 5)
    }

    func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(cardBackground)
    }

    func bar(_ value: Double, _ colors: [Color], height: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(UI.track)
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, geo.size.width * min(1, max(0, value))))
                    .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.8), value: value)
            }
        }
        .frame(height: height)
    }

    /// A circular progress ring with whatever you like in the middle.
    func ring<C: View>(_ progress: Double, size: CGFloat, line: CGFloat, colors: [Color]? = nil,
                               @ViewBuilder _ center: () -> C) -> some View {
        ZStack {
            Circle().stroke(UI.track, lineWidth: line)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(AngularGradient(colors: colors ?? UI.ringColors,
                                        center: .center),
                        style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.85), value: progress)
            center()
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Styles

/// A soft press: the whole tile dips under your finger.
struct PressStyle: ButtonStyle {
    var reduce: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduce ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(reduce ? nil : .spring(response: 0.22, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

/// A small pill button: timer lengths, Save, Stop.
struct ChipStyle: ButtonStyle {
    var tint: Color = UI.lilac
    /// A chosen option: filled in, with a ring.
    var on = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(UI.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(tint.opacity(configuration.isPressed ? 0.6 : (on ? 0.5 : 0.32))))
            .overlay(Capsule().strokeBorder(on ? UI.lilac : .clear, lineWidth: 2))
            .opacity(enabled ? 1 : 0.4)
    }
}

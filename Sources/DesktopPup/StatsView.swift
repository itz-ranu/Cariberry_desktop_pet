import AppKit
import SwiftUI

/// Her scrapbook. Pick any day (tap the calendar, or step with the arrows) to see how it
/// went: focus against your goal, time lost to distractions, sessions, finished to-dos, and
/// where the time went app by app. Below that: streak records, lifetime totals, badges, and
/// a card you can share.
struct StatsView: View {
    @ObservedObject var pet: Pet
    /// ImageRenderer can't capture a ScrollView's contents, so the render helper asks
    /// for the same layout laid out at full height instead.
    var scrolls: Bool = true

    static let width: CGFloat = 380

    @State private var selected = Calendar.current.startOfDay(for: Date())
    /// The day when the window last looked, so leaving it open past midnight rolls "Today" over.
    @State private var knownToday = Calendar.current.startOfDay(for: Date())
    /// The stats are plain (unpublished) values, so re-read them every few seconds.
    @State private var refresh = 0
    @State private var shareNote: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cal = Calendar.current
    private var today: Date { cal.startOfDay(for: Date()) }
    private var isToday: Bool { selected == today }

    // MARK: Data for the selected day

    private func focus(_ d: Date) -> Double { pet.dailyFocus[d] ?? 0 }                     // minutes
    private func distraction(_ d: Date) -> Double { (pet.dailyDistraction[d] ?? 0) / 60 }  // minutes
    private func previous(_ d: Date) -> Date { cal.date(byAdding: .day, value: -1, to: d) ?? d }
    private func next(_ d: Date) -> Date { cal.date(byAdding: .day, value: 1, to: d) ?? d }

    private var apps: [(String, Double)] {
        (pet.dailyAppTime[selected] ?? [:]).sorted { $0.value > $1.value }.prefix(7).map { ($0.key, $0.value) }
    }
    private var hasAnyData: Bool {
        focus(selected) > 0 || distraction(selected) > 0 || !(pet.dailyAppTime[selected] ?? [:]).isEmpty
            || (pet.dailySessions[selected] ?? 0) > 0
    }

    private var dayTitle: String {
        if isToday { return "Today" }
        if selected == previous(today) { return "Yesterday" }
        return selected.formatted(.dateTime.weekday(.wide))
    }
    private var dayDate: String { selected.formatted(.dateTime.day().month(.wide).year()) }

    // MARK: Body

    var body: some View {
        ZStack {
            background
            if scrolls {
                ScrollView(.vertical, showsIndicators: false) { stack }
            } else {
                stack
            }
        }
        .frame(width: Self.width, height: scrolls ? 820 : 3100)
        .environment(\.colorScheme, AppTheme.current.isDark ? .dark : .light)
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            refresh += 1
            let now = Calendar.current.startOfDay(for: Date())
            if now != knownToday {
                if selected == knownToday { selected = now }
                knownToday = now
            }
        }
    }

    private var background: some View {
        ZStack {
            UI.page
            Circle().fill(UI.blush.opacity(0.32)).frame(width: 280).blur(radius: 64).offset(x: 150, y: -260)
            Circle().fill(UI.lilac.opacity(0.28)).frame(width: 300).blur(radius: 70).offset(x: -160, y: 300)
        }
        .ignoresSafeArea()
    }

    private var stack: some View {
        VStack(spacing: 14) {
            header
            levelCard
            weekCard
            dayCard
            insightsCard
            recordsCard
            badgesCard
            allTimeRing
        }
        .padding(.top, 22)
        .padding(.horizontal, 16)
        .padding(.bottom, 26)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [UI.blush.opacity(0.7), UI.lilac.opacity(0.6)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Circle().strokeBorder(UI.glass(0.9), lineWidth: 3)
                CritterView(species: pet.species, coat: pet.coatIndex,
                            pose: Pose(emotion: .proud, phase: 0.42, outfit: pet.outfit), scale: 0.46)
                    .offset(x: -3, y: -8)
                    .frame(width: 84, height: 84)
                    .clipShape(Circle())
            }
            .frame(width: 84, height: 84)
            .shadow(color: UI.lilac.opacity(0.4), radius: 10, y: 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(pet.name)
                    .font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(UI.ink)
                Text("together \(pet.ageDays) day\(pet.ageDays == 1 ? "" : "s") · since \(pet.born.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
            }
            Spacer(minLength: 0)
        }
    }

    private var levelCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Level \(pet.level)")
                    .font(.system(size: 21, weight: .heavy, design: .rounded)).foregroundStyle(UI.ink)
                Text(pet.levelTitle)
                    .font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(UI.lilac)
                Spacer()
                if pet.collarTier > 0 {
                    HStack(spacing: 4) {
                        Circle().fill(Progression.collarColor(tier: pet.collarTier)).frame(width: 9, height: 9)
                        Text(Progression.collarName(tier: pet.collarTier))
                            .font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
                    }
                }
            }
            bar(pet.levelProgress, [UI.lilac, UI.blush], height: 10)
            HStack {
                Text("\(Int(pet.xpIntoLevel)) / \(Int(pet.xpForThisLevel)) XP")
                    .font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(UI.inkSoft)
                Spacer()
                if let next = Progression.nextUnlock(level: pet.level) {
                    Text("next: \(next)")
                        .font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
                }
            }
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [UI.blush.opacity(0.35), UI.lilac.opacity(0.30)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(UI.glass(0.8), lineWidth: 1.5))
        )
    }

    // MARK: The day browser

    private var dayCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                dayNavigator
                calendarGrid
                Divider().opacity(0.4)
                if hasAnyData { dayDetails } else { emptyDay }
                shareRow
            }
        }
    }

    private var dayNavigator: some View {
        HStack(spacing: 10) {
            stepButton("chevron.left") { selected = previous(selected) }
            VStack(alignment: .leading, spacing: 1) {
                Text(dayTitle)
                    .font(.system(size: 19, weight: .heavy, design: .rounded)).foregroundStyle(UI.ink)
                Text(dayDate)
                    .font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
            }
            stepButton("chevron.right") { if !isToday { selected = next(selected) } }
                .opacity(isToday ? 0.3 : 1)
                .disabled(isToday)
            Spacer()
            if !isToday {
                Button("Today") { withAnimation(reduceMotion ? nil : .spring(response: 0.3)) { selected = today } }
                    .buttonStyle(StatsChipStyle())
            }
        }
    }

    private func stepButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .heavy)).foregroundStyle(UI.ink)
                .frame(width: 30, height: 30)
                .background(Circle().fill(UI.lilac.opacity(0.25)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "chevron.left" ? "Previous day" : "Next day")
    }

    /// The last five weeks as a calendar: each day is shaded by how much you focused. Tap
    /// one to look at it.
    private var calendarGrid: some View {
        let weekdays = weekdayLetters
        let days = calendarDays
        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    Text(weekdays[i])
                        .font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(UI.inkSoft)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(days, id: \.self) { d in dayCell(d) }
            }
        }
    }

    private var weekdayLetters: [String] {
        let symbols = cal.veryShortWeekdaySymbols
        let first = cal.firstWeekday - 1
        return (0..<7).map { symbols[(first + $0) % 7] }
    }

    /// Five weeks ending with this one, starting on the first weekday.
    private var calendarDays: [Date] {
        let thisWeekStart = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let start = cal.date(byAdding: .weekOfYear, value: -4, to: thisWeekStart) ?? thisWeekStart
        return (0..<35).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private func dayCell(_ d: Date) -> some View {
        let future = d > today
        let m = focus(d)
        let goal = Double(max(1, pet.dailyGoal))
        let frac = min(1, m / goal)
        let hit = m >= goal
        let sel = d == selected
        return Button { withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8)) { selected = d } } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hit ? AnyShapeStyle(UI.hot)
                              : AnyShapeStyle(m > 0 ? UI.lilac.opacity(0.22 + 0.5 * frac) : UI.track))
                if sel {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(UI.ink, lineWidth: 2)
                }
                Text("\(cal.component(.day, from: d))")
                    .font(.system(size: 11, weight: d == today ? .heavy : .semibold, design: .rounded))
                    .foregroundStyle(hit ? Color.white : UI.ink.opacity(m > 0 ? 0.9 : 0.5))
            }
            .frame(height: 34)
            .overlay(alignment: .topTrailing) {
                if d == today { Circle().fill(UI.blush).frame(width: 7, height: 7).offset(x: 2, y: -2) }
            }
            .overlay(alignment: .bottomTrailing) {
                if let m = pet.moods[d].flatMap(Mood.init(rawValue:)) { Text(m.emoji).font(.system(size: 8)).offset(x: -2, y: -1) }
            }
        }
        .buttonStyle(.plain)
        .opacity(future ? 0 : 1)
        .disabled(future)
        .accessibilityLabel("\(d.formatted(.dateTime.weekday(.wide).day().month())): \(Focus.timeText(m)) focus")
    }

    private var dayDetails: some View {
        let f = focus(selected), dMin = distraction(selected)
        let goal = pet.dailyGoal
        let yesterday = focus(previous(selected))
        let delta = f - yesterday
        let ratio = (f + dMin) > 0 ? f / (f + dMin) : -1
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                ring(min(1, f / Double(max(1, goal))), size: 92, line: 11) {
                    VStack(spacing: 0) {
                        Text("\(Int(min(f / Double(max(1, goal)), 9.99) * 100))%")
                            .font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(UI.ink)
                        Text("of goal").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(UI.inkSoft)
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(Focus.timeText(f))
                        .font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(UI.ink)
                    Text("focused · goal \(Focus.timeText(Double(goal))) · vs day before")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
                    HStack(spacing: 6) {
                        if f >= Double(goal) { pill("🏆 goal hit", UI.butter) }
                        if abs(delta) >= 1 {
                            pill("\(delta > 0 ? "▲" : "▼") \(Focus.timeText(abs(delta)))", delta > 0 ? UI.sage : UI.peach)
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            if let m = pet.moods[selected].flatMap(Mood.init(rawValue:)) {
                HStack(spacing: 8) {
                    Text(m.emoji).font(.system(size: 20))
                    Text("You felt \(m.title.lowercased()) this day").font(.system(size: 12.5, weight: .semibold, design: .rounded)).foregroundStyle(UI.ink)
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(UI.lilac.opacity(0.18)))
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                tile("✅", "To-dos done", "\(pet.dailyTasks[selected] ?? 0)", UI.sage)
                tile("🍅", "Sessions", "\(pet.dailySessions[selected] ?? 0)", UI.peach)
                tile("📵", "Distracted", Focus.timeText(dMin), UI.blush)
                tile("🐾", "Told off", "\(pet.dailyBarks[selected] ?? 0)×", UI.butter)
            }

            composition(ratio: ratio)

            appsList
        }
    }

    private var appsList: some View {
        VStack(alignment: .leading, spacing: 9) {
            label("Where the day went")
            if apps.isEmpty {
                Text("No app time was tracked for this day.")
                    .font(.system(size: 11.5, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
            } else {
                let top = apps.first?.1 ?? 1
                let total = max(1, trackedSeconds(selected))
                ForEach(apps, id: \.0) { app in
                    let tint = kindTint(app.0)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Circle().fill(tint).frame(width: 8, height: 8)
                            Text(app.0).font(.system(size: 12.5, weight: .semibold, design: .rounded)).foregroundStyle(UI.ink).lineLimit(1)
                            Spacer()
                            Text("\(Int((app.1 / total * 100).rounded()))%")
                                .font(.system(size: 10.5, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft.opacity(0.8))
                            Text(formatDuration(app.1)).font(.system(size: 11.5, weight: .semibold, design: .rounded)).foregroundStyle(UI.inkSoft)
                                .frame(minWidth: 40, alignment: .trailing)
                        }
                        bar(app.1 / top, [tint.opacity(0.75), tint], height: 6)
                    }
                }
                HStack(spacing: 12) {
                    legendDot(UI.sage, "work"); legendDot(UI.blush, "distraction"); legendDot(UI.lilac, "everything else")
                }
                .padding(.top, 2)
            }
        }
    }

    private var emptyDay: some View {
        VStack(spacing: 8) {
            Text(isToday ? "🌱" : "🌙").font(.system(size: 34))
            Text(isToday ? "A fresh day. Nothing logged yet." : "Nothing was logged on this day.")
                .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(UI.ink)
            Text(isToday ? "Start a focus session and watch this fill up." : "She wasn't watching, or you had a day off. That's okay 💗")
                .font(.system(size: 11.5, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var shareRow: some View {
        HStack(spacing: 8) {
            Button { share(save: false) } label: { Label("Copy card", systemImage: "square.on.square") }
                .buttonStyle(StatsChipStyle())
            Button { share(save: true) } label: { Label("Save to Desktop", systemImage: "square.and.arrow.down") }
                .buttonStyle(StatsChipStyle(tint: UI.blush))
            if let note = shareNote {
                Text(note).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(UI.inkSoft)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: The day, as one stacked bar

    private func trackedSeconds(_ d: Date) -> Double { (pet.dailyAppTime[d] ?? [:]).values.reduce(0, +) }

    private func kindTint(_ app: String) -> Color {
        switch pet.siteKinds[app] {
        case "work": return UI.sage
        case "distraction": return UI.blush
        default: return UI.lilac
        }
    }

    private func legendDot(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(c).frame(width: 7, height: 7)
            Text(t).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
        }
    }

    /// Where the whole day went: focus, distraction, everything else, and time you were away from the
    /// keys. The four add up to the time she watched, so the bar never claims more than she saw.
    @ViewBuilder
    private func composition(ratio: Double) -> some View {
        let focusS = focus(selected) * 60
        let distS = min(distraction(selected) * 60, max(0, trackedSeconds(selected) - focusS))
        let away = pet.dailyAway[selected] ?? 0
        let other = max(0, trackedSeconds(selected) - focusS - distS)
        let total = focusS + distS + other + away
        if total > 0 {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    label("How the day split")
                    Spacer()
                    if ratio >= 0 {
                        Text("\(Int(ratio * 100))% focused · \(moodWord(ratio))")
                            .font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(UI.ink)
                    }
                }
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach([(focusS, UI.sage), (distS, UI.blush), (other, UI.lilac.opacity(0.55)), (away, UI.track)], id: \.0) { seg in
                            if seg.0 > 0 { Capsule().fill(seg.1).frame(width: max(5, (geo.size.width - 6) * seg.0 / total)) }
                        }
                    }
                }
                .frame(height: 12)
                HStack(spacing: 0) {
                    splitStat(UI.sage, "Focused", focusS)
                    splitStat(UI.blush, "Distracted", distS)
                    splitStat(UI.lilac.opacity(0.7), "Other", other)
                    if away > 60 { splitStat(UI.inkSoft.opacity(0.5), "Away", away) }
                }
            }
        }
    }

    private func splitStat(_ c: Color, _ t: String, _ seconds: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Circle().fill(c).frame(width: 7, height: 7)
                Text(t).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
            }
            Text(formatDuration(seconds)).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(UI.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: This week

    private var weekDays: [Date] { (0..<7).map { cal.date(byAdding: .day, value: -(6 - $0), to: today) ?? today } }

    private var weekCard: some View {
        let days = weekDays
        let vals = days.map { focus($0) }
        let goal = Double(max(1, pet.dailyGoal))
        let top = max(goal, vals.max() ?? 0) * 1.12
        let total = vals.reduce(0, +)
        let lastWeek = (7..<14).map { focus(cal.date(byAdding: .day, value: -$0, to: today) ?? today) }.reduce(0, +)
        let delta = total - lastWeek
        let active = vals.filter { $0 > 0 }.count
        let chartH: CGFloat = 96
        return card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    label("📈 This week")
                    Spacer()
                    if abs(delta) >= 1 && (total > 0 || lastWeek > 0) {
                        Text("\(delta > 0 ? "▲" : "▼") \(Focus.timeText(abs(delta))) vs last week")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded)).foregroundStyle(UI.ink)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill((delta > 0 ? UI.sage : UI.peach).opacity(0.55)))
                    }
                }
                ZStack(alignment: .bottom) {
                    // the goal line
                    GeometryReader { geo in
                        let y = chartH - chartH * CGFloat(goal / top)
                        Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y)) }
                            .stroke(UI.inkSoft.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        Text("goal").font(.system(size: 8.5, weight: .bold, design: .rounded)).foregroundStyle(UI.inkSoft.opacity(0.7))
                            .position(x: 12, y: max(6, y - 7))
                    }
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(0..<7, id: \.self) { i in
                            let d = days[i], v = vals[i]
                            let hit = v >= goal
                            let sel = d == selected
                            Button { withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8)) { selected = d } } label: {
                                VStack(spacing: 3) {
                                    Spacer(minLength: 0)
                                    if v > 0 {
                                        Text(Focus.timeText(v)).font(.system(size: 8.5, weight: .bold, design: .rounded))
                                            .foregroundStyle(UI.ink.opacity(sel ? 1 : 0.65)).lineLimit(1).minimumScaleFactor(0.7)
                                    }
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(v > 0 ? AnyShapeStyle(hit ? UI.hot : LinearGradient(colors: [UI.lilac.opacity(0.55), UI.lilac], startPoint: .top, endPoint: .bottom))
                                                    : AnyShapeStyle(UI.track))
                                        .frame(height: max(5, (chartH - 14) * CGFloat(v / top)))
                                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(UI.ink, lineWidth: sel ? 2 : 0))
                                }
                                .frame(maxWidth: .infinity, minHeight: chartH, maxHeight: chartH)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(d.formatted(.dateTime.weekday(.wide))): \(Focus.timeText(v)) focus")
                        }
                    }
                }
                .frame(height: chartH)
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(0..<7, id: \.self) { i in
                            Text(days[i].formatted(.dateTime.weekday(.abbreviated)))
                                .font(.system(size: 9.5, weight: days[i] == today ? .heavy : .semibold, design: .rounded))
                                .foregroundStyle(days[i] == today ? UI.ink : UI.inkSoft)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                HStack(spacing: 8) {
                    miniStat("Total", Focus.timeText(total))
                    miniStat("Daily avg", Focus.timeText(active > 0 ? total / Double(active) : 0))
                    miniStat("Days at goal", "\(vals.filter { $0 >= goal }.count) / 7")
                }
            }
        }
    }

    private func miniStat(_ t: String, _ v: String) -> some View {
        VStack(spacing: 1) {
            Text(v).font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(UI.ink).lineLimit(1).minimumScaleFactor(0.8)
            Text(t).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(UI.glass(0.7)))
    }

    // MARK: Little discoveries

    private func hourLabel(_ h: Int) -> String { "\(h % 12 == 0 ? 12 : h % 12) \(h < 12 ? "AM" : "PM")" }

    /// The hour of the day with the most focus, once there is enough to mean something.
    private var peakHour: Int? {
        let total = pet.focusByHour.values.reduce(0, +)
        guard total >= 20, let best = pet.focusByHour.max(by: { $0.value < $1.value }) else { return nil }
        return best.key
    }

    private var bestWeekday: (name: String, avg: Double)? {
        var sums: [Int: (Double, Int)] = [:]
        for (d, m) in pet.dailyFocus where m >= 5 {
            let wd = cal.component(.weekday, from: d)
            sums[wd] = ((sums[wd]?.0 ?? 0) + m, (sums[wd]?.1 ?? 0) + 1)
        }
        guard sums.values.map(\.1).reduce(0, +) >= 5,
              let best = sums.filter({ $0.value.1 >= 2 }).max(by: { $0.value.0 / Double($0.value.1) < $1.value.0 / Double($1.value.1) })
        else { return nil }
        return (cal.weekdaySymbols[best.key - 1], best.value.0 / Double(best.value.1))
    }

    /// The app or site that cost the most time this week, if anything she barked about did.
    private var weekSink: (String, Double)? {
        var by: [String: Double] = [:]
        for d in weekDays { for (app, s) in pet.dailyAppTime[d] ?? [:] where pet.siteKinds[app] == "distraction" { by[app, default: 0] += s } }
        guard let top = by.max(by: { $0.value < $1.value }), top.value >= 300 else { return nil }
        return (top.key, top.value)
    }

    private var insightsCard: some View {
        var rows: [(String, String, String)] = []
        if let h = peakHour { rows.append(("⏰", "Your focus hour", "You focus best around \(hourLabel(h))")) }
        if let w = bestWeekday { rows.append(("📅", "Strongest day", "\(w.name)s: about \(Focus.timeText(w.avg)) on average")) }
        if let s = weekSink { rows.append(("📵", "Biggest time sink this week", "\(displayName(s.0)), \(formatDuration(s.1))")) }
        if pet.streakDays >= 2 { rows.append(("🔥", "On a roll", "\(pet.streakDays) days in a row. Don't break it!")) }
        return card {
            VStack(alignment: .leading, spacing: 12) {
                label("✨ Little discoveries")
                if rows.isEmpty {
                    Text("Focus for a few days and she'll start spotting your patterns: your best hour, your strongest day, what keeps pulling you away. 🌱")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
                } else {
                    ForEach(0..<rows.count, id: \.self) { i in
                        HStack(spacing: 10) {
                            Text(rows[i].0).font(.system(size: 18))
                                .frame(width: 34, height: 34)
                                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(UI.lilac.opacity(0.25)))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(rows[i].1).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(UI.inkSoft).textCase(.uppercase).kerning(0.4)
                                Text(rows[i].2).font(.system(size: 12.5, weight: .semibold, design: .rounded)).foregroundStyle(UI.ink)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                if peakHour != nil { hourChart }
            }
        }
    }

    /// Twenty-four little bars: how much you've focused in each hour of the day, ever.
    private var hourChart: some View {
        let vals = (0..<24).map { pet.focusByHour[$0] ?? 0 }
        let top = max(1, vals.max() ?? 1)
        let peak = vals.firstIndex(of: top) ?? 0
        return VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 2.5) {
                ForEach(0..<24, id: \.self) { h in
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(h == peak ? AnyShapeStyle(UI.hot) : AnyShapeStyle(UI.lilac.opacity(vals[h] > 0 ? 0.55 : 0.18)))
                        .frame(height: max(3, 38 * CGFloat(vals[h] / top)))
                }
            }
            .frame(height: 40, alignment: .bottom)
            HStack {
                ForEach(["12a", "6a", "12p", "6p", "11p"], id: \.self) { t in
                    Text(t).font(.system(size: 8.5, weight: .semibold, design: .rounded)).foregroundStyle(UI.inkSoft)
                    if t != "11p" { Spacer() }
                }
            }
        }
    }

    // MARK: Records

    private var recordsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                label("🏅 Records")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    tile("🔥", "Current streak", "\(pet.streakDays) day\(pet.streakDays == 1 ? "" : "s")", UI.peach)
                    tile("👑", "Best streak", "\(pet.bestStreakDays) day\(pet.bestStreakDays == 1 ? "" : "s")", UI.butter)
                    tile("⏱", "Lifetime focus", formatDuration(pet.totalFocusMinutes * 60), UI.lilac)
                    tile("🌟", "Best day", Focus.timeText(pet.mostFocusInADay), UI.sage)
                    tile("🍅", "Sessions", "\(pet.totalSessions)", UI.peach)
                    tile("✅", "To-dos done", "\(pet.totalTasksDone)", UI.sage)
                    tile("🍖", "Treats eaten", "\(pet.treatsEaten)", UI.butter)
                    tile("🐾", "Times told off", "\(pet.barksGiven)", UI.blush)
                }
            }
        }
    }

    // MARK: Badges

    private var badgesCard: some View {
        let earned = Prefs.badges
        let count = Badges.all.filter { earned.contains($0.id) }.count
        return card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    label("🎖 Badges")
                    Spacer()
                    Text("\(count) of \(Badges.all.count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(UI.inkSoft)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(Badges.all) { b in
                        let got = earned.contains(b.id)
                        VStack(spacing: 3) {
                            Text(got ? b.emoji : "🔒").font(.system(size: 24)).opacity(got ? 1 : 0.5)
                            Text(b.title)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(UI.ink).lineLimit(2).multilineTextAlignment(.center)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 66)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(got ? AnyShapeStyle(UI.lilac.opacity(0.22)) : AnyShapeStyle(UI.track)))
                        .help(got ? b.detail : "Locked: \(b.detail)")
                        .accessibilityLabel(got ? "\(b.title), earned" : "\(b.title), locked. \(b.detail)")
                    }
                }
            }
        }
    }

    // MARK: All-time work vs distraction

    private var categoryBreakdown: [(name: String, seconds: Double, kind: ActivityKind)] {
        let kinds = Dictionary(uniqueKeysWithValues: RuleStore.shared.book.rules.map { ($0.name, $0.kind) })
        var totals: [String: Double] = [:]
        for (name, seconds) in pet.categoryTime {
            totals[kinds[name] != nil ? name : "Other", default: 0] += seconds
        }
        return totals.map { (name: $0.key, seconds: $0.value, kind: kinds[$0.key] ?? .neutral) }
    }

    private func displayName(_ raw: String) -> String {
        raw == "YouTube (might be learning, might not)" ? "YouTube" : raw
    }

    /// -1 means not enough signal yet to say anything meaningful.
    private var focusRatio: Double {
        let work = categoryBreakdown.filter { $0.kind == .work }.reduce(0) { $0 + $1.seconds }
        let distraction = categoryBreakdown.filter { $0.kind == .distraction }.reduce(0) { $0 + $1.seconds }
        return (work + distraction) > 0 ? work / (work + distraction) : -1
    }

    /// Deliberately not called "focus quality": it only counts time a rule actually classified
    /// as work or distraction, so it can't claim to measure your whole day.
    private var allTimeRing: some View {
        card {
            VStack(spacing: 12) {
                HStack {
                    label("Work vs distraction")
                    Spacer()
                    Text("all time").font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
                }
                let ratio = focusRatio
                ring(ratio >= 0 ? max(0.03, ratio) : 0, size: 100, line: 12) {
                    if ratio >= 0 {
                        VStack(spacing: 0) {
                            Text("\(Int(ratio * 100))%")
                                .font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(UI.ink)
                            Text(moodWord(ratio)).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
                        }
                    } else {
                        Text("🐾").font(.system(size: 26))
                    }
                }
                if ratio >= 0 {
                    HStack(spacing: 8) {
                        if let w = categoryBreakdown.filter({ $0.kind == .work }).max(by: { $0.seconds < $1.seconds }) {
                            categoryPill(displayName(w.name), w.seconds, UI.sage)
                        }
                        if let d = categoryBreakdown.filter({ $0.kind == .distraction }).max(by: { $0.seconds < $1.seconds }) {
                            categoryPill(displayName(d.name), d.seconds, UI.blush)
                        }
                    }
                } else {
                    Text("not enough data yet, get to work 💪")
                        .font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func categoryPill(_ name: String, _ seconds: Double, _ dot: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(dot).frame(width: 6, height: 6)
            Text(name).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(UI.ink).lineLimit(1)
            Text(formatDuration(seconds)).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(UI.glass(0.7)))
    }

    private func moodWord(_ ratio: Double) -> String {
        switch ratio {
        case 0.8...: return "excellent"
        case 0.6..<0.8: return "good"
        case 0.4..<0.6: return "mixed"
        default: return "rough day"
        }
    }

    // MARK: Sharing

    /// Draws a pretty card for the selected day and either copies it or saves it. It's an
    /// image of numbers you chose to share: nothing leaves the machine unless you paste it.
    private func share(save: Bool) {
        let card = ShareCard(name: pet.name, species: pet.species, coat: pet.coatIndex, outfit: pet.outfit,
                             dayTitle: dayTitle, date: dayDate,
                             focusMinutes: focus(selected), goalMinutes: pet.dailyGoal,
                             streak: pet.streakDays, sessions: pet.dailySessions[selected] ?? 0,
                             tasks: pet.dailyTasks[selected] ?? 0, level: pet.level, title: pet.levelTitle)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let image = renderer.nsImage else { flash("couldn't make the card 😟"); return }
        if save {
            guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { flash("couldn't save 😟"); return }
            let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            let stamp = selected.formatted(.iso8601.year().month().day())
            if let url = desktop?.appendingPathComponent("\(pet.name) \(stamp).png"), (try? png.write(to: url)) != nil {
                flash("saved to your Desktop 💌")
            } else {
                flash("couldn't save 😟")
            }
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            flash("copied! paste it anywhere 💌")
        }
    }

    private func flash(_ text: String) {
        withAnimation { shareNote = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { withAnimation { shareNote = nil } }
    }

    // MARK: Building blocks

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return total > 0 ? "<1m" : "0m"
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(UI.inkSoft)
            .textCase(.uppercase).kerning(0.5)
    }

    private func pill(_ text: String, _ tint: Color) -> some View {
        Text(text).font(.system(size: 10.5, weight: .heavy, design: .rounded)).foregroundStyle(UI.ink)
            .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(tint.opacity(0.55)))
    }

    private func tile(_ emoji: String, _ label: String, _ value: String, _ accent: Color) -> some View {
        HStack(spacing: 10) {
            Text(emoji).font(.system(size: 20))
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(accent.opacity(0.4)))
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(UI.ink).lineLimit(1)
                Text(label).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9).padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(UI.glass(0.7)))
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(UI.card)
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(UI.glass(0.9), lineWidth: 1.5))
                    .shadow(color: UI.ink.opacity(0.07), radius: 12, y: 5)
            )
    }

    private func bar(_ value: Double, _ colors: [Color], height: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(UI.track)
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, geo.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: height)
    }

    private func ring<C: View>(_ progress: Double, size: CGFloat, line: CGFloat, @ViewBuilder _ center: () -> C) -> some View {
        ZStack {
            Circle().stroke(UI.track, lineWidth: line)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(AngularGradient(colors: UI.ringColors,
                                        center: .center),
                        style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center()
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Small pill button

private struct StatsChipStyle: ButtonStyle {
    var tint: Color = UI.lilac
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(UI.ink)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(tint.opacity(configuration.isPressed ? 0.6 : 0.32)))
    }
}

// MARK: - The shareable card

/// A portrait card meant for a story or a group chat: her, the day's focus, and a few numbers.
struct ShareCard: View {
    var name: String
    var species: Species
    var coat: Int
    var outfit: Outfit
    var dayTitle: String
    var date: String
    var focusMinutes: Double
    var goalMinutes: Int
    var streak: Int
    var sessions: Int
    var tasks: Int
    var level: Int
    var title: String

    private var progress: Double { min(1, focusMinutes / Double(max(1, goalMinutes))) }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 1.0, green: 0.86, blue: 0.92), Color(red: 0.86, green: 0.80, blue: 1.0)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(UI.glass(0.35)).frame(width: 260).offset(x: 130, y: -190)
            Circle().fill(Color(red: 1.0, green: 0.72, blue: 0.82).opacity(0.5)).frame(width: 220).offset(x: -140, y: 200)

            VStack(spacing: 10) {
                Text("\(dayTitle.lowercased()) ✨")
                    .font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(UI.ink.opacity(0.7))
                    .padding(.top, 22)

                CritterView(species: species, coat: coat,
                            pose: Pose(emotion: progress >= 1 ? .proud : .happy, phase: 0.42, outfit: outfit), scale: 0.82)
                    .stickerOutline(2.0)

                VStack(spacing: 2) {
                    Text(Focus.timeText(focusMinutes))
                        .font(.system(size: 46, weight: .heavy, design: .rounded)).foregroundStyle(UI.ink)
                    Text("of focus\(progress >= 1 ? " · goal reached 🏆" : "")")
                        .font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(UI.ink.opacity(0.65))
                }

                HStack(spacing: 8) {
                    stat("🔥", "\(streak)", "day streak")
                    stat("🍅", "\(sessions)", "sessions")
                    stat("✅", "\(tasks)", "to-dos")
                }
                .padding(.horizontal, 22)

                Spacer(minLength: 0)
                VStack(spacing: 1) {
                    Text("\(name) · Lv \(level) \(title)")
                        .font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(UI.ink.opacity(0.75))
                    Text("\(date) · made with Cariberry 💗")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded)).foregroundStyle(UI.ink.opacity(0.5))
                }
                .padding(.bottom, 18)
            }
        }
        .frame(width: 360, height: 450)
    }

    private func stat(_ emoji: String, _ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(emoji).font(.system(size: 18))
            Text(value).font(.system(size: 19, weight: .heavy, design: .rounded)).foregroundStyle(UI.ink)
            Text(label).font(.system(size: 9.5, weight: .semibold, design: .rounded)).foregroundStyle(UI.ink.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(UI.glass(0.65)))
    }
}

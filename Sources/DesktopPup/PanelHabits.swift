import SwiftUI

// Tiny daily habits and the achievements card. Both are there from the very first minute, so
// there's always something small to tick off and something to look forward to.
extension PanelView {

    // MARK: Habits

    var habitsCard: some View {
        let done = _refreshed(pet.habitsDone)
        return card {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    label("🌷 Tiny habits")
                    Spacer()
                    pill("\(done.count)/\(Habits.all.count)", done.count == Habits.all.count ? UI.sage : UI.blush)
                }
                ForEach(Habits.all) { h in
                    let on = done.contains(h.id)
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6)) { pet.toggleHabit(h.id) }
                        refresh += 1
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(on ? AnyShapeStyle(UI.hot) : AnyShapeStyle(UI.inkSoft))
                            Text("\(h.emoji) \(h.title)")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(on ? UI.inkSoft : UI.ink)
                                .strikethrough(on, color: UI.inkSoft)
                            Spacer(minLength: 0)
                            if h.auto != nil && !on {
                                Text("auto").font(.system(size: 9.5, weight: .bold, design: .rounded)).foregroundStyle(UI.inkSoft)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(on ? "\(h.title), done" : "\(h.title), not done")
                }
                Text(done.count == Habits.all.count ? "all done! she's so proud 🥹" : "each one is +\(Int(Habits.xp)) xp and \(Habits.berries) 🍓, and finishing them all is +\(Habits.bonusBerries) 🍓")
                    .font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
            }
        }
    }

    // MARK: Achievements

    var trophyCard: some View {
        let earned = _refreshed(Prefs.badges)
        let mine = Badges.all.filter { earned.contains($0.id) }
        let next = Badges.nextUp(for: pet)
        return card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    label("🏆 Achievements")
                    Spacer()
                    pill("\(mine.count)/\(Badges.all.count)", UI.butter)
                }
                if mine.isEmpty {
                    Text("Focus for a few minutes and you'll earn your first one 🌱")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(mine.reversed()) { b in
                                Text(b.emoji).font(.system(size: 22))
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(UI.lilac.opacity(0.22)))
                                    .help("\(b.title): \(b.detail)")
                            }
                        }
                    }
                }
                if let n = next {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("next up: \(n.emoji) \(n.title)")
                                .font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(UI.ink)
                            Spacer()
                            Text(n.progressText(pet))
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded)).foregroundStyle(UI.inkSoft)
                        }
                        bar(n.progress(pet), [UI.butter, UI.peach], height: 8)
                        Text(n.detail).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
                    }
                }
                HStack(spacing: 6) {
                    Button("Share my day 📸") { actions.showStory() }.buttonStyle(ChipStyle(tint: UI.blush))
                    Button("All badges") { actions.showStats() }.buttonStyle(ChipStyle())
                }
            }
        }
    }
}

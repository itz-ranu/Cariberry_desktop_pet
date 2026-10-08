import SwiftUI

// The lo-fi radio: one big play button, four stations and a volume. Lives on Home (so it's
// one tap from anywhere) and on the Focus tab.
extension PanelView {

    func musicCard(compact: Bool) -> some View {
        let playing = _refreshed(pet.ambiencePlaying)
        let station = pet.ambience == .off ? Ambience.lofi : pet.ambience
        return card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button { pet.toggleAmbienceNow(); refresh += 1 } label: {
                        Image(systemName: playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundStyle(.white)
                            .offset(x: playing ? 0 : 1.5)
                            .frame(width: 54, height: 54)
                            .background(Circle().fill(UI.hot).shadow(color: UI.lilac.opacity(0.6), radius: 8, y: 4))
                    }
                    .buttonStyle(PressStyle(reduce: reduceMotion))
                    .help(playing ? "Pause the music" : "Play \(station.title)")
                    .accessibilityLabel(playing ? "Pause music" : "Play music")

                    VStack(alignment: .leading, spacing: 2) {
                        label(playing ? "Now playing" : "Lo-fi radio")
                        Text("\(station.emoji) \(station.title)")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(UI.ink).lineLimit(1)
                        Text(playing ? "she's bopping along 🎶" : station.mood)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(UI.inkSoft).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    EqualizerBars(playing: playing, tint: UI.lilac, reduceMotion: reduceMotion)
                        .frame(width: 34, height: 30)
                }

                HStack(spacing: 6) {
                    ForEach(Ambience.stations, id: \.self) { a in stationChip(a, selected: station == a, playing: playing) }
                }

                if !compact {
                    HStack(spacing: 6) {
                        Text("or just").font(.system(size: 10.5, weight: .semibold, design: .rounded)).foregroundStyle(UI.inkSoft)
                        ForEach(Ambience.nature, id: \.self) { a in
                            Button { pet.chooseAmbience(a); refresh += 1 } label: {
                                Text("\(a.emoji) \(a.short)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(UI.ink)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Capsule().fill(pet.ambience == a ? UI.lilac.opacity(0.35) : UI.track))
                            }
                            .buttonStyle(PressStyle(reduce: reduceMotion))
                            .accessibilityAddTraits(pet.ambience == a ? .isSelected : [])
                        }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.fill").font(.system(size: 10)).foregroundStyle(UI.inkSoft)
                        Slider(value: Binding(get: { Prefs.ambienceVolume },
                                              set: { Prefs.ambienceVolume = $0; pet.refreshAmbience(); refresh += 1 }), in: 0.05...1)
                            .tint(UI.lilac)
                        Image(systemName: "speaker.wave.3.fill").font(.system(size: 10)).foregroundStyle(UI.inkSoft)
                    }
                    Text("Starts by itself with a focus timer. The speaker up top mutes everything.")
                        .font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
                }
            }
        }
    }

    private func stationChip(_ a: Ambience, selected: Bool, playing: Bool) -> some View {
        Button { pet.chooseAmbience(a); refresh += 1 } label: {
            VStack(spacing: 2) {
                Text(a.emoji).font(.system(size: 17))
                Text(a.short)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(UI.ink)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? UI.lilac.opacity(0.35) : UI.track))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected && playing ? UI.lilac : .clear, lineWidth: 2))
        }
        .buttonStyle(PressStyle(reduce: reduceMotion))
        .help(a.mood)
        .accessibilityLabel(a.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Four little bars that bounce while music plays and lie flat when it doesn't.
struct EqualizerBars: View {
    var playing: Bool
    var tint: Color
    var reduceMotion: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.14)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<4, id: \.self) { i in
                    let wave = 0.5 + 0.5 * sin(t * (4.2 + Double(i) * 1.3) + Double(i) * 1.9)
                    let h: CGFloat = playing ? (reduceMotion ? 0.6 : 0.25 + 0.75 * wave) : 0.12
                    Capsule().fill(tint.opacity(playing ? 0.9 : 0.35))
                        .frame(width: 5, height: max(4, 30 * h))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.14), value: h)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }
}

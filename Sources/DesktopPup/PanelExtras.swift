import SwiftUI

// App Guard, the mood card, and the extra settings cards (coaching vibe, chat brain,
// music, daily check-in). Kept apart from PanelView so that file stays readable.
extension PanelView {

    // MARK: Home: mood

    /// The daily check-in, always one tap away on Home (it pops up by itself once a day too).
    var moodCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                if let m = pet.currentMood {
                    HStack(spacing: 10) {
                        Text(m.emoji).font(.system(size: 28))
                        VStack(alignment: .leading, spacing: 1) {
                            label("Today's mood")
                            Text(m.title).font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(UI.ink)
                        }
                        Spacer()
                        Button("Today's note 💌") { actions.showNote() }.buttonStyle(ChipStyle())
                    }
                    HStack(spacing: 6) {
                        ForEach(Mood.allCases, id: \.self) { o in moodButton(o, selected: o == m) }
                    }
                } else {
                    label("How are we feeling today, bestie?")
                    HStack(spacing: 6) {
                        ForEach(Mood.allCases, id: \.self) { o in moodButton(o, selected: false) }
                    }
                }
            }
        }
    }

    func moodButton(_ m: Mood, selected: Bool) -> some View {
        Button { pet.setMood(m); pet.touch(); refresh += 1 } label: {
            VStack(spacing: 2) {
                Text(m.emoji).font(.system(size: 19))
                Text(m.title).font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(UI.ink)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? UI.lilac.opacity(0.3) : UI.track))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? UI.lilac : .clear, lineWidth: 2))
        }
        .buttonStyle(PressStyle(reduce: reduceMotion))
        .accessibilityLabel(m.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: App Guard

    var appGuard: some View {
        VStack(spacing: 12) {
            if !(Prefs.browserAwareness && !actions.monitor.automationDenied) { permissionCard }
            card {
                VStack(alignment: .leading, spacing: 11) {
                    HStack {
                        label("🛡 Guard these")
                        Spacer()
                        Text("\(GuardPreset.all.filter { RuleStore.shared.isGuarded($0) }.count) on")
                            .font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(UI.inkSoft)
                    }
                    Text("Switch on anything that eats your focus. She'll nudge you the moment she sees it.")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(GuardPreset.all) { preset in guardTile(preset) }
                    }
                }
            }
            card {
                VStack(alignment: .leading, spacing: 10) {
                    label("➕ Add your own")
                    HStack {
                        TextField("a site or app, e.g. etsy.com", text: $blockDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(UI.track))
                            .onSubmit(addGuardTerm)
                        Button("Guard it", action: addGuardTerm)
                            .buttonStyle(ChipStyle())
                            .disabled(blockDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    let custom = RuleStore.shared.customBlocks
                    if !custom.isEmpty {
                        ForEach(custom, id: \.self) { term in
                            HStack {
                                Text("🚫 \(term)").font(.system(size: 12.5, weight: .semibold, design: .rounded)).foregroundStyle(UI.ink)
                                Spacer()
                                Button { RuleStore.shared.removeBlock(term); refresh += 1 } label: {
                                    Image(systemName: "xmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(UI.inkSoft).frame(width: 22, height: 22)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Stop guarding \(term)")
                            }
                        }
                    }
                    HStack(spacing: 6) {
                        Button("Edit rules file") { actions.editRules() }.buttonStyle(ChipStyle(tint: UI.blush))
                        Button("Reload") { actions.reloadRules(); refresh += 1 }.buttonStyle(ChipStyle(tint: UI.blush))
                    }
                }
            }
        }
    }

    func addGuardTerm() {
        actions.block(blockDraft)
        blockDraft = ""
        refresh += 1
    }

    func guardTile(_ preset: GuardPreset) -> some View {
        let on = { _ = refresh; return RuleStore.shared.isGuarded(preset) }()
        return HStack(spacing: 8) {
            Text(preset.emoji).font(.system(size: 20))
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(on ? UI.lilac.opacity(0.4) : UI.track))
            Text(preset.name).font(.system(size: 11.5, weight: .bold, design: .rounded)).foregroundStyle(UI.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
            Spacer(minLength: 2)
            Toggle("", isOn: Binding(get: { on }, set: { v in
                RuleStore.shared.setGuard(preset, on: v)
                pet.say(v ? "\(preset.name) is on my watch list 👀" : "okay, \(preset.name) is free to roam 🕊️", v ? .alert : .neutral, 2.6)
                refresh += 1
            }))
            .labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(UI.lilac)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(UI.glass(0.55)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Guard \(preset.name)")
    }

    /// A plain-English checklist for the one permission she needs to see which site you're on.
    var permissionCard: some View {
        let aware = { _ = refresh; return Prefs.browserAwareness }()
        let denied = actions.monitor.automationDenied
        let allowed = aware && !denied
        return card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    label("🔐 Seeing your sites")
                    Spacer()
                    pill(allowed ? "✅ working" : (denied ? "⚠️ blocked" : "⏸ off"), allowed ? UI.sage : (denied ? UI.peach : UI.butter))
                }
                Text("To tell Instagram Reels from your homework, she reads the title of your browser tab. That's all she reads, and it stays on your Mac.")
                    .font(.system(size: 11.5, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 7) {
                    step(1, "Turn on browser awareness", done: aware)
                    step(2, "Tap Allow when macOS asks to let Cariberry control your browser", done: allowed)
                    step(3, "That's it: she can see tab titles", done: allowed)
                }
                HStack(spacing: 6) {
                    if !aware { Button("Turn on") { actions.setBrowserAwareness(true); refresh += 1 }.buttonStyle(ChipStyle()) }
                    if denied || aware {
                        Button("Open macOS Automation settings") { actions.openAutomationSettings() }.buttonStyle(ChipStyle(tint: UI.blush))
                    }
                }
                Text("Apps outside the browser (the Roblox or Netflix app, say) are recognised by name, no permission needed.")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
            }
        }
    }

    func step(_ n: Int, _ text: String, done: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(n).circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(done ? AnyShapeStyle(UI.hot) : AnyShapeStyle(UI.inkSoft))
            Text(text).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(UI.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Settings extras

    /// How she coaches you, with a taste of how each one sounds.
    var vibeCard: some View {
        let current = { _ = refresh; return Prefs.vibe }()
        return card {
            VStack(alignment: .leading, spacing: 10) {
                label("🎭 Coaching vibe")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    ForEach(Vibe.allCases, id: \.self) { v in
                        Button { Prefs.vibe = v; pet.say("\(v.emoji) \(v.title) it is", .happy, 2.4); refresh += 1 } label: {
                            HStack(spacing: 5) {
                                Text(v.emoji)
                                Text(v.title).font(.system(size: 11.5, weight: .bold, design: .rounded)).foregroundStyle(UI.ink).lineLimit(1).minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(current == v ? UI.lilac.opacity(0.32) : UI.track))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(current == v ? UI.lilac : .clear, lineWidth: 2))
                        }
                        .buttonStyle(PressStyle(reduce: reduceMotion))
                        .accessibilityAddTraits(current == v ? .isSelected : [])
                    }
                }
                Text(current.blurb).font(.system(size: 11.5, weight: .semibold, design: .rounded)).foregroundStyle(UI.ink)
                Text(current.example).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Text("On a day you say you're stressed or tired she goes gentle, whatever you pick.")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
            }
        }
    }

    /// Which brain answers in chat, and the key for it (kept in the Keychain).
    var brainCard: some View {
        let provider = { _ = refresh; return ChatProvider(rawValue: Prefs.chatProvider) ?? .local }()
        return card {
            VStack(alignment: .leading, spacing: 10) {
                label("💬 Chat brain")
                Picker("Provider", selection: Binding(get: { provider }, set: { Prefs.chatProvider = $0.rawValue; actions.sendChatConfig(); refresh += 1 })) {
                    ForEach(ChatProvider.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                if provider != .local {
                    TextField("Model (default \(provider.defaultModel))", text: Binding(get: { Prefs.chatModel }, set: { Prefs.chatModel = $0 }))
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(UI.track))
                        .onSubmit { actions.sendChatConfig() }
                }
                if provider.needsKey {
                    HStack {
                        SecureField("Paste your \(provider.title) API key", text: $keyDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(UI.track))
                            .onSubmit { saveKey(provider) }
                        Button("Save") { saveKey(provider) }.buttonStyle(ChipStyle()).disabled(keyDraft.isEmpty)
                    }
                    if Keychain.get(provider.keyAccount) != nil {
                        Text("✅ a key is saved in your Keychain").font(.system(size: 10.5, weight: .semibold, design: .rounded)).foregroundStyle(UI.inkSoft)
                    }
                }
                Text(provider.privacy).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(UI.ink)
                Text("Chat needs the Cranberry brain running (Start in the chat window). Without it she still answers in her own voice.")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
            }
        }
    }

    func saveKey(_ provider: ChatProvider) {
        Keychain.set(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines), for: provider.keyAccount)
        keyDraft = ""
        actions.sendChatConfig()
        refresh += 1
    }
}

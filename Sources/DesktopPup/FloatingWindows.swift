import AppKit
import SwiftUI

// MARK: - A small floating window

/// A borderless, rounded, always-on-top card that floats near her: the mood check-in, the
/// sticky note and the chat drawer. It doesn't steal focus from what you're working in,
/// except the chat, which has to be able to take typing.
final class FloatingCard: NSPanel {
    var takesKeyboard = false
    override var canBecomeKey: Bool { takesKeyboard }
    override var canBecomeMain: Bool { false }

    init(size: CGSize, takesKeyboard: Bool = false) {
        self.takesKeyboard = takesKeyboard
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: takesKeyboard ? [.borderless] : [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
}

/// Opens, places and closes those cards.
@MainActor
final class FloatingWindows {
    private let pet: Pet
    let chat: ChatState
    private var moodCard: FloatingCard?
    private var noteCard: FloatingCard?
    private var chatCard: FloatingCard?
    private var storyCard: FloatingCard?
    private var toastCard: FloatingCard?
    /// Starts the Python brain: set by the app so the chat drawer can offer to.
    var startBrain: (() -> Void)?

    init(pet: Pet, chat: ChatState) {
        self.pet = pet
        self.chat = chat
    }

    private var visible: NSRect { pet.screen.visibleFrame }

    private func show(_ card: FloatingCard, _ view: some View, origin: CGPoint) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: card.frame.size)
        card.contentView = host
        card.setFrameOrigin(origin)
        card.alphaValue = 0
        card.orderFrontRegardless()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            card.alphaValue = 1
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.28
                card.animator().alphaValue = 1
            }
        }
    }

    private func dismiss(_ card: inout FloatingCard?) {
        guard let c = card else { return }
        card = nil
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { c.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            c.animator().alphaValue = 0
        }, completionHandler: { c.orderOut(nil) })
    }

    // MARK: Mood check-in

    func showMoodCheckIn() {
        guard moodCard == nil else { return }
        let size = CGSize(width: 380, height: 250)
        let card = FloatingCard(size: size)
        moodCard = card
        let v = visible
        let x = min(max(pet.position.x - size.width / 2, v.minX + 12), v.maxX - size.width - 12)
        let y = min(pet.position.y + 150 * pet.scale + 24, v.maxY - size.height - 12)
        show(card, MoodCheckInView(pet: pet) { [weak self] mood in
            guard let self else { return }
            if let mood {
                self.pet.setMood(mood)
                self.dismiss(&self.moodCard)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { self.showNote(for: mood) }
            } else {
                self.dismiss(&self.moodCard)
            }
        }, origin: CGPoint(x: x, y: y))
    }

    // MARK: Sticky note

    func showNote(for mood: Mood? = nil) {
        guard let mood = mood ?? pet.currentMood else { showMoodCheckIn(); return }
        if noteCard != nil { dismiss(&noteCard) }
        Prefs.noteDay = Date()
        let size = CGSize(width: 260, height: 300)
        let card = FloatingCard(size: size)
        noteCard = card
        applyPin(card, pinned: Prefs.notePinned)
        let v = visible
        let n = Fortune.note(for: mood, on: Calendar.current.startOfDay(for: Date()))
        show(card, StickyNoteView(mood: mood, text: n.text, extras: n.extras, pinned: Prefs.notePinned,
                                  togglePin: { [weak self, weak card] in
                                      guard let self, let card else { return }
                                      Prefs.notePinned.toggle()
                                      self.applyPin(card, pinned: Prefs.notePinned)
                                      self.refreshNote(mood: mood, text: n.text, extras: n.extras, card: card)
                                  },
                                  close: { [weak self] in
                                      guard let self else { return }
                                      self.dismiss(&self.noteCard)
                                  }),
             origin: CGPoint(x: v.maxX - size.width - 18, y: v.maxY - size.height - 30))
    }

    /// Once a day the note appears by itself, whether or not you answered the mood check-in.
    func showDailyNoteIfNeeded() {
        if let day = Prefs.noteDay, Calendar.current.isDateInToday(day) { return }
        showNote(for: pet.currentMood ?? .cozy)
    }

    /// Pinned: it sits on the desktop like a real post-it, under your windows. Unpinned: it floats on top.
    private func applyPin(_ card: FloatingCard, pinned: Bool) {
        card.level = pinned ? NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1) : .floating
        card.collectionBehavior = pinned ? [.canJoinAllSpaces, .stationary] : [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    private func refreshNote(mood: Mood, text: String, extras: String, card: FloatingCard) {
        guard let host = card.contentView as? NSHostingView<StickyNoteView> else { return }
        host.rootView = StickyNoteView(mood: mood, text: text, extras: extras, pinned: Prefs.notePinned,
                                       togglePin: host.rootView.togglePin, close: host.rootView.close)
    }

    // MARK: Study card

    /// A 9:16 card of today, to save, copy or post.
    func showStory() {
        if storyCard != nil { dismiss(&storyCard) }
        let data = StoryData(pet: pet)
        let size = CGSize(width: 252, height: 462)
        let card = FloatingCard(size: size)
        storyCard = card
        let v = visible
        let name = pet.name
        let image = StoryShare.image(data)
        show(card, StoryPreview(data: data, image: image,
            save: { [weak self] in
                guard let image else { return }
                self?.pet.say(StoryShare.save(image, name: name) != nil ? "saved to your Desktop 💌 go post it!" : "couldn't save that 😟", .happy, 4)
            },
            copy: { [weak self] in
                guard let image else { return }
                StoryShare.copy(image)
                self?.pet.say("copied! paste it into your story 💌", .happy, 4)
            },
            share: { [weak card] in
                guard let image, let view = card?.contentView else { return }
                NSSharingServicePicker(items: [image]).show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
            },
            close: { [weak self] in
                guard let self else { return }
                self.dismiss(&self.storyCard)
            }),
             origin: CGPoint(x: max(v.minX + 12, min(pet.position.x - size.width / 2, v.maxX - size.width - 12)),
                             y: min(v.maxY - size.height - 24, pet.position.y + 160 * pet.scale)))
    }

    // MARK: Achievement toast

    /// A little card slides in when a badge is earned, then tidies itself away.
    func showAchievement(_ badge: Badge) {
        if toastCard != nil { dismiss(&toastCard) }
        let size = CGSize(width: 330, height: 96)
        let card = FloatingCard(size: size)
        toastCard = card
        let v = visible
        show(card, AchievementToast(badge: badge), origin: CGPoint(x: v.maxX - size.width - 18, y: v.maxY - size.height - 16))
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.2) { [weak self, weak card] in
            guard let self, self.toastCard === card else { return }
            self.dismiss(&self.toastCard)
        }
    }

    // MARK: Chat

    var chatIsOpen: Bool { chatCard != nil }

    func toggleChat() {
        if chatCard != nil { dismiss(&chatCard); return }
        let size = CGSize(width: 366, height: 486)     // 330 x 440 of glass, plus room for its shadow
        let card = FloatingCard(size: size, takesKeyboard: true)
        chatCard = card
        chat.greetIfNeeded()
        let v = visible
        var x = pet.position.x + 120
        if x + size.width > v.maxX - 8 { x = pet.position.x - 120 - size.width }
        x = min(max(x, v.minX + 8), v.maxX - size.width - 8)
        let y = min(max(pet.position.y - 10, v.minY + 8), v.maxY - size.height - 8)
        show(card, FloatingChatDrawer(chat: chat, pet: pet, onClose: { [weak self] in
            guard let self else { return }
            self.dismiss(&self.chatCard)
        }, onStartBrain: { [weak self] in self?.startBrain?() }), origin: CGPoint(x: x, y: y))
        NSApp.activate(ignoringOtherApps: true)
        card.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Daily mood check-in

struct MoodCheckInView: View {
    @ObservedObject var pet: Pet
    var choose: (Mood?) -> Void

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 3) {
                Text("How are we feeling today, bestie?")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(UI.ink)
                    .multilineTextAlignment(.center)
                Text("no wrong answer. I'll match your vibe 💗")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(UI.inkSoft)
            }
            HStack(spacing: 8) {
                ForEach(Mood.allCases, id: \.self) { m in
                    Button { choose(m) } label: {
                        VStack(spacing: 5) {
                            Text(m.emoji).font(.system(size: 26))
                            Text(m.title)
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .foregroundStyle(UI.ink)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(LinearGradient(colors: [pill(m).opacity(0.6), pill(m).opacity(0.3)], startPoint: .top, endPoint: .bottom)))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(UI.glass(0.9), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(m.title)
                }
            }
            Button("maybe later") { choose(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(UI.inkSoft)
        }
        .padding(20)
        .frame(width: 344)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(UI.page)
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(UI.glass(0.9), lineWidth: 2))
                .shadow(color: UI.ink.opacity(0.2), radius: 18, y: 8)
        )
        .padding(18)
        .environment(\.colorScheme, AppTheme.current.isDark ? .dark : .light)
    }

    private func pill(_ m: Mood) -> Color {
        switch m {
        case .radiant: return UI.butter
        case .cozy: return UI.peach
        case .stressed: return UI.lilac
        case .tired: return UI.sky
        case .excited: return UI.blush
        }
    }
}

// MARK: - Sticky note

/// An aesthetic daily fortune, stuck to your desktop like a post-it. Drag it anywhere.
struct StickyNoteView: View {
    var mood: Mood
    var text: String
    var extras: String
    var pinned = false
    var togglePin: () -> Void = {}
    var close: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(mood.emoji) today's note")
                        .font(.custom("Noteworthy-Bold", size: 14))
                        .foregroundStyle(Color(red: 0.42, green: 0.30, blue: 0.40))
                    Spacer()
                    Button(action: togglePin) {
                        Image(systemName: pinned ? "pin.fill" : "pin")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(Color(red: 0.42, green: 0.30, blue: 0.40).opacity(pinned ? 0.95 : 0.6))
                    }
                    .buttonStyle(.plain)
                    .help(pinned ? "Unpin: let it float above your windows" : "Pin it to your desktop")
                    Button(action: close) {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(Color(red: 0.42, green: 0.30, blue: 0.40).opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("Put it away")
                }
                Text(text)
                    .font(.custom("Noteworthy-Light", size: 17))
                    .foregroundStyle(Color(red: 0.30, green: 0.22, blue: 0.32))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(extras)
                    .font(.custom("Noteworthy-Light", size: 11.5))
                    .foregroundStyle(Color(red: 0.42, green: 0.30, blue: 0.40).opacity(0.75))
            }
            .padding(.horizontal, 18).padding(.top, 26).padding(.bottom, 16)
            .frame(width: 220, height: 258)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.95, blue: 0.70), Color(red: 1.0, green: 0.88, blue: 0.80)],
                                         startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.22), radius: 9, x: 2, y: 6)
            )
            // a strip of washi tape
            Rectangle()
                .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.74, blue: 0.84).opacity(0.85), Color(red: 0.84, green: 0.76, blue: 1.0).opacity(0.85)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 74, height: 22)
                .rotationEffect(.degrees(-3))
                .offset(y: -9)
        }
        .rotationEffect(.degrees(-2.5))
        .padding(20)
    }
}

// MARK: - The floating chat drawer

/// A glassy chat window for "Cranberry AI", her brain: the Python service when it's running,
/// her own personality otherwise. It answers either way.
struct FloatingChatDrawer: View {
    @ObservedObject var chat: ChatState
    @ObservedObject var pet: Pet
    var onClose: () -> Void
    var onStartBrain: () -> Void
    @State private var inputMessage = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if !chat.brainOnline { offlineBanner }
            transcript
            inputBar
        }
        .frame(width: 330, height: 440)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(UI.page.opacity(0.55))
            }
        )
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(UI.glass(0.8), lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
        .padding(18)
        .environment(\.colorScheme, AppTheme.current.isDark ? .dark : .light)
        .onAppear { focused = true }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(LinearGradient(colors: [UI.blush.opacity(0.7), UI.lilac.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                AnimatedPet(pet: pet, scale: 0.26).offset(x: -2, y: -5).frame(width: 40, height: 40).clipShape(Circle())
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text("🐾 Cranberry AI Bestie")
                    .font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(UI.ink)
                HStack(spacing: 4) {
                    Circle().fill(chat.brainOnline ? Color.green : UI.butter).frame(width: 6, height: 6)
                    Text(chat.brainOnline ? "brain connected" : "chatting as \(pet.name)")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
                }
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(UI.inkSoft)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close chat")
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(UI.glass(0.5))
    }

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Text("💡").font(.system(size: 14))
            Text("Start the brain for homework help & email rewrites. I can still chat and do things without it.")
                .font(.system(size: 10.5, weight: .medium, design: .rounded)).foregroundStyle(UI.ink)
                .fixedSize(horizontal: false, vertical: true)
            Button("Start", action: onStartBrain)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(UI.hot))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(UI.butter.opacity(0.28))
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(chat.messages) { msg in ChatBubbleView(message: msg).id(msg.id) }
                    if chat.isThinking { typing.id("typing") }
                    if !chat.taskStatus.isEmpty {
                        Text(chat.taskStatus).font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(UI.inkSoft).padding(.leading, 4)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(14)
            }
            .onChange(of: chat.messages) { _, _ in withAnimation { proxy.scrollTo("end") } }
            .onChange(of: chat.isThinking) { _, _ in withAnimation { proxy.scrollTo("end") } }
        }
    }

    private var typing: some View {
        TimelineView(.animation(minimumInterval: 0.12)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(UI.inkSoft).frame(width: 6, height: 6)
                        .opacity(0.35 + 0.65 * (sin(t * 6 + Double(i)) + 1) / 2)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(Capsule().fill(UI.glass(0.75)))
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Talk to Cranberry...", text: $inputMessage)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(UI.ink)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Capsule().fill(UI.glass(0.7)))
                .focused($focused)
                .onSubmit(sendMessage)
            Button(action: sendMessage) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(UI.hot))
            }
            .buttonStyle(.plain)
            .disabled(inputMessage.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Send")
        }
        .padding(12)
        .background(UI.glass(0.4))
    }

    private func sendMessage() {
        guard !inputMessage.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        chat.send(inputMessage)
        inputMessage = ""
    }
}

struct ChatBubbleView: View {
    var message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(message.role == .user ? Color.white : UI.ink)
                .padding(.horizontal, 13).padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(message.role == .user ? AnyShapeStyle(UI.hot) : AnyShapeStyle(UI.glass(0.8)))
                )
                .textSelection(.enabled)
            if message.role != .user { Spacer(minLength: 40) }
        }
    }
}


// MARK: - Achievement toast

struct AchievementToast: View {
    var badge: Badge

    var body: some View {
        HStack(spacing: 14) {
            Text(badge.emoji)
                .font(.system(size: 34))
                .frame(width: 56, height: 56)
                .background(Circle().fill(LinearGradient(colors: [Color(red: 1.0, green: 0.90, blue: 0.70), Color(red: 1.0, green: 0.80, blue: 0.88)],
                                                          startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2.5))
            VStack(alignment: .leading, spacing: 2) {
                Text("achievement unlocked ✨")
                    .font(.system(size: 10.5, weight: .heavy, design: .rounded)).foregroundStyle(UI.inkSoft).textCase(.uppercase).kerning(0.4)
                Text(badge.title)
                    .font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(UI.ink).lineLimit(1)
                Text("\(badge.detail)  ·  +15 🍓")
                    .font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.97, blue: 0.93), Color(red: 0.98, green: 0.93, blue: 1.0)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
        )
        .padding(12)
        .environment(\.colorScheme, .light)
    }
}

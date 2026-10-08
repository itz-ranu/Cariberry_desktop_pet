import Foundation
import Security
import SwiftUI

// MARK: - Keychain

/// API keys for the optional cloud chat brains live in the macOS Keychain, never in a
/// plain file or in the repo.
enum Keychain {
    private static let service = "com.desktoppup.cariberry.chat"

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, for account: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// Which brain answers chat. "local" needs nothing: the on-device model, or her own
/// personality quips. Everything else needs your own account.
enum ChatProvider: String, CaseIterable {
    case local, ollama, openai, gemini

    var title: String {
        switch self {
        case .local: return "On this Mac only"
        case .ollama: return "Ollama (local model)"
        case .openai: return "ChatGPT / OpenAI"
        case .gemini: return "Gemini"
        }
    }
    var needsKey: Bool { self == .openai || self == .gemini }
    var keyAccount: String { rawValue }
    var defaultModel: String {
        switch self {
        case .local: return ""
        case .ollama: return "llama3.2"
        case .openai: return "gpt-4o-mini"
        case .gemini: return "gemini-2.0-flash"
        }
    }
    /// Who sees what you type in chat.
    var privacy: String {
        switch self {
        case .local: return "Your messages never leave this Mac."
        case .ollama: return "Your messages go to Ollama running on this Mac."
        case .openai: return "Your chat messages, plus her name, personality and the mood you picked, are sent to OpenAI. Nothing else is. OpenAI sets its own age limit and terms."
        case .gemini: return "Your chat messages, plus her name, personality and the mood you picked, are sent to Google. Nothing else is. Google sets its own age limit and terms."
        }
    }
}

// MARK: - Chat state

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, pet, system }
    let id = UUID()
    var role: Role
    var text: String
}

/// The conversation shown in the floating chat drawer. Replies come from the Python
/// "Cranberry" brain when it's running (through the loopback bridge), and from a built-in
/// personality fallback when it isn't, so the drawer always answers.
@MainActor
final class ChatState: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isThinking = false
    @Published private(set) var brainOnline = false
    @Published var taskStatus: String = ""

    weak var pet: Pet?
    var bridge: CranberryBridge?
    private var pendingID: String?
    private var streamingIndex: Int?

    init() {}

    func greetIfNeeded() {
        guard messages.isEmpty, let pet else { return }
        messages.append(ChatMessage(role: .pet, text: Dialogue.line(.greetDay, pet.species, name: pet.name)
                                    + "\nask me anything, or say “focus 25” to start a session 🐾"))
    }

    func setBrainOnline(_ online: Bool) {
        guard online != brainOnline else { return }
        brainOnline = online
    }

    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let pet else { return }
        messages.append(ChatMessage(role: .user, text: text))

        // things she can just *do* are handled right here, instantly, on any brain
        if let reply = LocalChat.command(text, pet: pet) {
            messages.append(ChatMessage(role: .pet, text: reply))
            return
        }
        if brainOnline, let bridge {
            isThinking = true
            let id = UUID().uuidString
            pendingID = id
            bridge.sendChat(id: id, text: text, pet: pet)
            // if the brain goes quiet, fall back rather than leave her hanging
            DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
                guard let self, self.pendingID == id else { return }
                self.finishReply(id: id, text: LocalChat.reply(to: text, pet: pet))
            }
        } else {
            isThinking = true
            let pet = pet
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.isThinking = false
                self?.messages.append(ChatMessage(role: .pet, text: LocalChat.reply(to: text, pet: pet)))
            }
        }
    }

    // MARK: From the brain

    func receiveHeard(_ text: String) { messages.append(ChatMessage(role: .user, text: text)) }

    func receiveChunk(id: String, text: String, done: Bool, mood: String?) {
        // a reply nobody asked for in the drawer (a voice command) starts its own thread
        if pendingID == nil { pendingID = id }
        guard id == pendingID else { return }
        isThinking = false
        if let i = streamingIndex, messages.indices.contains(i) {
            messages[i].text += text
        } else {
            messages.append(ChatMessage(role: .pet, text: text))
            streamingIndex = messages.count - 1
        }
        if done {
            pendingID = nil
            streamingIndex = nil
            if let last = messages.last, last.role == .pet {
                pet?.say(String(last.text.prefix(120)), mood.flatMap(Emotion.init(rawValue:)), 4)
            }
        }
    }

    private func finishReply(id: String, text: String) {
        guard id == pendingID else { return }
        pendingID = nil
        isThinking = false
        messages.append(ChatMessage(role: .pet, text: text))
    }

    func receiveStatus(_ text: String) { taskStatus = text }
}

// MARK: - Personality fallback

/// Chat that works with no Python and no internet: she answers in her own voice, and a few
/// phrases do real things ("focus 25", "dance", "stay").
@MainActor
enum LocalChat {
    /// Phrases that act on her instead of chatting. Returns the reply, or nil if it isn't one.
    static func command(_ text: String, pet: Pet) -> String? {
        let t = text.lowercased()
        if let r = t.range(of: #"focus(?: for)? (\d{1,3})"#, options: .regularExpression) {
            let mins = Double(t[r].filter(\.isNumber)) ?? 25
            pet.startFocus(minutes: min(max(mins, 1), 240), intention: pet.intention)
            return Dialogue.line(.timerStart, pet.species, ["n": "\(Int(mins))"])
        }
        if t.contains("start a focus") || t == "focus" || t.contains("study with me") {
            pet.startFocus(minutes: 25, intention: pet.intention)
            return Dialogue.line(.timerStart, pet.species, ["n": "25"])
        }
        if t.contains("dance") { pet.dance(); return Dialogue.line(.dance, pet.species) }
        if t.contains("sit still") || t == "stay" || t.contains("stay here") {
            if !pet.staying { pet.toggleStay() }
            return Dialogue.line(.stay, pet.species)
        }
        if t.contains("come here") || t.contains("come to me") { pet.comeHere(); return Dialogue.line(.comeHere, pet.species) }
        if t.contains("feed me") == false, t.hasPrefix("feed") { pet.feed(); return Dialogue.line(.fed, pet.species) }
        if t.contains("go to sleep") || t.contains("nap") { pet.nap(); return Dialogue.line(.sleepy, pet.species) }
        return nil
    }

    static func reply(to text: String, pet: Pet) -> String {
        let t = text.lowercased()
        let s = pet.species
        func has(_ words: [String]) -> Bool { words.contains { t.contains($0) } }
        if has(["hello", "hi ", "hey", "good morning", "good night"]) || t == "hi" { return Dialogue.line(.greetDay, s, name: pet.name) }
        if has(["thank", "thx", "ty "]) { return Dialogue.line(.petted, s) }
        if has(["love you", "ily", "i love"]) { return Dialogue.line(.petted, s) }
        if has(["stressed", "anxious", "overwhelmed", "panic", "worried"]) { return Mood.stressed.reply(s) }
        if has(["tired", "exhausted", "sleepy", "drained"]) { return Mood.tired.reply(s) }
        if has(["sad", "lonely", "cry", "down", "bad day"]) { return Mood.stressed.reply(s) + " 🫂" }
        if has(["hungry", "snack", "food"]) { return Dialogue.line(.hungry, s) }
        if has(["bored"]) { return Dialogue.line(.bored, s) }
        if has(["study", "homework", "exam", "essay", "assignment", "deadline"]) {
            return Dialogue.line(.praise, s) + "\nwant me to sit with you? say “focus 25” 📖"
        }
        if has(["help", "what can you do"]) {
            return "I can chat, cheer you on, and do things: “focus 25”, “dance”, “stay”, “come here”. Connect a chat brain in Settings and I can help with homework and emails too 💗"
        }
        if has(["water", "drink"]) { return Dialogue.line(.water, s) }
        if has(["stretch"]) { return Dialogue.line(.stretchRemind, s) }
        if has(["joke"]) { return jokes.randomElement() ?? "" }
        return Dialogue.line(.chatter, s)
    }

    private static let jokes = [
        "why did the student eat their homework? the teacher said it was a piece of cake 🍰",
        "I told my laptop I needed a break. it said it'd been waiting for me to say that 🔋",
        "what do you call a sleepy pet? a nap-stronaut 🚀💤",
    ]
}

import SwiftUI

// The Wardrobe tab: who she is (species, colour, size, name, where she lives), what she's
// wearing, and the Sanctuary where berries buy rugs, clothes and decor.
extension PanelView {

    var wardrobe: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(WardrobePage.allCases, id: \.self) { page in
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.8)) { wardrobePage = page }
                    } label: {
                        Text(page == .shop ? "🍓 \(pet.berries)" : page.rawValue)
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(wardrobePage == page ? Color.white : UI.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(wardrobePage == page ? AnyShapeStyle(UI.hot) : AnyShapeStyle(UI.glass(0.6))))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(wardrobePage == page ? .isSelected : [])
                }
            }
            switch wardrobePage {
            case .her: herSection
            case .closet: closetSection
            case .shop: shopSection
            }
        }
    }

    // MARK: Pets

    var herSection: some View {
        VStack(spacing: 12) {
            if welcome { welcomeBanner }
            card {
                VStack(alignment: .leading, spacing: 10) {
                    label("✨ Pick your bestie")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(Species.allCases, id: \.self) { s in speciesCard(s) }
                    }
                }
            }
            card {
                VStack(alignment: .leading, spacing: 10) {
                    label("🎨 Colour")
                    HStack(spacing: 14) {
                        ForEach(0..<pet.species.coats.count, id: \.self) { i in swatch(i) }
                        Spacer(minLength: 0)
                    }
                }
            }
            card {
                VStack(alignment: .leading, spacing: 10) {
                    label("📍 Where she lives")
                    Picker("Home", selection: Binding(get: { pref(Prefs.placeAnywhere) }, set: {
                        Prefs.placeAnywhere = $0
                        if !$0 { pet.goHome() }
                        refresh += 1
                    })) {
                        Text("On the floor").tag(false)
                        Text("Anywhere I drop her").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    Text(Prefs.placeAnywhere
                         ? "Drag her anywhere on your screen. She'll sit on a cushion right where you let go."
                         : "She always settles back onto the bottom of your screen.")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
                    if pet.perched {
                        Button("Send her home 🏠") { pet.goHome(); refresh += 1 }.buttonStyle(ChipStyle(tint: UI.blush))
                    }
                }
            }
            card {
                VStack(alignment: .leading, spacing: 10) {
                    label("📏 Size on screen")
                    Picker("Size", selection: Binding(get: { pet.sizeLevel }, set: { pet.chooseSize($0) })) {
                        ForEach(0..<Stage.sizeNames.count, id: \.self) { Text(Stage.sizeNames[$0]).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
            }
            card {
                VStack(alignment: .leading, spacing: 10) {
                    label("💌 Name")
                    HStack {
                        TextField("Name", text: $nameDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(UI.track))
                            .onSubmit { actions.rename(nameDraft) }
                        Button("Save") { actions.rename(nameDraft) }
                            .buttonStyle(ChipStyle())
                            .disabled(nameDraft.trimmingCharacters(in: .whitespaces).isEmpty || nameDraft == pet.name)
                    }
                }
            }
        }
    }

    func pref(_ v: Bool) -> Bool { _ = refresh; return v }

    var welcomeBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Welcome to Cariberry ✨")
                .font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            Text("Pick your bestie below. She'll keep you company, cheer when you focus, and bark when you doom-scroll. You can change her any time.")
                .font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(UI.hot))
    }

    func speciesCard(_ s: Species) -> some View {
        let selected = pet.species == s
        let coat = selected ? pet.coatIndex : Prefs.coat(for: s)
        return Button { pet.chooseSpecies(s) } label: {
            VStack(spacing: 0) {
                StaticCritter(species: s, coat: coat, outfit: pet.outfit, scale: 0.34).equatable()
                    .offset(y: 3)
                Text(s.displayName)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(UI.ink).lineLimit(1)
                    .padding(.bottom, 7)
            }
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(selected ? AnyShapeStyle(UI.lilac.opacity(0.26)) : AnyShapeStyle(UI.track)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? UI.lilac : .clear, lineWidth: 2.2))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13)).foregroundStyle(UI.lilac)
                        .background(Circle().fill(.white).padding(2)).padding(3)
                }
            }
        }
        .buttonStyle(PressStyle(reduce: reduceMotion))
        .help(s.blurb)
        .accessibilityLabel("\(s.displayName). \(s.blurb)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    func swatch(_ i: Int) -> some View {
        let coat = pet.species.coats[i]
        let selected = pet.coatIndex == i
        return Button { pet.chooseCoat(i) } label: {
            VStack(spacing: 5) {
                Circle()
                    .fill(LinearGradient(colors: [coat.light, coat.mid, coat.shade],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 34, height: 34)
                    .overlay(Circle().strokeBorder(UI.ink.opacity(0.12)))
                    .padding(3)
                    .overlay(Circle().strokeBorder(selected ? UI.lilac : .clear, lineWidth: 2.4))
                Text(coat.name)
                    .font(.system(size: 10.5, weight: selected ? .bold : .medium, design: .rounded))
                    .foregroundStyle(selected ? UI.ink : UI.inkSoft)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(coat.name) colour")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Closet

    var closetSection: some View {
        VStack(spacing: 12) {
            card {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(LinearGradient(colors: [UI.blush.opacity(0.6), UI.lilac.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        AnimatedPet(pet: pet, scale: 0.5).offset(x: -3, y: -9).frame(width: 96, height: 96).clipShape(Circle())
                    }
                    .frame(width: 96, height: 96)
                    VStack(alignment: .leading, spacing: 5) {
                        label("Today's look")
                        Text(pet.outfit.isEmpty ? "Nothing on yet. Tap things below ✨" : "\(pet.outfit.count) thing\(pet.outfit.count == 1 ? "" : "s") on")
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded)).foregroundStyle(UI.ink)
                        if !pet.outfit.isEmpty {
                            Button("Take all off") { pet.clearOutfit() }.buttonStyle(ChipStyle(tint: UI.blush))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            ForEach(AccessorySlot.allCases, id: \.self) { slot in
                card {
                    VStack(alignment: .leading, spacing: 8) {
                        label(slot.title)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                            ForEach(Accessory.items(for: slot), id: \.self) { a in accessoryChip(a) }
                        }
                    }
                }
            }
        }
    }

    /// One item in the closet. Things she doesn't own yet are dimmed with their price; tapping
    /// one jumps to the Sanctuary.
    func accessoryChip(_ a: Accessory) -> some View {
        let selected = pet.outfit[a.slot] == a
        let owned = pet.owns(a)
        return Button {
            if owned { pet.wear(a); pet.touch() } else { wardrobePage = .shop }
        } label: {
            VStack(spacing: 2) {
                Text(a.emoji).font(.system(size: 17))
                Text(a.title)
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(UI.ink).lineLimit(1).minimumScaleFactor(0.8)
                if !owned { Text("🍓 \(a.price)").font(.system(size: 8.5, weight: .bold, design: .rounded)).foregroundStyle(UI.inkSoft) }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? UI.lilac.opacity(0.32) : UI.track))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? UI.lilac : .clear, lineWidth: 2))
            .opacity(owned ? 1 : 0.5)
        }
        .buttonStyle(PressStyle(reduce: reduceMotion))
        .help(owned ? (selected ? "Take off \(a.title.lowercased())" : "Put on \(a.title.lowercased())") : "\(a.title): \(a.price) berries in the Sanctuary")
        .accessibilityLabel(owned ? a.title : "\(a.title), \(a.price) berries")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Sanctuary

    var shopSection: some View {
        VStack(spacing: 12) {
            card {
                HStack(spacing: 12) {
                    Text("🍓").font(.system(size: 34))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(pet.berries) berries")
                            .font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(UI.ink)
                        Text("Earn them by focusing: 1 a minute, +3 a task, +10 a session, +25 for your goal.")
                            .font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
                    }
                    Spacer(minLength: 0)
                }
            }
            if let note = shopMessage {
                Text(note).font(.system(size: 11.5, weight: .bold, design: .rounded)).foregroundStyle(UI.ink)
                    .frame(maxWidth: .infinity).padding(8)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(UI.butter.opacity(0.4)))
            }
            let forSale = Accessory.allCases.filter { $0 != .none && $0.price > 0 }
            card {
                VStack(alignment: .leading, spacing: 10) {
                    label("Rugs, clothes & more")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(forSale, id: \.self) { a in shopTile(emoji: a.emoji, title: a.title, price: a.price, owned: pet.owns(a)) {
                            buyNote(pet.buy(a), a.title); pet.touch()
                        } }
                    }
                }
            }
            card {
                VStack(alignment: .leading, spacing: 10) {
                    label("Room decor, companions & weather")
                    Text("Little things that sit beside her, and soft particles that drift through her corner. One kind of weather at a time.")
                        .font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(UI.inkSoft)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(Decor.allCases, id: \.self) { d in
                            let owned = pet.owns(d)
                            shopTile(emoji: d.emoji, title: d.title, price: d.price, owned: owned,
                                     active: pet.decorOn.contains(d.rawValue)) {
                                if owned { pet.toggleDecor(d) } else { buyNote(pet.buy(d), d.title) }
                                pet.touch()
                            }
                        }
                    }
                }
            }
        }
    }

    func buyNote(_ ok: Bool, _ title: String) {
        shopMessage = ok ? "got the \(title.lowercased())! 🎉" : nil
        if ok { DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { shopMessage = nil } }
    }

    func shopTile(emoji: String, title: String, price: Int, owned: Bool, active: Bool = false,
                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(emoji).font(.system(size: 24))
                Text(title).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(UI.ink).lineLimit(1)
                Text(owned ? (active ? "on show ✓" : "owned") : "🍓 \(price)")
                    .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(owned ? UI.inkSoft : (pet.berries >= price ? UI.ink : UI.inkSoft))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(owned ? UI.track : (pet.berries >= price ? UI.sage.opacity(0.7) : UI.track)))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(active ? UI.lilac.opacity(0.28) : UI.track))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(active ? UI.lilac : .clear, lineWidth: 2))
        }
        .buttonStyle(PressStyle(reduce: reduceMotion))
        .accessibilityLabel(owned ? "\(title), owned" : "\(title), \(price) berries")
    }
}

/// A pet that never moves (the species picker, say). It's drawn straight at its on-screen size, and
/// `Equatable` lets SwiftUI skip redrawing it when the panel around it refreshes.
struct StaticCritter: View, Equatable {
    var species: Species
    var coat: Int
    var outfit: Outfit
    var scale: CGFloat

    var body: some View {
        CritterView(species: species, coat: coat, pose: Pose(emotion: .happy, phase: 0.4, outfit: outfit), scale: scale)
    }
}

#if os(iOS)
import SwiftUI

struct SaveSlot: Codable {
    var level = 0
    var powerups: Set<Powerup> = []
    var lastPlayed = Date()
}

private struct UnsaveRectKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

enum SaveStore {
    private static let key = "saveSlots"

    static func load() -> [SaveSlot] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let slots = try? JSONDecoder().decode([SaveSlot].self, from: data)
        else { return [] }
        return slots
    }

    static func save(_ slots: [SaveSlot]) {
        if let data = try? JSONEncoder().encode(slots) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

struct FeedView: View {

    private static let levelCount = 15
    private static let adLevels: Set<Int> = [7]

    @State private var scenes: [LevelScene]?
    @State private var currentLevel = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var heldDirection: CGFloat = 0
    @State private var openApp: String?
    @State private var loading = false
    @State private var showGame = false
    @State private var screenSize: CGSize = .zero
    @State private var slots: [SaveSlot] = SaveStore.load()
    @State private var activeSlot: Int?
    @State private var choosingSlot = false
    @State private var unsaveIndex: Int?
    @State private var pressedIndex: Int?
    @State private var menuRect: CGRect = .zero
    @State private var menuLeft = false
    @State private var gateUnlocked = false

    private static let screenSpring = Animation.spring(response: 0.32, dampingFraction: 0.88)
    // ios app open depth feel
    private static let screenIn = AnyTransition.scale(scale: 0.92).combined(with: .opacity)
    private static let screenOut = AnyTransition.scale(scale: 1.08).combined(with: .opacity)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // prewarm so first transitions dont hitch
                Group {
                    slotScreen
                    appScreen("settings")
                    loadingScreen
                }
                .opacity(0.01)
                .allowsHitTesting(false)

                // game warms up hidden behind the menu
                if let scenes {
                    feed(scenes)
                        .opacity(showGame ? 1 : 0)
                        .scaleEffect(showGame ? 1 : 1.05)
                        .allowsHitTesting(showGame)
                }
                if !showGame {
                    if loading {
                        loadingScreen
                            .transition(Self.screenIn)
                    } else if choosingSlot {
                        slotScreen
                            .transition(Self.screenIn)
                    } else if let openApp {
                        appScreen(openApp)
                            .transition(Self.screenIn)
                    } else {
                        homeScreen(size: geo.size)
                            .transition(Self.screenOut)
                    }
                }
            }
            .animation(Self.screenSpring, value: showGame)
            .animation(Self.screenSpring, value: loading)
            .animation(Self.screenSpring, value: choosingSlot)
            .animation(Self.screenSpring, value: openApp)
            .onAppear {
                screenSize = geo.size
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    preload(size: geo.size)
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    private var loadingScreen: some View {
        ZStack {
            Color.black
            VStack(spacing: 14) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.2)
                Text("loading")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private func preload(size: CGSize) {
        guard scenes == nil else { return }
        start(size: size)
    }

    // tiktok saved page, saves as video thumbnails
    private static let haptic = UIImpactFeedbackGenerator(style: .medium)

    private var slotScreen: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            if unsaveIndex != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { dismissUnsave() }
            }
            VStack(spacing: 0) {
                Text("Saved")
                    .font(.headline).bold()
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 62)

                HStack(spacing: 30) {
                    VStack(spacing: 7) {
                        Text("Videos")
                            .font(.subheadline).bold()
                            .foregroundStyle(.white)
                        Rectangle().fill(.white).frame(width: 34, height: 2)
                    }
                    VStack(spacing: 7) {
                        Text("Sounds")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.4))
                        Color.clear.frame(width: 34, height: 2)
                    }
                    VStack(spacing: 7) {
                        Text("Posts")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.4))
                        Color.clear.frame(width: 34, height: 2)
                    }
                }
                .padding(.top, 20)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3),
                          spacing: 2) {
                    // one new save tile always follows the last save
                    ForEach(0..<(slots.count + 1), id: \.self) { i in
                        slotCard(i)
                            .scaleEffect(pressedIndex == i ? 0.92 : 1)
                            .animation(.easeOut(duration: 0.12), value: pressedIndex)
                            .onTapGesture {
                                if unsaveIndex != nil {
                                    dismissUnsave()
                                } else {
                                    chooseSlot(i)
                                }
                            }
                            .onLongPressGesture(minimumDuration: 0.22) {
                                if i < slots.count {
                                    Self.haptic.impactOccurred()
                                    unsaveIndex = i
                                }
                            } onPressingChanged: { pressing in
                                pressedIndex = pressing ? i : nil
                            }
                            .background(
                                GeometryReader { g in
                                    Color.clear.preference(
                                        key: UnsaveRectKey.self,
                                        value: unsaveIndex == i
                                            ? g.frame(in: .named("saved")) : .zero)
                                }
                            )
                    }
                }
                .padding(.top, 18)
                .padding(.horizontal, 2)

                Spacer()
            }

            Button {
                choosingSlot = false
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(24)
            }
            .padding(.top, 40)

            // always mounted, scales out of the pressed save
            unsaveMenu(unsaveIndex ?? 0)
                .scaleEffect(unsaveIndex != nil ? 1 : 0.12,
                             anchor: UnitPoint(x: menuLeft ? 0.75 : 0.25, y: -0.45))
                .opacity(unsaveIndex != nil ? 1 : 0)
                .allowsHitTesting(unsaveIndex != nil)
                .position(x: menuLeft ? menuRect.maxX - 68 : menuRect.minX + 68,
                          y: menuRect.maxY + 15)
                .animation(.spring(response: 0.26, dampingFraction: 0.82),
                           value: unsaveIndex != nil)
        }
        .coordinateSpace(name: "saved")
        .onPreferenceChange(UnsaveRectKey.self) { rect in
            if rect != .zero {
                menuRect = rect
                menuLeft = (unsaveIndex ?? 0) % 3 == 2
            }
        }
        .onAppear { Self.haptic.prepare() }
    }

    private func unsaveMenu(_ i: Int) -> some View {
        Button {
            slots.remove(at: i)
            SaveStore.save(slots)
            dismissUnsave()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "bookmark.slash.fill")
                    .font(.system(size: 14))
                Text("Unsave")
                    .font(.footnote).bold()
            }
            .foregroundStyle(.white)
            .frame(width: 120, height: 42)
            .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.45), radius: 7, y: 3)
        }
        .buttonStyle(.plain)
    }

    private func dismissUnsave() {
        unsaveIndex = nil
    }

    private func slotCard(_ i: Int) -> some View {
        let slot = i < slots.count ? slots[i] : nil
        return ZStack {
            Rectangle().fill(Color(white: 0.09))
            if slot != nil {
                // tiny mock of a level as the video cover
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.white.opacity(0.9), lineWidth: 1.5)
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(.white)
                        .frame(width: 13, height: 13)
                        .padding(.bottom, 10)
                }
                .padding(12)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .medium))
                    Text("New Save")
                        .font(.caption2)
                }
                .foregroundStyle(.white.opacity(0.45))
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let slot {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                    Text("lvl \(Self.displayLevel(for: slot.level))")
                        .font(.caption2).bold()
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 2)
                .padding(7)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let slot, !slot.powerups.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(slot.powerups), id: \.self) { p in
                        Image(uiImage: GameArt.icon(for: p))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22)
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 4)
                .background(.white.opacity(0.2), in: Capsule())
                .padding(6)
            }
        }
        .aspectRatio(0.72, contentMode: .fit)
        .contentShape(Rectangle())
    }

    private func chooseSlot(_ i: Int) {
        let slot: SaveSlot
        if i < slots.count {
            slot = slots[i]
            activeSlot = i
        } else {
            slot = SaveSlot()
            slots.append(slot)
            activeSlot = slots.count - 1
        }
        SaveStore.save(slots)

        if scenes != nil {
            enterGame(slot)
        } else {
            // fallback if play lands before the preload finished
            loading = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                preload(size: screenSize)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    enterGame(slot)
                }
            }
        }
    }

    private func enterGame(_ slot: SaveSlot) {
        guard let scenes else { return }
        let level = min(max(slot.level, 0), Self.levelCount - 1)
        if slot.powerups.contains(.doubleJump) {
            for s in scenes { s.extraJumps = 1 }
        }
        scenes[level].prepareEntry(atXFraction: 0.5)

        currentLevel = level
        scrollOffset = 0
        gateUnlocked = false
        loading = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            choosingSlot = false
            showGame = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            scenes[level].beginEntry()
        }
    }

    private func saveProgress() {
        guard let a = activeSlot, a < slots.count else { return }
        slots[a].level = currentLevel
        if scenes?.first?.extraJumps ?? 0 > 0 {
            slots[a].powerups.insert(.doubleJump)
        }
        slots[a].lastPlayed = Date()
        SaveStore.save(slots)
    }

    private func exitGame() {
        saveProgress()
        showGame = false
        choosingSlot = false
        activeSlot = nil
        heldDirection = 0
        // reset only after the feed unmounts
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            scenes = nil
            currentLevel = 0
            scrollOffset = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                preload(size: screenSize)
            }
        }
    }

    // fake iphone home screen, the game hides behind the play app
    private func homeScreen(size: CGSize) -> some View {
        ZStack {
            Color.black
            VStack(spacing: 30) {
                widget
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4),
                          spacing: 22) {
                    AppIcon(art: .settings, label: "Settings") { openApp = "settings" }
                    AppIcon(art: .tips, label: "Tips") { openApp = "tips" }
                    AppIcon(art: .music, label: "Music") { openApp = "music" }
                    AppIcon(art: .play, label: "Scroll of Doom") { choosingSlot = true }
                    AppIcon(art: .messages, label: "Messages")
                    AppIcon(art: .camera, label: "Camera")
                    AppIcon(art: .photos, label: "Photos")
                    AppIcon(art: .clock, label: "Clock")
                    AppIcon(art: .calendar, label: "Calendar")
                    AppIcon(art: .maps, label: "Maps")
                }
                Spacer()
                dock
            }
            .padding(.top, 78)
            .padding(.horizontal, 26)
            .padding(.bottom, 24)
        }
    }

    // medium widget, 4x2
    private var widget: some View {
        Image("widget")
            .resizable()
            .aspectRatio(2.13, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var dock: some View {
        RoundedRectangle(cornerRadius: 30)
            .fill(.white.opacity(0.1))
            .frame(height: 92)
            .overlay(
                HStack(spacing: 26) {
                    AppIcon(art: .phone)
                    AppIcon(art: .safari)
                    AppIcon(art: .mail)
                    AppIcon(art: .facetime)
                }
            )
    }

    private func appScreen(_ name: String) -> some View {
        ZStack(alignment: .topLeading) {
            Color.black
            Text(name)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button {
                openApp = nil
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(24)
            }
            .padding(.top, 54)
        }
    }

    private func start(size: CGSize) {
        let built = (0..<Self.levelCount).map { i -> LevelScene in
            let s = LevelScene(size: size)
            s.levelIndex = i
            s.isAdLevel = Self.adLevels.contains(i)
            s.bottomInset = GameTabBar.height
            return s
        }
        for (i, scene) in built.enumerated() {
            scene.onFellThrough = { xFrac in advance(from: i, entryFrac: xFrac) }
            scene.onHatchOpened = { if currentLevel == i { gateUnlocked = true } }
            // powerups persist for the whole run
            scene.onCollectWings = {
                for s in built { s.extraJumps = 1 }
                saveProgress()
            }
        }
        scenes = built
    }

    private func feed(_ scenes: [LevelScene]) -> some View {
        ZStack(alignment: .topLeading) {
            feedScroll(scenes)
            Button {
                exitGame()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 3)
                    .padding(24)
            }
            .padding(.top, 54)
        }
        // outside the scroll so it never moves
        .overlay(alignment: .bottom) {
            GameTabBar(gateUnlocked: gateUnlocked,
                       onMove: { dir in
                           heldDirection = dir
                           scenes[currentLevel].setMove(dir)
                       },
                       onJump: {
                           scenes[currentLevel].jump()
                       })
        }
    }

    // current and next page always mounted so the scroll never hits a
    // first render, the offset animates and the window slides after
    private func feedScroll(_ scenes: [LevelScene]) -> some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack(alignment: .top) {
                ForEach(visiblePages, id: \.self) { index in
                    LevelPageView(levelIndex: index,
                                  displayLevel: Self.displayLevel(for: index),
                                  isAd: Self.adLevels.contains(index),
                                  scene: scenes[index])
                        .frame(width: geo.size.width, height: h)
                        .offset(y: scrollOffset + CGFloat(index - currentLevel) * h)
                }
            }
        }
        .ignoresSafeArea()
    }

    private var visiblePages: [Int] {
        currentLevel + 1 < Self.levelCount ? [currentLevel, currentLevel + 1] : [currentLevel]
    }

    // ads and future boss levels dont count toward the shown level number
    private static func displayLevel(for index: Int) -> Int {
        index + 1 - adLevels.filter { $0 < index }.count
    }

    private func advance(from index: Int, entryFrac: CGFloat) {
        guard let scenes, index + 1 < Self.levelCount else { return }
        scenes[index + 1].prepareEntry(atXFraction: entryFrac)
        scenes[index].setMove(0)
        scenes[index + 1].setMove(heldDirection)
        gateUnlocked = false
        withAnimation(.easeInOut(duration: 0.45)) {
            scrollOffset = -screenSize.height
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.46) {
            currentLevel = index + 1
            scrollOffset = 0
            scenes[index + 1].beginEntry()
        }
        saveProgress()
    }
}

private struct AppIcon: View {
    enum Art {
        case settings, tips, messages, camera, photos, clock, calendar,
             music, maps, phone, safari, mail, facetime, play
    }

    let art: Art
    var label: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        Button { action?() } label: {
            VStack(spacing: 6) {
                artwork
                    .frame(width: 62, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                if let label {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func gradient(_ top: Double, _ bottom: Double) -> LinearGradient {
        LinearGradient(colors: [Color(white: top), Color(white: bottom)],
                       startPoint: .top, endPoint: .bottom)
    }

    @ViewBuilder private var artwork: some View {
        switch art {
        case .settings:
            ZStack {
                gradient(0.35, 0.15)
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color(white: 0.8))
            }
        case .tips:
            ZStack {
                gradient(0.75, 0.5)
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
            }
        case .messages:
            ZStack {
                gradient(0.6, 0.35)
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
            }
        case .camera:
            ZStack {
                gradient(0.85, 0.65)
                Image(systemName: "camera.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color(white: 0.15))
            }
        case .photos:
            ZStack {
                Color.white
                // overlapping petals darken where they cross, like the real flower
                ForEach(0..<8, id: \.self) { i in
                    Ellipse()
                        .fill(Color(white: 0.3 + Double(i) * 0.07).opacity(0.65))
                        .frame(width: 16, height: 30)
                        .offset(y: -12)
                        .rotationEffect(.degrees(Double(i) * 45))
                        .blendMode(.multiply)
                }
            }
        case .clock:
            ZStack {
                Color.black
                Circle().fill(.white).padding(5)
                ForEach(0..<12, id: \.self) { i in
                    Capsule()
                        .fill(.black)
                        .frame(width: 1.5, height: i % 3 == 0 ? 6 : 3.5)
                        .offset(y: -21)
                        .rotationEffect(.degrees(Double(i) * 30))
                }
                Capsule().fill(.black).frame(width: 2.5, height: 15)
                    .offset(y: -7.5)
                    .rotationEffect(.degrees(305))
                Capsule().fill(.black).frame(width: 2, height: 21)
                    .offset(y: -10.5)
                    .rotationEffect(.degrees(70))
                Circle().fill(.black).frame(width: 4, height: 4)
            }
        case .calendar:
            ZStack {
                Color.white
                VStack(spacing: -2) {
                    Text("FRI")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(white: 0.45))
                    Text("4")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.black)
                }
            }
        case .music:
            ZStack {
                gradient(0.55, 0.25)
                Image(systemName: "music.note")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
            }
        case .maps:
            ZStack {
                Color(white: 0.9)
                // side streets, freeway, and the blue-dot stand-in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(white: 0.75))
                    .frame(width: 80, height: 4)
                    .rotationEffect(.degrees(-32))
                    .offset(y: -14)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(white: 0.75))
                    .frame(width: 80, height: 4)
                    .rotationEffect(.degrees(58))
                    .offset(x: -14)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(white: 0.45))
                    .frame(width: 84, height: 9)
                    .rotationEffect(.degrees(-32))
                    .offset(y: 4)
                Circle()
                    .fill(.white)
                    .frame(width: 15, height: 15)
                    .overlay(Circle().fill(.black).frame(width: 9, height: 9))
                    .offset(x: 14, y: -12)
            }
        case .phone:
            ZStack {
                gradient(0.6, 0.35)
                Image(systemName: "phone.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white)
            }
        case .safari:
            ZStack {
                gradient(0.85, 0.6)
                Circle().fill(.white).padding(6)
                Image(systemName: "safari.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(Color(white: 0.25))
            }
        case .mail:
            ZStack {
                gradient(0.55, 0.3)
                Image(systemName: "envelope.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white)
            }
        case .facetime:
            ZStack {
                gradient(0.65, 0.4)
                Image(systemName: "video.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white)
            }
        case .play:
            ZStack {
                Color(white: 0.85)
                Image(systemName: "play.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.black)
            }
        }
    }
}

#Preview {
    FeedView()
}
#endif

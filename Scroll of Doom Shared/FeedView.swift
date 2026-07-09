#if os(iOS)
import SwiftUI

struct SaveSlot: Codable {
    var level = 0
    var powerups: Set<Powerup> = []
    // exact cube position and per level item state, nil means a fresh start
    var cubeX: Double?
    var cubeY: Double?
    var hasKey = false
    var gateOpen = false
    var pickupTaken = false
    var thumbnail: Data?
    var lastPlayed = Date()
}

// the captured render of the level, or a plain cube for saves not yet played
private struct SaveThumbnail: View {
    let slot: SaveSlot
    let isAd: Bool
    let isBoss: Bool
    let adPowerup: Powerup?

    var body: some View {
        if let data = slot.thumbnail, let ui = UIImage(data: data) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 2)
                .fill(.white)
                .frame(width: 13, height: 13)
        }
    }
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

    // 10 normal, boss, 10 normal, dash ad, then 10 normal, boss, 10 normal,
    // boss, 10 normal, wings ad
    private static let levelCount = 56
    private static let adLevels: [Int: Powerup] = [21: .dash, 54: .doubleJump]
    private static let bossLevels: Set<Int> = [10, 32, 43]

    @State private var scenes: [LevelScene]?
    @State private var currentLevel = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var heldDirection: CGFloat = 0
    @State private var openApp: String?
    @State private var showCreator = false
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
    @State private var runPowerups: Set<Powerup> = []
    @State private var jumpReady = true
    @State private var airJumpReady = false
    @State private var dashReady = true

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
                    } else if showCreator {
                        MyLevelsView(onExit: { showCreator = false })
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
            .animation(Self.screenSpring, value: showCreator)
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

                // active tab just brightens, no underline
                HStack(spacing: 26) {
                    Text("Posts")
                        .font(.subheadline).bold()
                        .foregroundStyle(.white)
                    Text("Collections")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Sounds")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Effects")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.top, 20)

                ScrollView {
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
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
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
            if let slot {
                // schematic of the actual level, cube where it was left
                SaveThumbnail(slot: slot,
                              isAd: Self.adLevels[slot.level] != nil,
                              isBoss: Self.bossLevels.contains(slot.level),
                              adPowerup: Self.adLevels[slot.level])
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
                    Text(LevelPageView.username(
                        displayLevel: Self.displayLevel(for: slot.level),
                        adPowerup: Self.adLevels[slot.level],
                        isBoss: Self.bossLevels.contains(slot.level)))
                        .font(.caption2).bold()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
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
        runPowerups = slot.powerups
        if slot.powerups.contains(.doubleJump) {
            for s in scenes { s.extraJumps = 1 }
        }
        if slot.powerups.contains(.dash) {
            for s in scenes { s.hasDash = true }
        }

        let hasPosition = slot.cubeX != nil && slot.cubeY != nil
        if hasPosition {
            // resume exactly where the save left off, item state and all
            scenes[level].restore(.init(x: slot.cubeX!, y: slot.cubeY!,
                                        hasKey: slot.hasKey, hatchOpen: slot.gateOpen,
                                        skipPickup: slot.pickupTaken))
        } else {
            scenes[level].prepareEntry(atXFraction: 0.5)
        }

        currentLevel = level
        scrollOffset = 0
        gateUnlocked = slot.gateOpen
        loading = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            choosingSlot = false
            showGame = true
        }
        if !hasPosition {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                scenes[level].beginEntry()
            }
        }
    }

    private func saveProgress() {
        guard let a = activeSlot, a < slots.count else { return }
        slots[a].level = currentLevel
        slots[a].powerups = runPowerups
        if let scene = scenes?[currentLevel] {
            let s = scene.snapshot()
            slots[a].cubeX = s.x
            slots[a].cubeY = s.y
            slots[a].hasKey = s.hasKey
            slots[a].gateOpen = s.hatchOpen
            slots[a].pickupTaken = s.skipPickup
            slots[a].thumbnail = scene.thumbnailImage()?.pngData()
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
        runPowerups = []
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
                    AppIcon(art: .play, label: "PLAY") { choosingSlot = true }
                    AppIcon(art: .messages, label: "Messages")
                    AppIcon(art: .camera, label: "Camera")
                    AppIcon(art: .photos, label: "Photos") { showCreator = true }
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

    // medium widget, 4x2, in a real liquid glass frame
    private var widget: some View {
        Image("widget")
            .resizable()
            .aspectRatio(2.13, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding(7)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
    }

    private var dock: some View {
        HStack(spacing: 26) {
            AppIcon(art: .phone)
            AppIcon(art: .safari)
            AppIcon(art: .mail)
            AppIcon(art: .facetime)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 92)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30))
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
            s.isAdLevel = Self.adLevels[i] != nil
            s.adPowerup = Self.adLevels[i] ?? .doubleJump
            s.isBossLevel = Self.bossLevels.contains(i)
            s.bottomInset = GameTabBar.height
            return s
        }
        for (i, scene) in built.enumerated() {
            scene.onFellThrough = { xFrac in advance(from: i, entryFrac: xFrac) }
            scene.onHatchOpened = { if currentLevel == i { gateUnlocked = true } }
            scene.onJumpStateChanged = { first, second in
                if currentLevel == i {
                    jumpReady = first
                    airJumpReady = second
                }
            }
            scene.onDashStateChanged = { ready in
                if currentLevel == i { dashReady = ready }
            }
            // powerups persist for the whole run
            scene.onCollectPowerup = { p in
                runPowerups.insert(p)
                switch p {
                case .doubleJump: for s in built { s.extraJumps = 1 }
                case .dash: for s in built { s.hasDash = true }
                }
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
                       dashEnabled: runPowerups.contains(.dash),
                       dashReady: dashReady,
                       wingsEnabled: runPowerups.contains(.doubleJump),
                       jumpReady: jumpReady,
                       airJumpReady: airJumpReady,
                       onMove: { dir in
                           heldDirection = dir
                           scenes[currentLevel].setMove(dir)
                       },
                       onJump: {
                           scenes[currentLevel].jump()
                       },
                       onDash: {
                           scenes[currentLevel].dash()
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
                                  adPowerup: Self.adLevels[index],
                                  isBoss: Self.bossLevels.contains(index),
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

    // ads and bosses dont count toward the shown level number
    private static func displayLevel(for index: Int) -> Int {
        if bossLevels.contains(index) { return bossNumber(for: index) }
        return index + 1
            - adLevels.keys.filter { $0 < index }.count
            - bossLevels.filter { $0 < index }.count
    }

    private static func bossNumber(for index: Int) -> Int {
        bossLevels.filter { $0 <= index }.count
    }

    private func advance(from index: Int, entryFrac: CGFloat) {
        guard let scenes, index + 1 < Self.levelCount else { return }
        scenes[index + 1].prepareEntry(atXFraction: entryFrac)
        scenes[index].setMove(0)
        gateUnlocked = false
        withAnimation(.easeInOut(duration: 0.45)) {
            scrollOffset = -screenSize.height
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.46) {
            currentLevel = index + 1
            scrollOffset = 0
            // hand the held direction over now, a release during the scroll
            // would otherwise be eaten by the old level
            scenes[index + 1].setMove(heldDirection)
            scenes[index + 1].beginEntry()
            saveProgress()
        }
    }
}

private struct AppIcon: View {
    enum Art: String {
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
                    // liquid glass sheen and rim
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .fill(LinearGradient(
                                colors: [.white.opacity(0.25), .white.opacity(0.05), .clear],
                                startPoint: .topLeading, endPoint: .bottom))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .strokeBorder(.white.opacity(0.25), lineWidth: 0.8)
                    )
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

    @ViewBuilder private var artwork: some View {
        switch art {
        case .calendar:
            // shows todays actual date like the real icon
            ZStack {
                Color.white
                VStack(spacing: -2) {
                    Text(Date().formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(white: 0.45))
                    Text(Date().formatted(.dateTime.day()))
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.black)
                }
            }
        case .play:
            Image(systemName: "play.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white)
                .frame(width: 62, height: 62)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 15))
        default:
            Image("icon.\(art.rawValue)")
                .resizable()
                .scaledToFill()
        }
    }
}

#Preview {
    FeedView()
}
#endif

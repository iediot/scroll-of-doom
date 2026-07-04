#if os(iOS)
import SwiftUI

struct FeedView: View {

    private static let levelCount = 15
    private static let adLevels: Set<Int> = [7]

    @State private var scenes: [LevelScene]?
    @State private var currentLevel: Int? = 0
    @State private var heldDirection: CGFloat = 0
    @State private var openApp: String?
    @State private var loading = false
    @State private var showGame = false
    @State private var screenSize: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // the game stays mounted invisibly behind the menu so spritekit
                // and metal warm up before play is ever pressed
                if let scenes {
                    feed(scenes)
                        .opacity(showGame ? 1 : 0)
                        .allowsHitTesting(showGame)
                }
                if !showGame {
                    if loading {
                        loadingScreen
                    } else if let openApp {
                        appScreen(openApp)
                    } else {
                        homeScreen(size: geo.size)
                    }
                }
            }
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

    private func beginLoading(size: CGSize) {
        if scenes != nil {
            enterGame()
        } else {
            // fallback if play lands before the preload finished
            loading = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                preload(size: size)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    enterGame()
                }
            }
        }
    }

    private func enterGame() {
        // the preloaded cube has been idling, drop it in fresh from the top
        scenes?.first?.enterFromTop(atXFraction: 0.5)
        currentLevel = 0
        loading = false
        showGame = true
    }

    private func exitGame() {
        showGame = false
        heldDirection = 0
        currentLevel = 0
        scenes = nil
        // rebuild fresh scenes warm behind the menu for the next run
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            preload(size: screenSize)
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
                    AppIcon(art: .play, label: "Scroll of Doom") { beginLoading(size: size) }
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
            return s
        }
        for (i, scene) in built.enumerated() {
            scene.onFellThrough = { xFrac in advance(from: i, entryFrac: xFrac) }
            // powerups persist for the whole run
            scene.onCollectWings = { for s in built { s.extraJumps = 1 } }
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
    }

    private func feedScroll(_ scenes: [LevelScene]) -> some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(0..<Self.levelCount, id: \.self) { index in
                    LevelPageView(levelIndex: index,
                                  displayLevel: Self.displayLevel(for: index),
                                  isAd: Self.adLevels.contains(index),
                                  scene: scenes[index],
                                  onMove: { dir in
                                      heldDirection = dir
                                      if let i = currentLevel { scenes[i].setMove(dir) }
                                  },
                                  onJump: {
                                      if let i = currentLevel { scenes[i].jump() }
                                  })
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentLevel)
        .scrollDisabled(true)
        .scrollIndicators(.hidden)
        .ignoresSafeArea()
    }

    // ads and future boss levels dont count toward the shown level number
    private static func displayLevel(for index: Int) -> Int {
        index + 1 - adLevels.filter { $0 < index }.count
    }

    private func advance(from index: Int, entryFrac: CGFloat) {
        guard let scenes, index + 1 < Self.levelCount else { return }
        scenes[index + 1].enterFromTop(atXFraction: entryFrac)
        scenes[index].setMove(0)
        scenes[index + 1].setMove(heldDirection)
        withAnimation(.easeInOut(duration: 0.45)) {
            currentLevel = index + 1
        }
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

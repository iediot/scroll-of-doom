#if os(iOS)
import SwiftUI

struct FeedView: View {

    private static let levelCount = 7

    // scenes stay nil until play is pressed, by then the real screen size is
    // known so every level is built at the right size from its first frame
    @State private var scenes: [LevelScene]?
    @State private var currentLevel: Int? = 0
    @State private var heldDirection: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            if let scenes {
                feed(scenes)
            } else {
                menu(size: geo.size)
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    private func menu(size: CGSize) -> some View {
        ZStack {
            Color.black
            Button {
                start(size: size)
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.white)
            }
        }
    }

    private func start(size: CGSize) {
        let built = (0..<Self.levelCount).map { i -> LevelScene in
            let s = LevelScene(size: size)
            s.levelIndex = i
            return s
        }
        for (i, scene) in built.enumerated() {
            scene.onFellThrough = { xFrac in advance(from: i, entryFrac: xFrac) }
        }
        scenes = built
    }

    private func feed(_ scenes: [LevelScene]) -> some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(0..<Self.levelCount, id: \.self) { index in
                    LevelPageView(levelIndex: index,
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

#Preview {
    FeedView()
}
#endif

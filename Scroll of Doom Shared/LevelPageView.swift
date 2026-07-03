#if os(iOS)
import SwiftUI
import SpriteKit

/// A single page in the feed — a full-screen playable level with TikTok-style
/// chrome: caption bottom-left, engagement rail on the right (raised toward
/// mid-screen), and triangle movement/jump controls along the bottom.
struct LevelPageView: View {
    let levelIndex: Int
    @Binding var scrollLocked: Bool

    /// The level's SpriteKit scene, kept stable across body re-evaluations.
    @State private var scene = LevelScene(size: CGSize(width: 400, height: 800))

    /// Number of controls currently held. Feed paging is locked while > 0.
    @State private var activeControls = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(red: 0.05, green: 0.06, blue: 0.12)
            SpriteView(scene: scene, options: [.ignoresSiblingOrder])
            engagementRail
            caption
            controls
        }
        .ignoresSafeArea()
    }

    // MARK: - Scroll lock (multi-touch safe)

    private func controlPressChanged(_ pressing: Bool) {
        activeControls = max(0, activeControls + (pressing ? 1 : -1))
        scrollLocked = activeControls > 0
    }

    // MARK: - Controls (triangles along the bottom)

    private var controls: some View {
        HStack(alignment: .bottom) {
            HStack(spacing: 18) {
                ControlTriangle(direction: .left) { pressing in
                    scene.setMove(pressing ? -1 : 0)
                    controlPressChanged(pressing)
                }
                ControlTriangle(direction: .right) { pressing in
                    scene.setMove(pressing ? 1 : 0)
                    controlPressChanged(pressing)
                }
            }
            Spacer()
            ControlTriangle(direction: .up) { pressing in
                if pressing { scene.jump() }
                controlPressChanged(pressing)
            }
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 88)   // raised, sits above the username
    }

    // MARK: - Caption (bottom-left)

    private var caption: some View {
        VStack {
            Spacer()
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("@level_\(levelIndex + 1)")
                        .font(.headline).bold()
                    Text("Level \(levelIndex + 1)")
                        .font(.subheadline)
                        .opacity(0.9)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 4)
                Spacer()
            }
            .padding(.leading, 16)
            .padding(.bottom, 26)    // below the arrows, at the very bottom
        }
    }

    // MARK: - Engagement rail (right side, raised like TikTok)

    private var engagementRail: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 22) {
                profileAvatar
                EngagementButton(icon: "heart.fill",   label: likeCount,    tint: .white)
                EngagementButton(icon: "bubble.right.fill", label: commentCount, tint: .white)
                EngagementButton(icon: "arrowshape.turn.up.right.fill", label: shareCount, tint: .white)
            }
            .padding(.trailing, 12)
            .padding(.bottom, 230)   // lifts rail clear of the controls
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var profileAvatar: some View {
        Circle()
            .fill(Color(red: 0.30, green: 0.32, blue: 0.42))
            .frame(width: 46, height: 46)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .overlay(Image(systemName: "square.fill").foregroundStyle(.white))
    }

    private var likeCount: String    { formatCount(1200 + levelIndex * 337) }
    private var commentCount: String { formatCount(84 + levelIndex * 53) }
    private var shareCount: String   { formatCount(12 + levelIndex * 9) }

    private func formatCount(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...:     return String(format: "%.1fK", Double(n) / 1_000)
        default:           return "\(n)"
        }
    }
}

// MARK: - Triangle control

/// A triangular button that reports press/release. The triangle itself is the
/// hit area (no surrounding circle), and its own gesture wins over the feed's
/// scroll so touches here drive the game rather than paging.
private struct ControlTriangle: View {
    enum Direction { case left, right, up }

    let direction: Direction
    let onPress: (Bool) -> Void

    @State private var pressed = false
    private let sideLength: CGFloat = 66

    private var rotation: Angle {
        switch direction {
        case .up:    return .degrees(0)
        case .left:  return .degrees(-90)
        case .right: return .degrees(90)
        }
    }

    var body: some View {
        let shape = TriangleShape().rotation(rotation)
        return shape
            .fill(.white.opacity(pressed ? 0.9 : 0.5))
            .frame(width: sideLength, height: sideLength)
            .shadow(color: .black.opacity(0.35), radius: 3)
            .contentShape(shape)   // hit area = the triangle only
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !pressed { pressed = true; onPress(true) }
                    }
                    .onEnded { _ in
                        pressed = false; onPress(false)
                    }
            )
    }
}

/// An upward-pointing triangle filling its rect; rotate for other directions.
private struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Engagement button

private struct EngagementButton: View {
    let icon: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .shadow(color: .black.opacity(0.4), radius: 2)
            if !label.isEmpty {
                Text(label)
                    .font(.footnote).bold()
                    .shadow(color: .black.opacity(0.4), radius: 2)
            }
        }
        .foregroundStyle(tint)
    }
}
#endif

#if os(iOS)
import SwiftUI
import SpriteKit

struct LevelPageView: View {
    let levelIndex: Int
    let scene: LevelScene
    // input goes through feedview so a held press carries across level transitions
    let onMove: (CGFloat) -> Void
    let onJump: () -> Void

    @State private var keyCollected = false

    private let gap: CGFloat = 28
    private let controlSide: CGFloat = 64
    private let usernameBottom: CGFloat = 30
    private let usernameHeight: CGFloat = 46

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
            SpriteView(scene: scene, options: [.ignoresSiblingOrder])
            engagementRail
            controls
            caption
        }
        .ignoresSafeArea()
        .onAppear {
            scene.onCollectHeart = { keyCollected = true }
        }
    }

    private var controls: some View {
        HStack(alignment: .bottom) {
            HStack(spacing: 18) {
                ControlTriangle(direction: .left, side: controlSide) { pressing in
                    onMove(pressing ? -1 : 0)
                }
                ControlTriangle(direction: .right, side: controlSide) { pressing in
                    onMove(pressing ? 1 : 0)
                }
            }
            Spacer()
            ControlTriangle(direction: .up, side: controlSide) { pressing in
                if pressing { onJump() }
            }
        }
        .padding(.horizontal, 26)
        .padding(.bottom, usernameBottom + usernameHeight + gap)
    }

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
            .padding(.leading, 30)
            .padding(.bottom, usernameBottom)
        }
    }

    private var engagementRail: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 22) {
                profileAvatar.padding(.bottom, 35)
                Text(likeCount).font(.footnote).bold()
                EngagementButton(icon: "bubble.right.fill", label: commentCount, tint: .white)
                EngagementButton(icon: "arrowshape.turn.up.right.fill", label: shareCount, tint: .white)
            }
            .padding(.trailing, 12)
            .padding(.bottom, 230)
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

    // collecting the key takes a like with it, kept under 1k so the -1 is visible
    private static let likeSeeds = [903, 617, 842, 476, 758]
    private var likeCount: String {
        let seed = Self.likeSeeds[levelIndex % Self.likeSeeds.count]
        return formatCount(seed - (keyCollected ? 1 : 0))
    }
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

private struct ControlTriangle: View {
    enum Direction { case left, right, up }

    let direction: Direction
    let side: CGFloat
    let onPress: (Bool) -> Void

    @State private var pressed = false

    private var rotation: Angle {
        switch direction {
        case .up:    return .degrees(0)
        case .left:  return .degrees(-90)
        case .right: return .degrees(90)
        }
    }

    var body: some View {
        RoundedTriangle(cornerRadius: 12)
            .fill(.white.opacity(pressed ? 0.75 : 1.0))
            .frame(width: side, height: side)
            .shadow(color: .black.opacity(0.35), radius: 3)
            .rotationEffect(rotation)
            .overlay(
                // uikit touches instead of swiftui gestures, swiftui is single-touch
                // and adds lag, raw touches make every button independent and instant
                TouchCatcher { down in
                    pressed = down
                    onPress(down)
                }
            )
    }
}

private struct TouchCatcher: UIViewRepresentable {
    let onPress: (Bool) -> Void

    func makeUIView(context: Context) -> TouchCatcherView {
        let v = TouchCatcherView()
        v.backgroundColor = .clear
        v.onPress = onPress
        return v
    }

    func updateUIView(_ uiView: TouchCatcherView, context: Context) {
        uiView.onPress = onPress
    }
}

private final class TouchCatcherView: UIView {
    var onPress: ((Bool) -> Void)?
    private var activeTouches = 0

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if activeTouches == 0 { onPress?(true) }
        activeTouches += touches.count
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        activeTouches = max(0, activeTouches - touches.count)
        if activeTouches == 0 { onPress?(false) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        activeTouches = max(0, activeTouches - touches.count)
        if activeTouches == 0 { onPress?(false) }
    }
}

private struct RoundedTriangle: Shape {
    var cornerRadius: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let w = min(rect.width, rect.height)
        let h = w * sqrt(3) / 2
        let top         = CGPoint(x: rect.midX,       y: rect.midY - h / 2)
        let bottomRight = CGPoint(x: rect.midX + w/2, y: rect.midY + h / 2)
        let bottomLeft  = CGPoint(x: rect.midX - w/2, y: rect.midY + h / 2)
        let pts = [top, bottomRight, bottomLeft]

        var path = Path()
        for i in 0..<3 {
            let curr = pts[i]
            let prev = pts[(i + 2) % 3]
            let next = pts[(i + 1) % 3]
            let toPrev = unit(from: curr, to: prev)
            let toNext = unit(from: curr, to: next)
            let start = CGPoint(x: curr.x + toPrev.x * cornerRadius, y: curr.y + toPrev.y * cornerRadius)
            let end   = CGPoint(x: curr.x + toNext.x * cornerRadius, y: curr.y + toNext.y * cornerRadius)
            if i == 0 { path.move(to: start) } else { path.addLine(to: start) }
            path.addQuadCurve(to: end, control: curr)
        }
        path.closeSubpath()
        return path
    }

    private func unit(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(hypot(dx, dy), 0.0001)
        return CGPoint(x: dx / len, y: dy / len)
    }
}

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

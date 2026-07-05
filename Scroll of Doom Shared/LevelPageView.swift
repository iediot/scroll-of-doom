#if os(iOS)
import SwiftUI
import SpriteKit

// home/search move, create is the gate, profile jumps
struct GameTabBar: View {
    static let height: CGFloat = 128

    let gateUnlocked: Bool
    let onMove: (CGFloat) -> Void
    let onJump: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.white.opacity(0.15))
                .frame(height: 0.5)
            HStack(spacing: 0) {
                barHoldItem(icon: "arrowtriangle.left.fill", direction: -1)
                barHoldItem(icon: "arrowtriangle.right.fill", direction: 1)
                columnDivider
                createGate
                columnDivider
                // future dash ability, grayed out for now
                barItem(icon: "chevron.right.2", tint: Color(white: 0.45))
                jumpItem
            }
            .frame(maxHeight: .infinity)
            .padding(.bottom, 8)
            .padding(.horizontal, 10)
        }
        .frame(height: Self.height)
        .background(Color.black)
    }

    private func barHoldItem(icon: String, direction: CGFloat) -> some View {
        barItem(icon: icon)
            .overlay(
                TouchCatcher { down in
                    onMove(down ? direction : 0)
                }
            )
    }

    private var jumpItem: some View {
        barItem(icon: "arrowtriangle.up.fill")
            .overlay(
                TouchCatcher { down in
                    if down { onJump() }
                }
            )
    }

    private var columnDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.15))
            .frame(width: 0.5)
    }

    private func barItem(icon: String, tint: Color = .white) -> some View {
        Image(systemName: icon)
            .font(.system(size: 28))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 62)
            .contentShape(Rectangle())
    }

    private var createGate: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(white: 0.55))
                .frame(width: 44, height: 31)
                .offset(x: -5)
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(white: 0.3))
                .frame(width: 44, height: 31)
                .offset(x: 5)
            RoundedRectangle(cornerRadius: 9)
                .fill(.white)
                .frame(width: 44, height: 31)
            // cross spins into the plus on unlock
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.black)
                .rotationEffect(.degrees(gateUnlocked ? 0 : 45))
                .animation(.spring(response: 0.35, dampingFraction: 0.55), value: gateUnlocked)
        }
        .frame(maxWidth: .infinity, minHeight: 62)
    }
}

struct LevelPageView: View {
    let levelIndex: Int
    // ads and future boss levels dont count toward the shown level number
    let displayLevel: Int
    let isAd: Bool
    let scene: LevelScene

    @State private var keyCollected = false
    @State private var heartFilled = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
            SpriteView(scene: scene, options: [.ignoresSiblingOrder])
            engagementRail
            caption
        }
        .ignoresSafeArea()
        .onAppear {
            scene.onCollectHeart = { keyCollected = true }
            scene.onHeartFilled = { heartFilled = true }
        }
    }

    private static let usernamePatterns = [
        "@user.level%d", "@lvl%d_real", "@its.level.%d", "@level%dofficial",
        "@justlevel%dthings", "@level%d_clips", "@level%d.fyp",
        "@level%dfanpage", "@lvl%d.official", "@level%d_leaks",
        "@level%dposting", "@lvl.%d.daily", "@level%d.core", "@levels.w.%d"
    ]

    private static let blurbPatterns = [
        "ts level pmo sm icl 🥀",
        "day 2 of posting my level until someone beats it",
        "no caption needed.",
        "We explored this abandoned level. What we found was unsettling.",
        "🧱",
        "BREAKING: local level declared structurally unsound, residents advised to jump.",
        "this one lowk goes hard ngl 🔥",
        "",
        "my honest reaction 💀",
        "POV: the gate wont open",
        "speedrun attempt, any% (gone wrong)",
        "how it feels to finally leave this place",
        "Level %d tour, part 3. The walls are still white.",
        "Season finale. Everything ends here."
    ]

    private var username: String {
        if isAd { return "@wingscorp.official" }
        let pattern = Self.usernamePatterns[(displayLevel - 1) % Self.usernamePatterns.count]
        return String(format: pattern, displayLevel)
    }

    private var blurb: String {
        if isAd { return "Wings™ — fly through levels. Get yours today 🪽" }
        let pattern = Self.blurbPatterns[(displayLevel - 1) % Self.blurbPatterns.count]
        return String(format: pattern, displayLevel)
    }

    private var caption: some View {
        VStack {
            Spacer()
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(username)
                        .font(.headline).bold()
                    if !blurb.isEmpty {
                        Text(blurb)
                            .font(.subheadline)
                            .opacity(0.9)
                    }
                    if isAd {
                        Text("Sponsored")
                            .font(.caption).bold()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.white.opacity(0.25), in: Capsule())
                    }
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 4)
                .frame(maxWidth: 265, alignment: .leading)
                Spacer()
            }
            .padding(.leading, 30)
            .padding(.bottom, GameTabBar.height + 30)
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
                EngagementButton(icon: "ellipsis", label: "", tint: .white)
            }
            .padding(.trailing, 12)
            .padding(.bottom, 193 + GameTabBar.height * 0.75)
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

    private static let likeSeeds = [903, 617, 842, 476, 758, 531, 689, 289,
                                    724, 448, 866, 592, 337, 781, 653]
    private var likeCount: String {
        let seed = Self.likeSeeds[levelIndex % Self.likeSeeds.count]
        return formatCount(seed - (keyCollected ? 1 : 0) + (heartFilled ? 1 : 0))
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

// raw uikit touches, swiftui gestures are single touch and laggy
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

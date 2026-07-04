#if os(iOS)
import SwiftUI
import SpriteKit

struct LevelPageView: View {
    let levelIndex: Int
    // ads and future boss levels dont count toward the shown level number
    let displayLevel: Int
    let isAd: Bool
    let scene: LevelScene
    // input goes through feedview so a held press carries across level transitions
    let onMove: (CGFloat) -> Void
    let onJump: () -> Void

    // total bar height including the home indicator strip, the scenes box
    // floor sits right on top of it so the floor gap lands on the create button
    static let barHeight: CGFloat = 112

    @State private var keyCollected = false
    @State private var heartFilled = false
    @State private var gateUnlocked = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
            SpriteView(scene: scene, options: [.ignoresSiblingOrder])
            engagementRail
            caption
            tabBar
        }
        .ignoresSafeArea()
        .onAppear {
            scene.onCollectHeart = { keyCollected = true }
            scene.onHeartFilled = { heartFilled = true }
            scene.onHatchOpened = { gateUnlocked = true }
        }
    }

    // tiktok tab bar, home and search are the move controls, create is the
    // gate lock and profile is the jump
    private var tabBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.white.opacity(0.15))
                .frame(height: 0.5)
            HStack(spacing: 0) {
                barHoldItem(icon: "arrowtriangle.left.fill", direction: -1)
                barHoldItem(icon: "arrowtriangle.right.fill", direction: 1)
                createGate
                barItem(icon: "message")
                jumpItem
            }
            .padding(.top, 14)
            .padding(.horizontal, 34)
            Spacer()
        }
        .frame(height: Self.barHeight)
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

    private func barItem(icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 31))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .contentShape(Rectangle())
    }

    private var createGate: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: 0.55))
                .frame(width: 50, height: 36)
                .offset(x: -6)
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: 0.3))
                .frame(width: 50, height: 36)
                .offset(x: 6)
            RoundedRectangle(cornerRadius: 10)
                .fill(.white)
                .frame(width: 50, height: 36)
            // locked shows a cross, unlocking spins it 45 degrees into the plus
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.black)
                .rotationEffect(.degrees(gateUnlocked ? 0 : 45))
                .animation(.spring(response: 0.35, dampingFraction: 0.55), value: gateUnlocked)
        }
        .frame(maxWidth: .infinity, minHeight: 54)
    }

    private static let usernamePatterns = [
        "@user.level%d", "@lvl%d_real", "@its.level.%d", "@level%dofficial",
        "@justlevel%dthings", "@level%d_clips", "@level%d.fyp",
        "@level%dfanpage", "@lvl%d.official", "@level%d_leaks",
        "@level%dposting", "@lvl.%d.daily", "@level%d.core", "@levels.w.%d"
    ]

    private static let blurbPatterns = [
        "ts level pmo sm icl 🌹",
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
                Spacer()
            }
            .padding(.leading, 30)
            .padding(.bottom, Self.barHeight + 30)
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
            .padding(.bottom, 193)
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

// uikit touches instead of swiftui gestures, swiftui is single-touch and adds
// lag, raw touches make every button independent and instant
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

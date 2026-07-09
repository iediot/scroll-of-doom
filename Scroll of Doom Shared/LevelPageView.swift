#if os(iOS)
import SwiftUI
import SpriteKit

// the app background, a very dark gray instead of pure black so surfaces read apart
extension Color { static let gameBG = Color(white: 0.10) }
extension UIColor { static let gameBG = UIColor(white: 0.10, alpha: 1) }

// home/search move, create is the gate, profile jumps
struct GameTabBar: View {
    static let height: CGFloat = 128

    let gateUnlocked: Bool
    let dashEnabled: Bool
    let dashReady: Bool
    let wingsEnabled: Bool
    let jumpReady: Bool
    let airJumpReady: Bool
    let onMove: (CGFloat) -> Void
    let onJump: () -> Void
    let onDash: () -> Void

    private static let dimmed = Color(white: 0.45)

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.white.opacity(0.15))
                .frame(height: 0.5)
            HStack(spacing: 0) {
                barHoldItem(rotation: .degrees(-90), direction: -1)
                barHoldItem(rotation: .degrees(90), direction: 1)
                createGate
                dashItem
                jumpItem
            }
            .frame(maxHeight: .infinity)
            .padding(.bottom, 8)
            .padding(.horizontal, 10)
        }
        .frame(height: Self.height)
        .background(Color.gameBG)
    }

    private func barHoldItem(rotation: Angle, direction: CGFloat) -> some View {
        PressableItem(onPress: { down in onMove(down ? direction : 0) }) {
            RoundedTriangle(cornerRadius: 6)
                .fill(.white)
                .frame(width: 30, height: 30)
                .rotationEffect(rotation)
        }
    }

    // fully grays while locked or recharging, back triangle sits rightmost
    private var dashItem: some View {
        let lit = dashEnabled && dashReady
        return PressableItem(onPress: { down in if down, dashEnabled { onDash() } }) {
            ZStack {
                RoundedTriangle(cornerRadius: 5)
                    .fill(lit ? Color.white : Self.dimmed)
                    .frame(width: 25, height: 25)
                    .rotationEffect(.degrees(90))
                    .offset(x: 7)
                RoundedTriangle(cornerRadius: 5)
                    .fill(Color.gameBG)
                    .frame(width: 25, height: 25)
                    .rotationEffect(.degrees(90))
                RoundedTriangle(cornerRadius: 5)
                    .fill(lit ? Color.white : Self.dimmed)
                    .frame(width: 25, height: 25)
                    .rotationEffect(.degrees(90))
                    .offset(x: -7)
            }
        }
    }

    // stacked triangles show jump charges, back one is the double jump
    private var jumpItem: some View {
        PressableItem(onPress: { down in if down { onJump() } }) {
            ZStack {
                RoundedTriangle(cornerRadius: 5)
                    .fill(wingsEnabled && airJumpReady ? Color.white : Self.dimmed)
                    .frame(width: 25, height: 25)
                    .offset(y: -7)
                RoundedTriangle(cornerRadius: 5)
                    .fill(Color.gameBG)
                    .frame(width: 25, height: 25)
                RoundedTriangle(cornerRadius: 5)
                    .fill(jumpReady ? Color.white : Self.dimmed)
                    .frame(width: 25, height: 25)
                    .offset(y: 7)
            }
        }
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
    // ads and bosses dont count toward the level number, bosses carry the
    // boss number here instead
    let displayLevel: Int
    let adPowerup: Powerup?
    let isBoss: Bool
    let scene: LevelScene

    private var isAd: Bool { adPowerup != nil }

    @State private var keyCollected = false
    @State private var heartFilled = false
    @State private var bossPromptShown = false
    @State private var bossSlotFilled = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.gameBG
            SpriteView(scene: scene, preferredFramesPerSecond: 120,
                       options: [.ignoresSiblingOrder])
            engagementRail
            caption
            if bossPromptShown {
                bossPrompt
                    .padding(.trailing, 58)
                    .padding(.bottom, 270)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .bottomTrailing)
                    .transition(.scale(scale: 0.3, anchor: .trailing)
                        .combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: bossPromptShown)
        .ignoresSafeArea()
        .onAppear {
            scene.onCollectHeart = { keyCollected = true }
            scene.onHeartFilled = { heartFilled = true }
            scene.onBossDelivered = {
                bossPromptShown = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    bossSlotFilled = true
                }
            }
        }
    }

    // the boss slot, pops out of the ellipsis like tiktoks menu
    private var bossPrompt: some View {
        HStack(spacing: 8) {
            Image(systemName: bossSlotFilled ? "heart.slash.fill" : "heart.slash")
                .font(.system(size: 16))
                .symbolEffect(.bounce, value: bossSlotFilled)
            Text("Not interested")
                .font(.footnote).bold()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.45), radius: 7, y: 3)
    }

    private static let usernamePatterns = [
        "@user.level%d", "@lvl%d_real", "@its.level.%d", "@level%dofficial",
        "@justlevel%dthings", "@level%d_clips", "@level%d.fyp",
        "@level%dfanpage", "@lvl%d.official", "@level%d_leaks",
        "@level%dposting", "@lvl.%d.daily", "@level%d.core", "@levels.w.%d",
        "@level%dcam", "@thelevel%darchive", "@level%d.diaries",
        "@level%dupdates", "@its.lvl%d.fr", "@level%d.mood",
        "@level%dgrind", "@lvl%d.haze", "@level%d.era", "@level%dcheck",
        "@lowkey.level%d", "@level%d.rizz", "@level%dslays", "@level%d_gaming",
        "@level%dcorner", "@level%d.pov", "@notlevel%d", "@level%d.irl",
        "@level%dtherapy", "@level%d.whisperss", "@level%dcontent",
        "@level%d.unfiltered", "@level%d_speedruns", "@level%dtok",
        "@level%d.aesthetic", "@level%dvibes", "@level%d.4k",
        "@certified.level%d", "@level%denjoyer", "@level%d.dump",
        "@level%dtutorials", "@level%d.soft", "@level%d_edits",
        "@level%dloreee", "@delulu.level%d", "@level%dfinale"
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
        "posting this before the level gets taken down",
        "not me getting stuck here for an hour 😭",
        "the level economy is crazy rn",
        "grwm to beat this level 🎀",
        "Day 40. Still here. Nothing has changed.",
        "Level %d exists. Thats it. Thats the post.",
        "am i delulu for thinking i can beat this first try",
        "caught in 4k falling through the gate 📸",
        "First time posting here. Be nice.",
        "entering my level %d era ✨",
        "There is something peaceful about a room with one exit.",
        "no because why is this level actually hard",
        "Filmed this on my lunch break. Enjoy.",
        "rating this level a solid 6-7",
        "Does anyone know who built these rooms? Asking seriously.",
        "Fun fact: the gate only opens for a full heart.",
        "My grandson showed me how to post this. What a lovely little room.",
        "me vs the level (the level is winning)",
        "The lighting in here is actually insane.",
        "canon event, do not interfere 🕯️",
        "the way i gasped when the gate opened",
        "level said youre not leaving and meant it",
        "A quiet place. I come here to think.",
        "not the heart spawning all the way down there 💀",
        "bet you cant beat this without the wings",
        "I measured the jump. Its exactly one cube too far.",
        "sound on for this one 🔇",
        "someone said this level is mid. couldnt be me.",
        "replaying this instead of going to therapy",
        "the fall is lowkey therapeutic",
        "Documenting every level until they shut this app down.",
        "W level or L level? comments below 👇",
        "slight inconvenience and i WILL restart",
        "That jump was personal.",
        "lore drop: the cube has always been here",
        "if you see this youre legally required to finish the level",
        "Season finale. Everything ends here."
    ]

    static func username(displayLevel: Int, adPowerup: Powerup?, isBoss: Bool) -> String {
        switch adPowerup {
        case .doubleJump: return "@wingscorp.official"
        case .dash: return "@dashlabs.official"
        case nil: break
        }
        if isBoss { return "@boss\(displayLevel)" }
        let pattern = usernamePatterns[(displayLevel - 1) % usernamePatterns.count]
        return String(format: pattern, displayLevel)
    }

    private var username: String {
        Self.username(displayLevel: displayLevel, adPowerup: adPowerup, isBoss: isBoss)
    }

    private var blurb: String {
        switch adPowerup {
        case .doubleJump: return "Wings™ — fly through levels. Get yours today 🪽"
        case .dash: return "Dash™ — get there faster. Try it now 💨"
        case nil: break
        }
        if isBoss { return "you werent supposed to scroll this far." }
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
                                    724, 448, 866, 592, 337, 781, 653, 415,
                                    508, 772, 264, 691, 843, 379]
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

// squeezes while held for press feedback
private struct PressableItem<Content: View>: View {
    let onPress: (Bool) -> Void
    @ViewBuilder let content: Content

    @State private var pressed = false

    var body: some View {
        content
            .scaleEffect(pressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: pressed)
            .frame(maxWidth: .infinity, minHeight: 62)
            .contentShape(Rectangle())
            .overlay(
                TouchCatcher { down in
                    pressed = down
                    onPress(down)
                }
            )
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

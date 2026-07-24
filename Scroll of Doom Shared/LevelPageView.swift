#if os(iOS)
import SwiftUI
import SpriteKit
import Combine
import UIKit

// a uikit blur whose strength can be dialed down well below a full material, so it
// reads as a light blur rather than a frosted wall
struct LightBlur: UIViewRepresentable {
    var intensity: CGFloat = 0.18   // 0 none, 1 full material

    func makeUIView(context: Context) -> UIVisualEffectView {
        let v = UIVisualEffectView(effect: nil)
        context.coordinator.view = v
        return v
    }
    func updateUIView(_ v: UIVisualEffectView, context: Context) {
        context.coordinator.set(intensity)
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        weak var view: UIVisualEffectView?
        private var animator: UIViewPropertyAnimator?
        func set(_ x: CGFloat) {
            animator?.stopAnimation(true)
            guard let view else { return }
            let a = UIViewPropertyAnimator(duration: 1, curve: .linear) { [weak view] in
                view?.effect = UIBlurEffect(style: .systemThinMaterialDark)
            }
            a.pausesOnCompletion = true
            a.fractionComplete = min(max(x, 0.001), 0.999)
            animator = a
        }
    }
}

extension View {
    // a faint black blur hugging the title so it reads over the header blur and content
    func wordBlur() -> some View {
        self.padding(.horizontal, 12).padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 20).fill(.black.opacity(0.22)).blur(radius: 12)
            }
    }
}

// a gentle top down progressive blur, several light bands each reaching lower and
// fading out, so its blurriest at the top and eases to nothing at the bottom
struct ProgressiveHeaderBlur: View {
    var layers = 2   // fewer live blur views so transitions stay smooth
    var perLayer: CGFloat = 0.16
    var body: some View {
        ZStack {
            ForEach(0..<layers, id: \.self) { i in
                let end = CGFloat(i + 1) / CGFloat(layers)
                // longer overlapping fades so neighbouring bands blend, keeping the
                // blur close between adjacent steps instead of jumping
                let hold = max(0, end - 2.0 / CGFloat(layers))
                LightBlur(intensity: perLayer)
                    .mask(LinearGradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: hold),
                        .init(color: .clear, location: end)
                    ], startPoint: .top, endPoint: .bottom))
            }
        }
    }
}

// the app background, a very dark gray instead of pure black so surfaces read apart
extension Color { static let gameBG = Color(white: 0.10) }
extension UIColor { static let gameBG = UIColor(white: 0.10, alpha: 1) }

// flip to true to show the on screen fps / node / draw overlay while debugging,
// the overlay itself costs a few fps so keep it off normally
enum PerfHUD { static let on = false }

// MARK: - Settings

// performance and quality options, persisted and read by the scene and sprite view
final class GameSettings: ObservableObject {
    static let shared = GameSettings()
    private let d = UserDefaults.standard

    @Published var framerate: Int { didSet { d.set(framerate, forKey: "set.framerate") } }
    @Published var graphics: Int  { didSet { d.set(graphics, forKey: "set.graphics") } }   // 0 low, 1 med, 2 high
    @Published var particles: Int { didSet { d.set(particles, forKey: "set.particles") } }  // 0 off, 1 low, 2 med, 3 high

    // only clean divisors of a 120hz display, 90 stutters and 30 is too choppy to use
    static let frameRates = [60, 120]

    private init() {
        d.register(defaults: ["set.framerate": 120, "set.graphics": 2, "set.particles": 3])
        framerate = d.integer(forKey: "set.framerate")
        graphics = d.integer(forKey: "set.graphics")
        particles = d.integer(forKey: "set.particles")
        // drop any stale, non divisor value like the old 90 option
        if !Self.frameRates.contains(framerate) { framerate = 120 }
    }

    // fraction of the native resolution to render at, low is noticeably softer
    var renderScale: CGFloat { [0.5, 0.7, 1.0][min(max(graphics, 0), 2)] }
    // scales every particle burst, off drops them entirely
    var particleFactor: CGFloat { [0, 0.3, 0.65, 1.0][min(max(particles, 0), 3)] }
    // heavy extras (wallpaper, soft shadows) only on high
    var richVisuals: Bool { graphics >= 2 }
}

// an skview that keeps its reduced drawable resolution and frame rate cap, skview
// resets both on layout so we reapply them there
final class ScaledSKView: SKView {
    var renderScale: CGFloat = 1
    var targetFPS: Int = 120
    override func layoutSubviews() {
        super.layoutSubviews()
        if preferredFramesPerSecond != targetFPS { preferredFramesPerSecond = targetFPS }
        let native = window?.screen.nativeScale ?? UIScreen.main.scale
        let target = max(1, native * renderScale)
        if abs(contentScaleFactor - target) > 0.01 {
            contentScaleFactor = target
            layer.contentsScale = target
        }
    }
}

// wraps the skview so we can drop the render resolution and set the framerate live
struct GameSpriteView: UIViewRepresentable {
    let scene: SKScene
    var renderScale: CGFloat = 1
    var framerate: Int = 120
    var paused: Bool = false   // stop rendering entirely, eg while hidden behind a menu

    func makeUIView(context: Context) -> ScaledSKView {
        let v = ScaledSKView()
        v.ignoresSiblingOrder = true
        v.renderScale = renderScale
        v.targetFPS = framerate
        v.presentScene(scene)
        apply(v)
        return v
    }

    func updateUIView(_ v: ScaledSKView, context: Context) {
        if v.scene !== scene { v.presentScene(scene) }
        if v.renderScale != renderScale || v.targetFPS != framerate {
            v.renderScale = renderScale
            v.targetFPS = framerate
            v.setNeedsLayout()   // reapply the drawable scale and fps cap
        }
        apply(v)
    }

    private func apply(_ v: ScaledSKView) {
        v.preferredFramesPerSecond = framerate
        v.isPaused = paused
        v.showsFPS = PerfHUD.on
        v.showsNodeCount = PerfHUD.on
        v.showsDrawCount = PerfHUD.on
    }
}

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
    var onJumpHold: (Bool) -> Void = { _ in }
    var jetpackEnabled: Bool = false
    var jetpackFuel: CGFloat = 1
    @Binding var showInventory: Bool

    private static let dimmed = Color(white: 0.45)

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.white.opacity(0.15))
                .frame(height: 0.5)
            HStack(spacing: 0) {
                barHoldItem(rotation: .degrees(-90), direction: -1)
                barHoldItem(rotation: .degrees(90), direction: 1)
                inventoryButton
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
        PressableItem(onPress: { down in if down { onJump() }; onJumpHold(down) }) {
            ZStack {
                // jetpack fuel gauge behind the arrows, the fill drops revealing a
                // darker track as fuel is spent, like the volume slider
                if jetpackEnabled {
                    ZStack(alignment: .bottom) {
                        Rectangle().fill(Color(white: 0.18))
                        Rectangle().fill(Color(white: 0.32))
                            .frame(height: 44 * max(0, min(1, jetpackFuel)))
                    }
                    .frame(width: 40, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .animation(.linear(duration: 0.08), value: jetpackFuel)
                }
                // back arrow with the notch carved out of it, showing the gauge or
                // background through the gap
                ZStack {
                    RoundedTriangle(cornerRadius: 5)
                        .fill(wingsEnabled && airJumpReady ? Color.white : Self.dimmed)
                        .frame(width: 25, height: 25)
                        .offset(y: -7)
                    RoundedTriangle(cornerRadius: 5)
                        .fill(.black)
                        .frame(width: 25, height: 25)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                // front arrow renders fully on top
                RoundedTriangle(cornerRadius: 5)
                    .fill(jumpReady ? Color.white : Self.dimmed)
                    .frame(width: 25, height: 25)
                    .offset(y: 7)
            }
        }
    }


    // opens the inventory that slides up from below
    private var inventoryButton: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                showInventory.toggle()
            }
        } label: {
            Image(systemName: "backpack.fill")
                .font(.system(size: 27, weight: .medium))
                .foregroundStyle(showInventory ? .white : Color(white: 0.72))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 62)
    }
}

// every inventory item maps to the powerups it grants, a combined item counts as both
enum InventoryItem {
    static func powers(_ id: String) -> Set<Powerup> {
        switch id {
        case "cube.wings": return [.doubleJump]
        case "cube.jetpack": return [.jetpack]
        case "item.dashBoots": return [.dash]
        case "item.spikeBoots": return [.spikeBoots]
        case "item.bothBoots": return [.dash, .spikeBoots]
        case "cube.jetpack.wings": return [.doubleJump, .jetpack]
        default: return []
        }
    }
    // the owned items, a pair only collapses into its combined item once it has been merged
    static func owned(from s: Set<Powerup>, merged: Set<String>) -> [String] {
        let wings = s.contains(.doubleJump), jet = s.contains(.jetpack)
        let dash = s.contains(.dash), spike = s.contains(.spikeBoots)
        var out: [String] = []
        if wings && jet && merged.contains("pack") { out.append("cube.jetpack.wings") }
        else { if wings { out.append("cube.wings") }; if jet { out.append("cube.jetpack") } }
        if dash && spike && merged.contains("boots") { out.append("item.bothBoots") }
        else { if dash { out.append("item.dashBoots") }; if spike { out.append("item.spikeBoots") } }
        return out
    }
    static func powers(of slots: [String?]) -> Set<Powerup> {
        slots.compactMap { $0 }.reduce(into: Set<Powerup>()) { $0.formUnion(powers($1)) }
    }
    // the merge id for two items that can combine, else nil
    static func mergePair(_ a: String, _ b: String) -> String? {
        let pair: Set<String> = [a, b]
        if pair == ["item.dashBoots", "item.spikeBoots"] { return "boots" }
        if pair == ["cube.wings", "cube.jetpack"] { return "pack" }
        return nil
    }
    // the single item a merged pair becomes
    static func mergedItem(_ pair: String) -> String {
        pair == "boots" ? "item.bothBoots" : "cube.jetpack.wings"
    }
}

// the cube built from stacked layers so equipping an item only adds or swaps a layer,
// the base body never redraws and the frame stays a fixed size so nothing around it shifts
struct PlayerSpriteView: View {
    var equipped: Set<Powerup>
    var height: CGFloat = 120

    var body: some View {
        let bodyW = height / 1.369
        let bodyH = bodyW * 600 / 512
        let wingW = bodyW * 1.5, wingH = wingW * 600 / 700
        let wingLift = bodyH * 0.62 - wingH / 2        // raise the pack to sit on the back
        let wings = equipped.contains(.doubleJump)
        let jet = equipped.contains(.jetpack)
        let combined = wings && jet
        let dash = equipped.contains(.dash), spike = equipped.contains(.spikeBoots)

        return ZStack(alignment: .bottom) {
            if wings {
                layer(combined ? "cube.wing.jetpack.left" : "cube.wing.left", wingW, wingH).offset(y: -wingLift)
                layer(combined ? "cube.wing.jetpack.right" : "cube.wing.right", wingW, wingH).offset(y: -wingLift)
            }
            if jet { layer(combined ? "cube.jetpack.wings" : "cube.jetpack", wingW, wingH).offset(y: -wingLift) }
            layer("cube.sitting", bodyW, bodyH)
            if dash || spike {
                layer((dash && spike) ? "cube.boots.both" : spike ? "cube.boots.spike" : "cube.boots.dash", bodyW, bodyH)
            }
            layer("cube.eyes", bodyW, bodyH)
            layer("cube.mouth.neutral", bodyW, bodyH)
        }
        .frame(width: wingW, height: height, alignment: .bottom)
    }

    private func layer(_ name: String, _ w: CGFloat, _ h: CGFloat) -> some View {
        Image(name).resizable().scaledToFit().frame(width: w, height: h)
    }
}

private struct SlotFrameKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, b in b }
    }
}
private struct PoolFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let n = nextValue(); if n != .zero { value = n }
    }
}
private struct ItemFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, b in b }
    }
}

// the pop up inventory, spans the screen and rises from the control bar. items drag
// into the slots to equip, back out to remove, and onto a partner to merge for coins.
// locked slots unlock for coins on tap.
struct InventoryPanel: View {
    static let height: CGFloat = 300
    private static let space = "inventory"
    var owned: Set<Powerup> = []
    @Binding var slots: [String?]
    var free: Bool = false      // the editor unlocks and merges without spending

    @State private var dragItem: String?
    @State private var dragPos: CGPoint = .zero
    @State private var hoverMerge: String?
    @State private var slotFrames: [Int: CGRect] = [:]
    @State private var itemFrames: [String: CGRect] = [:]
    @State private var poolFrame: CGRect = .zero
    @State private var unlocked = 1
    @State private var merged: Set<String> = []
    @State private var coins = 0

    private var equipped: Set<Powerup> { InventoryItem.powers(of: slots) }
    private var pool: [String] { InventoryItem.owned(from: owned, merged: merged).filter { !slots.contains($0) } }
    private var mergeCost: Int { free ? 0 : 200 + 100 * merged.count }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "backpack.fill")
                    .font(.system(size: 18, weight: .semibold))
                Text("Inventory")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                HStack(spacing: 6) {
                    Image(uiImage: GameArt.coinStillImage())
                        .resizable().scaledToFit()
                        .frame(width: 22, height: 22)
                    Text("\(coins)")
                        .font(.system(size: 18, weight: .bold))
                }
            }
            .foregroundStyle(.white)

            // two square slots hugging a big centered render of the equipped model
            HStack(spacing: 20) {
                slotView(0)
                PlayerSpriteView(equipped: equipped)
                slotView(1)
            }

            // the pool of owned items
            HStack(spacing: 12) {
                ForEach(pool, id: \.self) { poolTile($0) }
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(GeometryReader { g in
                Color.clear.preference(key: PoolFrameKey.self,
                                       value: g.frame(in: .named(Self.space)))
            })
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 26)
        .padding(.top, 16)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.15))
        .clipShape(.rect(topLeadingRadius: 22, topTrailingRadius: 22))
        .coordinateSpace(name: Self.space)
        .onAppear {
            unlocked = free ? slots.count : Loadout.unlockedSlots
            merged = Loadout.mergedPairs
            coins = CoinBank.balance
        }
        .onPreferenceChange(SlotFrameKey.self) { slotFrames = $0 }
        .onPreferenceChange(PoolFrameKey.self) { poolFrame = $0 }
        .onPreferenceChange(ItemFrameKey.self) { itemFrames = $0 }
        // the mergeable marker sits below and between each pair that can still merge
        .overlay {
            ForEach(mergeMarks, id: \.0) { mark in
                if let fa = itemFrames[mark.1], let fb = itemFrames[mark.2] {
                    Image("icon.mergeable").resizable().scaledToFit()
                        .frame(width: 84, height: 42)
                        .position(x: (fa.midX + fb.midX) / 2, y: fa.maxY + 22)
                        .allowsHitTesting(false)
                }
            }
        }
        // the item follows the finger while dragging
        .overlay {
            if let dragItem {
                Image(dragItem).resizable().scaledToFit()
                    .frame(width: 54, height: 54)
                    .position(dragPos)
                    .allowsHitTesting(false)
            }
        }
    }

    // adjacent owned pairs that can still be merged and afforded, id is the pair name
    private var mergeMarks: [(String, String, String)] {
        guard coins >= mergeCost else { return [] }
        var out: [(String, String, String)] = []
        for i in pool.indices where i + 1 < pool.count {
            if let pair = InventoryItem.mergePair(pool[i], pool[i + 1]), !merged.contains(pair) {
                out.append((pair, pool[i], pool[i + 1]))
            }
        }
        return out
    }

    // the price tag shown on a valid merge partner while dragging over it
    private var mergeBadge: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(.white, lineWidth: 2)
            .overlay(alignment: .top) {
                HStack(spacing: 3) {
                    Image(uiImage: GameArt.coinStillImage()).resizable().scaledToFit()
                        .frame(width: 13, height: 13)
                    Text("\(mergeCost)").font(.system(size: 12, weight: .bold))
                }
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(.black))
                .foregroundStyle(.white)
                .offset(y: -12)
            }
    }

    private func dragGesture(_ id: String) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .onChanged { v in
                dragItem = id
                dragPos = v.location
                hoverMerge = mergeTarget(for: id, at: v.location)
            }
            .onEnded { v in
                drop(id, at: v.location)
                dragItem = nil
                hoverMerge = nil
            }
    }

    // another owned item under the point that this one can still merge with
    private func mergeTarget(for id: String, at p: CGPoint) -> String? {
        for (other, f) in itemFrames where other != id && f.contains(p) {
            if let pair = InventoryItem.mergePair(id, other), !merged.contains(pair) { return other }
        }
        return nil
    }

    private func drop(_ id: String, at p: CGPoint) {
        for i in slots.indices where i < unlocked {
            if let f = slotFrames[i], f.contains(p) { equip(id, into: i); return }
        }
        if let other = mergeTarget(for: id, at: p),
           let pair = InventoryItem.mergePair(id, other) { tryMerge(pair, id, other); return }
        if poolFrame.contains(p) { unequip(id) }
    }

    private func equip(_ id: String, into i: Int) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if let j = slots.firstIndex(of: id) { slots[j] = nil }
            if i < slots.count { slots[i] = id }
        }
    }
    private func unequip(_ id: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if let j = slots.firstIndex(of: id) { slots[j] = nil }
        }
    }

    private func tryMerge(_ pair: String, _ a: String, _ b: String) {
        guard !merged.contains(pair), coins >= mergeCost else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if !free {
                CoinBank.balance -= mergeCost
                Loadout.mergedPairs.insert(pair)
                coins = CoinBank.balance
            }
            merged.insert(pair)
            for i in slots.indices where slots[i] == a || slots[i] == b { slots[i] = nil }
        }
    }

    private func unlockSlot() {
        guard unlocked < slots.count, free || coins >= 100 else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if !free {
                CoinBank.balance -= 100
                Loadout.unlockedSlots = unlocked + 1
                coins = CoinBank.balance
            }
            unlocked += 1
        }
    }

    private func poolTile(_ id: String) -> some View {
        itemTile(id)
            .opacity(dragItem == id ? 0.3 : 1)
            .overlay { if hoverMerge == id { mergeBadge } }
            .background(GeometryReader { g in
                Color.clear.preference(key: ItemFrameKey.self,
                                       value: [id: g.frame(in: .named(Self.space))])
            })
            .highPriorityGesture(dragGesture(id))
    }

    private func itemTile(_ name: String) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(white: 0.10))
            .frame(width: 54, height: 54)
            .overlay(Image(name).resizable().scaledToFit().padding(8))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(white: 0.28), lineWidth: 1.5))
    }

    private func slotView(_ i: Int) -> some View {
        let isUnlocked = i < unlocked
        let id = i < slots.count ? slots[i] : nil
        return RoundedRectangle(cornerRadius: 14)
            .fill(Color(white: 0.10))
            .frame(width: 62, height: 62)
            .overlay {
                if let id {
                    Image(id).resizable().scaledToFit().padding(8)
                        .opacity(dragItem == id ? 0.3 : 1)
                        .highPriorityGesture(dragGesture(id))
                } else if isUnlocked {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color(white: 0.35), lineWidth: 2)
                } else {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color(white: 0.2), style: StrokeStyle(lineWidth: 2, dash: [5]))
                        .overlay {
                            VStack(spacing: 3) {
                                Image(systemName: "lock.fill").font(.system(size: 16, weight: .semibold))
                                HStack(spacing: 2) {
                                    Image(uiImage: GameArt.coinStillImage()).resizable().scaledToFit()
                                        .frame(width: 12, height: 12)
                                    Text("100").font(.system(size: 12, weight: .bold))
                                }
                            }
                            .foregroundStyle(Color(white: 0.4))
                        }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if !isUnlocked { unlockSlot() } }
            .background(GeometryReader { g in
                Color.clear.preference(key: SlotFrameKey.self,
                                       value: [i: g.frame(in: .named(Self.space))])
            })
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
    var paused: Bool = false

    private var isAd: Bool { adPowerup != nil }

    @State private var keyCollected = false
    @State private var heartFilled = false
    @State private var bossPromptShown = false
    @State private var bossSlotFilled = false
    @ObservedObject private var settings = GameSettings.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.gameBG
            GameSpriteView(scene: scene, renderScale: settings.renderScale,
                           framerate: settings.framerate, paused: paused)
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
        case .jetpack: return "@jetlife.official"
        case .spikeBoots: return "@gripwear.official"
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
        case .jetpack: return "JetLife™ — take to the skies. Fuel sold separately 🔥"
        case .spikeBoots: return "GripWear™ — stick to any wall. Kick off in style 👟"
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

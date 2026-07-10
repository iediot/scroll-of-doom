import SpriteKit
import UIKit

// a designed level, positions are fractions of the screen so they carry across
// devices, y is from the bottom like spritekit
struct PlatformData: Codable, Identifiable, Equatable {
    var id = UUID()
    var x: Double        // center, fraction of width
    var y: Double        // fraction of height from the bottom
    var w: Double        // length, fraction of screen width
    var vertical: Bool?  // optional so old saves still decode
    var ox: Double?      // pixel offset within the grid cell, right
    var oy: Double?      // pixel offset within the grid cell, up
    var isVertical: Bool { vertical == true }
    var offX: Double { ox ?? 0 }
    var offY: Double { oy ?? 0 }
}

struct LevelData: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String = "untitled"
    var platforms: [PlatformData] = []
    var heartX: Double = 0.5
    var heartY: Double = 0.24
    var powerups: Set<Powerup> = []   // powerups granted to the player in this level
}

enum CustomLevelStore {
    private static let key = "customLevels"

    static func load() -> [LevelData] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let levels = try? JSONDecoder().decode([LevelData].self, from: data)
        else { return [] }
        return levels
    }

    static func save(_ levels: [LevelData]) {
        if let data = try? JSONEncoder().encode(levels) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func encode(_ level: LevelData) -> String {
        (try? JSONEncoder().encode(level))?.base64EncodedString() ?? ""
    }

    static func decode(_ code: String) -> LevelData? {
        guard let data = Data(base64Encoded: code.trimmingCharacters(in: .whitespacesAndNewlines)),
              var level = try? JSONDecoder().decode(LevelData.self, from: data) else { return nil }
        level.id = UUID()
        return level
    }
}

final class LevelScene: SKScene {

    private let moveSpeed: CGFloat = 260
    private let jumpSpeed: CGFloat = 715
    private let gravityY: CGFloat = -26
    // coyote time and jump buffering
    private let coyoteTime: TimeInterval = 0.08
    private let jumpBufferTime: TimeInterval = 0.12
    private let edgeInset: CGFloat = 4
    // matches the create button column in the tab bar

    private enum Cat {
        static let player:   UInt32 = 0x1 << 0
        static let ground:   UInt32 = 0x1 << 1
        static let heart:    UInt32 = 0x1 << 2
        static let wings:    UInt32 = 0x1 << 3
        static let platform: UInt32 = 0x1 << 4   // custom platforms and walls, phased through on entry
    }

    var levelIndex = 0
    var isAdLevel = false
    var isBossLevel = false
    // when set the scene renders this designed layout instead of the built in one
    var customLevel: LevelData?
    var adPowerup: Powerup = .doubleJump
    var extraJumps = 0 { didSet { updateWings() } }
    var hasDash = false { didSet { updateShoes() } }
    // box floor sits on top of the tab bar
    var bottomInset: CGFloat = 0
    var onFellThrough: ((CGFloat) -> Void)?
    var onCollectHeart: (() -> Void)?
    var onHeartFilled: (() -> Void)?
    var onCollectPowerup: ((Powerup) -> Void)?
    var onHatchOpened: (() -> Void)?
    var onBossDelivered: (() -> Void)?
    var onJumpStateChanged: ((Bool, Bool) -> Void)?
    var onDashStateChanged: ((Bool) -> Void)?

    private let modelSize: CGFloat = 30
    // small fixed hitbox, centered horizontally and sitting at the models feet
    private let hitW: CGFloat = 18
    private let hitH: CGFloat = 22
    // stacked sprite layers, drawn bigger than the hitbox
    private let spriteW: CGFloat = 40
    private var spriteH: CGFloat { spriteW * 600 / 512 }
    private let heartSize: CGFloat = 38   // the pickup heart, held one is a touch smaller
    // platforms and walls, a grayer bar with a black rim a third of its width each side
    private let barWidth: CGFloat = 3
    private let barColor = UIColor(white: 0.8, alpha: 1)
    private var barOutline: CGFloat { barWidth + 2 * barWidth / 3 }

    private var player: SKNode!
    private var squishBottom: SKNode!   // squishes scale from the cubes feet, purely visual
    private var walkNode: SKNode!       // inner node for the continuous walk bob
    private var walking = false
    private var bodySprite: SKSpriteNode!   // sitting or holding stance, no face
    private var eyesSprite: SKSpriteNode!   // eyes with baked in glare
    private var mouthSprite: SKSpriteNode!  // swaps between open, neutral, happy
    private var heldHeart: SKSpriteNode!    // shown above the head while carrying the key
    private var shoesSprite: SKSpriteNode!  // shown at the feet once dash is unlocked
    private var wingsSprite: SKSpriteNode!  // drawn behind the body with double jump
    private var wasGrounded = true
    private var descentSpeed: CGFloat = 0
    private var prevVelY: CGFloat = 0
    private var border: SKShapeNode?
    private var heart: SKNode?
    private var heartSlot: SKNode?
    private var wings: SKNode?
    private var hatchNode: SKNode?
    private var platformsNode: SKNode?
    private var hatchCenter: CGPoint = .zero
    private var hasKey = false
    private var hatchUnlocked = false

    private var boxBottomY: CGFloat = 0
    private var boxTopY: CGFloat = 0
    private var boxMidX: CGFloat = 0
    private var cornerR: CGFloat = 0

    private let dashSpeed: CGFloat = 480
    private let dashDuration: TimeInterval = 0.16
    private let dashCooldown: TimeInterval = 0.45
    private var dashEndTime: TimeInterval = -1
    private var dashReadyTime: TimeInterval = -1
    private var dashDirection: CGFloat = 1
    private var lastFacing: CGFloat = 1
    struct RestoreState {
        let x: Double
        let y: Double
        let hasKey: Bool
        let hatchOpen: Bool
        let skipPickup: Bool
    }

    private var pendingRestore: RestoreState?
    private var bossDelivered = false
    private var lastJumpState = (first: true, second: false)
    private var lastDashReady = true
    private var moveDirection: CGFloat = 0
    private var lastGroundedTime: TimeInterval = -1
    private var jumpRequestedTime: TimeInterval = -1
    private var sceneTime: TimeInterval = 0
    private var lastTime: TimeInterval = 0
    private var airJumpsUsed = 0
    private var hasFallenThrough = false
    private var entryPhasing = false   // dropping in, passing through platforms until the floor
    private var pendingEntryFrac: CGFloat?
    private var lastLayoutSize: CGSize = .zero

    // real display corner radius with fallback
    private var displayCornerRadius: CGFloat {
        if let screen = view?.window?.windowScene?.screen,
           let r = screen.value(forKey: "_displayCornerRadius") as? CGFloat, r > 0 {
            return r
        }
        return 47
    }

    override func didMove(to view: SKView) {
        scaleMode = .resizeFill
        backgroundColor = .gameBG
        physicsWorld.gravity = CGVector(dx: 0, dy: gravityY)
        physicsWorld.contactDelegate = self
        // representing must not rebuild and reset a level in progress
        if player == nil { buildLevel() } else { relayout() }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard player != nil else { return }
        relayout()
    }

    private func relayout() {
        layoutBox()
        heartSlot?.position = keyPosition
        heart?.position = keySpawnPosition
        wings?.position = keySpawnPosition
        lastLayoutSize = size
    }

    private let keyTopOffset: CGFloat = 419
    private let keyRightInset: CGFloat = 35

    private var keyPosition: CGPoint {
        CGPoint(x: size.width - keyRightInset, y: size.height - keyTopOffset)
    }

    private var keySpawnPosition: CGPoint {
        if let c = customLevel {
            return CGPoint(x: CGFloat(c.heartX) * size.width, y: CGFloat(c.heartY) * size.height)
        }
        return CGPoint(x: 60, y: boxBottomY + 60)
    }

    // the ellipsis in the rail, boss levels deliver the broken heart there
    private var bossSlotPosition: CGPoint {
        CGPoint(x: size.width - 35, y: 304)
    }

    private func buildLevel() {
        removeAllChildren()
        addWallpaper()
        let restore = pendingRestore
        pendingRestore = nil
        hasKey = restore?.hasKey ?? false
        hatchUnlocked = restore?.hatchOpen ?? false
        bossDelivered = restore?.hatchOpen ?? false

        player = SKNode()
        player.zPosition = 10
        player.physicsBody = makeBody()
        addChild(player)

        // all the model layers ride one node that scales from the feet for squish,
        // dropped a couple px so it rests flush on the ground
        squishBottom = SKNode()
        squishBottom.position = CGPoint(x: 0, y: -modelSize / 2 - 2)
        player.addChild(squishBottom)

        // an inner node just for the continuous walk bob, so it composes with squish
        walkNode = SKNode()
        squishBottom.addChild(walkNode)

        let spriteSize = CGSize(width: spriteW, height: spriteH)
        func layer(_ name: String, _ z: CGFloat) -> SKSpriteNode {
            let n = SKSpriteNode(texture: SKTexture(imageNamed: name))
            n.size = spriteSize
            n.anchorPoint = CGPoint(x: 0.5, y: 0)   // bottom center sits at the feet
            n.zPosition = z
            walkNode.addChild(n)
            return n
        }
        // wings sit behind everything, their own wider canvas
        wingsSprite = SKSpriteNode(texture: SKTexture(imageNamed: "cube.wings"))
        wingsSprite.size = CGSize(width: spriteW * 1.5, height: spriteW * 1.5 * 600 / 700)
        wingsSprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        wingsSprite.position = CGPoint(x: 0, y: spriteH * 0.62)
        wingsSprite.zPosition = -1
        walkNode.addChild(wingsSprite)

        bodySprite = layer("cube.sitting", 0)
        shoesSprite = layer("cube.shoes", 0.5)   // over the body, at the feet
        shoesSprite.position.y = -1              // sit them a touch lower
        eyesSprite = layer("cube.eyes", 1)
        mouthSprite = layer("cube.mouth.neutral", 1)

        heldHeart = SKSpriteNode(texture: SKTexture(imageNamed: "cube.heart"))
        heldHeart.size = CGSize(width: heartSize * 0.85, height: heartSize * 0.85)
        heldHeart.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        heldHeart.position = CGPoint(x: 0, y: spriteH * 0.9)
        heldHeart.zPosition = 1
        heldHeart.isHidden = true
        walkNode.addChild(heldHeart)

        updateStance()
        updateShoes()
        updateWings()
        walking = false
        wasGrounded = false   // it drops in from the air
        setMouth(airborne: true)

        layoutBox()
        addHeartSlot()
        // a held or delivered item isnt rendered again
        let skip = restore?.skipPickup ?? false
        if isAdLevel {
            if !skip { addWings() }
        } else {
            if !skip { addHeartKey() }
        }
        if hatchUnlocked, !isAdLevel, !isBossLevel {
            heartSlot?.addChild(SKSpriteNode(texture: GameArt.heartTexture(filled: true)))
        }

        if let restore {
            placeCube(fracX: restore.x, fracY: restore.y)
        } else {
            respawnCube()
        }
        lastLayoutSize = size
    }

    // square ruled paper behind everything, anchored to the left so the right
    // side only appears when the screen is wider than tall
    private func addWallpaper() {
        let side = max(size.width, size.height)
        let bg = SKSpriteNode(texture: SKTexture(imageNamed: "level.wallpaper"))
        bg.size = CGSize(width: side, height: side)
        bg.anchorPoint = CGPoint(x: 0, y: 0.5)
        bg.position = CGPoint(x: 0, y: size.height / 2)
        bg.zPosition = -100
        addChild(bg)
    }

    private func addHeartSlot() {
        let slot = SKNode()
        slot.zPosition = 7

        let sprite = SKSpriteNode(texture: GameArt.heartTexture(filled: false))
        slot.addChild(sprite)
        slot.position = keyPosition
        addChild(slot)
        heartSlot = slot
    }

    // tiktok like pop
    private func fillHeartSlot() {
        guard let slot = heartSlot else { return }
        let filled = SKSpriteNode(texture: GameArt.heartTexture(filled: true))
        filled.alpha = 0
        slot.addChild(filled)
        filled.run(.fadeIn(withDuration: 0.1))

        let shrink = SKAction.scale(to: 0.75, duration: 0.08)
        shrink.timingMode = .easeIn
        let overshoot = SKAction.scale(to: 1.35, duration: 0.14)
        overshoot.timingMode = .easeOut
        let settle = SKAction.scale(to: 1.0, duration: 0.12)
        settle.timingMode = .easeInEaseOut
        slot.run(.sequence([shrink, overshoot, settle]))

        onHeartFilled?()
    }

    private func layoutBox() {
        border?.removeFromParent()

        // flat bottom on the bar, arcs only on top
        let rect = CGRect(x: edgeInset, y: bottomInset,
                          width: size.width - edgeInset * 2,
                          height: size.height - edgeInset - bottomInset)
        boxBottomY = rect.minY
        boxTopY = rect.maxY
        boxMidX = rect.midX

        let minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY

        let cr = max(min(displayCornerRadius - edgeInset, rect.width / 2, rect.height / 2), 0)
        cornerR = cr
        let path = CGMutablePath()
        let quarter = CGFloat.pi / 2

        // walls and rounded top only, the full width gate is the floor
        path.move(to: CGPoint(x: maxX, y: minY))
        path.addLine(to: CGPoint(x: maxX, y: maxY - cr))
        path.addArc(center: CGPoint(x: maxX - cr, y: maxY - cr), radius: cr,
                    startAngle: 0, endAngle: quarter, clockwise: false)
        path.addLine(to: CGPoint(x: minX + cr, y: maxY))
        path.addArc(center: CGPoint(x: minX + cr, y: maxY - cr), radius: cr,
                    startAngle: quarter, endAngle: .pi, clockwise: false)
        path.addLine(to: CGPoint(x: minX, y: minY))

        // physics stays, visually hidden
        let shape = SKShapeNode(path: path)
        shape.strokeColor = .clear   // walls and top are invisible, physics only
        shape.lineWidth = 3
        shape.lineCap = .round
        shape.lineJoin = .round
        shape.fillColor = .clear
        shape.zPosition = 5

        let edge = SKPhysicsBody(edgeChainFrom: path)
        edge.categoryBitMask = Cat.ground
        shape.physicsBody = edge

        addChild(shape)
        border = shape

        buildHatch(y: minY)
        buildPlatforms()
    }

    // the gate spans the whole screen, once open you fall through anywhere
    private func buildHatch(y: CGFloat) {
        hatchNode?.removeFromParent()
        hatchNode = nil
        hatchCenter = CGPoint(x: size.width / 2, y: y)
        guard !hatchUnlocked else { return }

        let hatch = SKNode()
        hatch.zPosition = 6

        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: size.width, y: y))

        let outline = SKShapeNode(path: path)
        outline.strokeColor = .black
        outline.lineWidth = barOutline
        outline.lineCap = .round
        outline.zPosition = 0
        hatch.addChild(outline)

        let line = SKShapeNode(path: path)
        line.strokeColor = barColor
        line.lineWidth = barWidth
        line.lineCap = .round
        line.zPosition = 1
        hatch.addChild(line)

        let body = SKPhysicsBody(edgeFrom: CGPoint(x: edgeInset, y: y),
                                 to: CGPoint(x: size.width - edgeInset, y: y))
        body.categoryBitMask = Cat.ground
        hatch.physicsBody = body

        addChild(hatch)
        hatchNode = hatch
    }

    private func buildPlatforms() {
        platformsNode?.removeFromParent()
        let node = SKNode()
        node.zPosition = 5

        if let c = customLevel {
            for p in c.platforms {
                let cx = CGFloat(p.x) * size.width + CGFloat(p.offX)
                let cy = CGFloat(p.y) * size.height + CGFloat(p.offY)
                let len = CGFloat(p.w) * size.width
                if p.isVertical {
                    addSegment(node: node, a: CGPoint(x: cx, y: cy - len / 2),
                               b: CGPoint(x: cx, y: cy + len / 2), category: Cat.platform)
                } else {
                    addSegment(node: node, a: CGPoint(x: cx - len / 2, y: cy),
                               b: CGPoint(x: cx + len / 2, y: cy), category: Cat.platform)
                }
            }
        } else {
            // built in zigzag, 52pt spacing stays under the ~65pt jump height
            let keyY = keyPosition.y
            var y = boxBottomY + 52
            var i = 0
            while y < keyY - 35 {
                let cx = i % 2 == 0 ? size.width - 75 : size.width - 160
                addPlatform(node: node, cx: cx, y: y, width: 70)
                y += 52
                i += 1
            }
        }

        addChild(node)
        platformsNode = node
    }

    private func addPlatform(node: SKNode, cx: CGFloat, y: CGFloat, width: CGFloat) {
        addSegment(node: node, a: CGPoint(x: cx - width / 2, y: y),
                   b: CGPoint(x: cx + width / 2, y: y))
    }

    private func addSegment(node: SKNode, a: CGPoint, b: CGPoint, category: UInt32 = Cat.ground) {
        let path = CGMutablePath()
        path.move(to: a)
        path.addLine(to: b)

        // wider black stroke behind, so the rim shows all the way around the grayer bar
        let outline = SKShapeNode(path: path)
        outline.strokeColor = .black
        outline.lineWidth = barOutline
        outline.lineCap = .round
        outline.zPosition = 0
        node.addChild(outline)

        let line = SKShapeNode(path: path)
        line.strokeColor = barColor
        line.lineWidth = barWidth
        line.lineCap = .round
        line.zPosition = 1
        let body = SKPhysicsBody(edgeFrom: a, to: b)
        body.categoryBitMask = category
        line.physicsBody = body
        node.addChild(line)
    }

    private func addHeartKey() {
        heart?.removeFromParent()

        let key = SKNode()
        key.zPosition = 8
        if isBossLevel {
            key.addChild(SKSpriteNode(texture: GameArt.brokenHeartTexture()))
        } else {
            let h = SKSpriteNode(texture: SKTexture(imageNamed: "cube.heart"))
            h.size = CGSize(width: heartSize, height: heartSize)
            key.addChild(h)
        }
        key.position = keySpawnPosition

        let body = SKPhysicsBody(circleOfRadius: 20)
        body.isDynamic = false
        body.categoryBitMask = Cat.heart
        body.collisionBitMask = 0
        key.physicsBody = body

        addChild(key)
        heart = key
    }

    private func addWings() {
        wings?.removeFromParent()

        let node = SKNode()
        node.zPosition = 8
        // dash pickup is the shoes, double jump pickup is the wings
        if adPowerup == .dash {
            let shoes = SKSpriteNode(texture: SKTexture(imageNamed: "dash.item"))
            shoes.size = CGSize(width: heartSize, height: heartSize)
            node.addChild(shoes)
        } else {
            let w = SKSpriteNode(texture: SKTexture(imageNamed: "cube.wings"))
            w.size = CGSize(width: heartSize * 1.4, height: heartSize * 1.4 * 600 / 700)
            node.addChild(w)
        }
        node.position = keySpawnPosition

        let body = SKPhysicsBody(circleOfRadius: 22)
        body.isDynamic = false
        body.categoryBitMask = Cat.wings
        body.collisionBitMask = 0
        node.physicsBody = body

        addChild(node)
        wings = node
    }

    private func openHatch() {
        guard !hatchUnlocked else { return }
        hatchUnlocked = true
        updateStance()   // heart is deposited, stop holding it
        onHatchOpened?()
        guard let hatch = hatchNode else { return }
        hatch.physicsBody = nil
        hatch.run(.sequence([.wait(forDuration: 0.35),
                             .fadeOut(withDuration: 0.25),
                             .removeFromParent()]))
        hatchNode = nil
    }

    private func respawnCube() {
        let x = pendingEntryFrac.map { $0 * size.width } ?? boxMidX
        pendingEntryFrac = nil
        player.position = CGPoint(x: x, y: boxTopY - 40)
        player.physicsBody?.velocity = .zero
        player.physicsBody?.isDynamic = true
        player.isHidden = false
        hasFallenThrough = false
        // drop in phasing through platforms, solid again once it lands on the floor
        beginEntryPhasing(customLevel != nil)
    }

    private func placeCube(fracX: Double, fracY: Double) {
        player.position = CGPoint(x: CGFloat(fracX) * size.width,
                                  y: CGFloat(fracY) * size.height)
        player.physicsBody?.velocity = .zero
        player.physicsBody?.isDynamic = true
        player.isHidden = false
        hasFallenThrough = false
        beginEntryPhasing(false)
    }

    private func beginEntryPhasing(_ on: Bool) {
        entryPhasing = on
        // while phasing only the floor collides, otherwise platforms and walls are solid too
        player.physicsBody?.collisionBitMask = on ? Cat.ground : Cat.ground | Cat.platform
    }

    // exact state for the save, held items report as consumed so they wont respawn
    func snapshot() -> RestoreState {
        guard let player else {
            return RestoreState(x: 0.5, y: 0.5, hasKey: false, hatchOpen: false, skipPickup: false)
        }
        let consumed = isAdLevel ? (wings == nil) : (heart == nil)
        return RestoreState(x: Double(player.position.x / size.width),
                            y: Double(player.position.y / size.height),
                            hasKey: hasKey, hatchOpen: hatchUnlocked, skipPickup: consumed)
    }

    func restore(_ state: RestoreState) {
        pendingRestore = state
        if player != nil { buildLevel() }
    }

    // renders the visible level (platforms, item, gate, cube) for the save card,
    // no walls or empty heart since those dont show in the real level
    func thumbnailImage() -> UIImage? {
        guard let player else { return nil }
        let scale: CGFloat = 0.28
        // crop to the save card aspect, trims the bar/gate below and empty top
        let cardAspect: CGFloat = 0.72
        let winH = size.width / cardAspect
        let winBottom = boxBottomY
        let imgSize = CGSize(width: size.width * scale, height: winH * scale)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: imgSize, format: format)

        func pt(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * scale, y: imgSize.height - (p.y - winBottom) * scale)
        }

        return renderer.image { ctx in
            let cg = ctx.cgContext
            // gray fallback then the ruled paper wallpaper, square anchored left
            UIColor(white: 0.16, alpha: 1).setFill()
            cg.fill(CGRect(origin: .zero, size: imgSize))
            if let wp = UIImage(named: "level.wallpaper") {
                let sd = max(imgSize.width, imgSize.height)
                wp.draw(in: CGRect(x: 0, y: (imgSize.height - sd) / 2, width: sd, height: sd))
            }

            cg.setLineCap(.round)

            // a black rim under a grayer bar, matching the game
            func drawBar(_ a: CGPoint, _ b: CGPoint) {
                cg.setStrokeColor(UIColor.black.cgColor)
                cg.setLineWidth(barOutline * scale)
                cg.move(to: a); cg.addLine(to: b); cg.strokePath()
                cg.setStrokeColor(barColor.cgColor)
                cg.setLineWidth(barWidth * scale)
                cg.move(to: a); cg.addLine(to: b); cg.strokePath()
            }

            // platforms and walls
            for node in platformsNode?.children ?? [] {
                guard let shape = node as? SKShapeNode, shape.physicsBody != nil,
                      let bb = shape.path?.boundingBoxOfPath else { continue }
                if bb.width >= bb.height {
                    drawBar(pt(CGPoint(x: bb.minX, y: bb.midY)), pt(CGPoint(x: bb.maxX, y: bb.midY)))
                } else {
                    drawBar(pt(CGPoint(x: bb.midX, y: bb.minY)), pt(CGPoint(x: bb.midX, y: bb.maxY)))
                }
            }
            // locked gate spans the floor
            if !hatchUnlocked {
                drawBar(pt(CGPoint(x: 0, y: boxBottomY)), pt(CGPoint(x: size.width, y: boxBottomY)))
            }

            // collectible item
            for node in [heart, wings].compactMap({ $0 }) {
                guard let sprite = node.children.first as? SKSpriteNode,
                      let cgImg = sprite.texture?.cgImage() else { continue }
                let sz = sprite.size
                let c = pt(node.position)
                UIImage(cgImage: cgImg).draw(in: CGRect(x: c.x - sz.width * scale / 2,
                                                        y: c.y - sz.height * scale / 2,
                                                        width: sz.width * scale,
                                                        height: sz.height * scale))
            }

            // the layered player model, drawn from the feet up
            let feet = pt(CGPoint(x: player.position.x, y: player.position.y - modelSize / 2 - 2))
            let holding = hasKey && !hatchUnlocked
            // centered layer (wings, held heart)
            func drawCentered(_ name: String, w: CGFloat, h: CGFloat, cy: CGFloat) {
                UIImage(named: name)?.draw(in: CGRect(x: feet.x - w * scale / 2, y: cy - h * scale / 2,
                                                      width: w * scale, height: h * scale))
            }
            // bottom anchored body layer
            func drawBody(_ name: String) {
                UIImage(named: name)?.draw(in: CGRect(x: feet.x - spriteW * scale / 2,
                                                      y: feet.y - spriteH * scale,
                                                      width: spriteW * scale, height: spriteH * scale))
            }
            if extraJumps > 0 {
                let ww = spriteW * 1.5
                drawCentered("cube.wings", w: ww, h: ww * 600 / 700, cy: feet.y - spriteH * 0.62 * scale)
            }
            drawBody(holding ? "cube.holding" : "cube.sitting")
            if hasDash { drawBody("cube.shoes") }
            drawBody("cube.eyes")
            drawBody("cube.mouth.neutral")
            if holding {
                drawCentered("cube.heart", w: heartSize * 0.85, h: heartSize * 0.85,
                             cy: feet.y - spriteH * 0.9 * scale)
            }
        }
    }


    func setMove(_ direction: CGFloat) {
        moveDirection = direction
        if direction != 0 { lastFacing = direction; faceShoes(direction) }
        lookEyes(direction)
    }

    // short horizontal burst toward the held or last faced direction
    func dash() {
        guard hasDash, sceneTime >= dashReadyTime else { return }
        dashDirection = moveDirection != 0 ? moveDirection : lastFacing
        dashEndTime = sceneTime + dashDuration
        dashReadyTime = sceneTime + dashCooldown
        dashSquish()
        faceShoes(dashDirection)
        lookEyes(dashDirection, amount: 3.5)
    }

    // the face and shoes glance toward the direction of travel, the wings trail opposite
    private func lookEyes(_ dir: CGFloat, amount: CGFloat = 2.6) {
        let x = dir * amount
        eyesSprite?.run(.moveTo(x: x, duration: 0.1), withKey: "look")
        mouthSprite?.run(.moveTo(x: x, duration: 0.1), withKey: "look")
        shoesSprite?.run(.moveTo(x: x, duration: 0.1), withKey: "look")
        wingsSprite?.run(.moveTo(x: -x * 3, duration: 0.1), withKey: "look")
    }

    // wings only show once double jump is available
    private func updateWings() {
        wingsSprite?.isHidden = extraJumps <= 0
    }

    // open mouth in the air, a random neutral or happy mouth once back on the ground
    private func setMouth(airborne: Bool) {
        let name = airborne ? "cube.mouth.open"
                            : (Bool.random() ? "cube.mouth.neutral" : "cube.mouth.happy")
        mouthSprite?.texture = SKTexture(imageNamed: name)
    }

    // shoes are drawn facing right, mirror them when heading left
    private func faceShoes(_ dir: CGFloat) {
        shoesSprite?.xScale = dir < 0 ? -1 : 1
    }

    // shoes only show once dash is available
    private func updateShoes() {
        shoesSprite?.isHidden = !hasDash
    }

    // sitting normally, holding the heart over its head while carrying the key
    private func updateStance() {
        guard let bodySprite, let heldHeart else { return }
        let holding = hasKey && !hatchUnlocked
        bodySprite.texture = SKTexture(imageNamed: holding ? "cube.holding" : "cube.sitting")
        heldHeart.isHidden = !holding
    }

    // a gentle continuous squash and stretch while walking on the ground
    private func setWalking(_ on: Bool) {
        guard on != walking, let walkNode else { return }
        walking = on
        if on {
            let down = SKAction.group([.scaleX(to: 1.06, duration: 0.15), .scaleY(to: 0.9, duration: 0.15)])
            down.timingMode = .easeInEaseOut
            let up = SKAction.group([.scaleX(to: 1, duration: 0.15), .scaleY(to: 1, duration: 0.15)])
            up.timingMode = .easeInEaseOut
            walkNode.run(.repeatForever(.sequence([down, up])), withKey: "walk")
        } else {
            walkNode.removeAction(forKey: "walk")
            let ret = SKAction.group([.scaleX(to: 1, duration: 0.1), .scaleY(to: 1, duration: 0.1)])
            ret.timingMode = .easeOut
            walkNode.run(ret)
        }
    }

    private func spawnParticles(at pos: CGPoint, count: Int, life: TimeInterval = 0.32,
                                _ vel: (Int) -> CGVector) {
        for i in 0..<count {
            let dot = SKShapeNode(circleOfRadius: 1.8)
            dot.fillColor = .white
            dot.strokeColor = .clear
            dot.zPosition = 9
            dot.position = pos
            addChild(dot)
            let v = vel(i)
            let move = SKAction.moveBy(x: v.dx, y: v.dy, duration: life)
            move.timingMode = .easeOut
            dot.run(.sequence([
                .group([move, .fadeOut(withDuration: life), .scale(to: 0.2, duration: life)]),
                .removeFromParent()
            ]))
        }
    }

    private func jumpPuff() {
        guard let player else { return }
        spawnParticles(at: CGPoint(x: player.position.x, y: player.position.y - 14), count: 5) { _ in
            CGVector(dx: .random(in: -16...16), dy: .random(in: -20 ... -6))
        }
    }

    private func landPuff() {
        guard let player else { return }
        spawnParticles(at: CGPoint(x: player.position.x, y: player.position.y - 14), count: 6) { i in
            let side: CGFloat = i % 2 == 0 ? 1 : -1
            return CGVector(dx: side * .random(in: 10...26), dy: .random(in: 2...9))
        }
    }

    // trails a particle from wherever the cube is each frame of the dash
    private func dashTrail() {
        guard let player else { return }
        spawnParticles(at: player.position, count: 1, life: 0.25) { _ in
            CGVector(dx: -self.dashDirection * .random(in: 8...18), dy: .random(in: -6...6))
        }
    }

    // bottom bound squash and stretch for jump, keyed so it doesnt pile up
    private func squish(x: CGFloat, y: CGFloat, hold: TimeInterval, back: TimeInterval) {
        guard let squishBottom else { return }
        squishBottom.removeAction(forKey: "squish")
        let out = SKAction.group([.scaleX(to: x, duration: hold), .scaleY(to: y, duration: hold)])
        out.timingMode = .easeOut
        let ret = SKAction.group([.scaleX(to: 1, duration: back), .scaleY(to: 1, duration: back)])
        ret.timingMode = .easeOut
        squishBottom.run(.sequence([out, ret]), withKey: "squish")
    }

    // snaps flat the instant it touches down, then springs back, bottom bound
    private func landSquish() {
        guard let squishBottom else { return }
        squishBottom.removeAction(forKey: "squish")
        squishBottom.xScale = 1.34
        squishBottom.yScale = 0.64
        let ret = SKAction.group([.scaleX(to: 1, duration: 0.17), .scaleY(to: 1, duration: 0.17)])
        ret.timingMode = .easeOut
        squishBottom.run(ret, withKey: "squish")
    }

    private func dashSquish() {
        guard let squishBottom else { return }
        squishBottom.removeAction(forKey: "squish")
        let out = SKAction.group([.scaleX(to: 1.4, duration: 0.06), .scaleY(to: 0.72, duration: 0.06)])
        out.timingMode = .easeOut
        let ret = SKAction.group([.scaleX(to: 1, duration: 0.18), .scaleY(to: 1, duration: 0.18)])
        ret.timingMode = .easeOut
        squishBottom.run(.sequence([out, ret]), withKey: "squish")
    }

    // small rectangle whose bottom sits at the models feet, animation independent
    private func makeBody() -> SKPhysicsBody {
        let body = SKPhysicsBody(rectangleOf: CGSize(width: hitW, height: hitH),
                                 center: CGPoint(x: 0, y: -modelSize / 2 + hitH / 2))
        body.allowsRotation = false
        body.restitution = 0
        body.friction = 0
        body.linearDamping = 0
        body.categoryBitMask = Cat.player
        body.contactTestBitMask = Cat.ground | Cat.heart | Cat.wings
        body.collisionBitMask = Cat.ground
        body.usesPreciseCollisionDetection = true
        return body
    }

    func jump() {
        jumpRequestedTime = sceneTime
    }

    // cube waits frozen at the top until the scroll settles, then drops
    func prepareEntry(atXFraction frac: CGFloat) {
        pendingEntryFrac = frac
        if boxTopY > 0 { respawnCube() }
        player?.physicsBody?.isDynamic = false
    }

    func beginEntry() {
        player?.physicsBody?.isDynamic = true
    }

    // rebuilds the level from scratch, used to restart a playtest
    func reload() {
        pendingRestore = nil
        buildLevel()
    }

    override func update(_ currentTime: TimeInterval) {
        guard player != nil else { return }
        sceneTime = currentTime

        // catches resizes the events missed
        if size != lastLayoutSize {
            relayout()
        }

        guard let body = player.physicsBody else { return }

        // real frame delta so the look-ahead is right at any refresh rate
        let dt: CGFloat = lastTime > 0 ? CGFloat(min(currentTime - lastTime, 1.0 / 30.0)) : 1.0 / 60.0
        lastTime = currentTime

        // cancel the collision solvers bounce on a hard landing, a bounce is a
        // small upward velocity right after descending, a jump is far larger
        if prevVelY < -200, body.velocity.dy > 2, body.velocity.dy < 300,
           !(sceneTime < dashEndTime) {
            body.velocity.dy = 0
        }
        prevVelY = body.velocity.dy

        // look one frame ahead, cap velocity, walls stop the model edge
        let wallHalf = modelSize / 2
        let wallMin = edgeInset + wallHalf
        let wallMax = size.width - edgeInset - wallHalf
        let dashing = sceneTime < dashEndTime
        var vx = dashing ? dashDirection * dashSpeed : moveDirection * moveSpeed
        let predictedX = player.position.x + vx * dt
        if predictedX > wallMax {
            vx = max(0, (wallMax - player.position.x) / dt)
        } else if predictedX < wallMin {
            vx = min(0, (wallMin - player.position.x) / dt)
        }
        body.velocity.dx = vx
        // dashes hold their height and trail particles the whole way
        if dashing {
            body.velocity.dy = 0
            dashTrail()
        }

        // terminal velocity so long falls cant tunnel through thin edges
        if body.velocity.dy < -1400 { body.velocity.dy = -1400 }

        // raycast under the hitboxs bottom corners, ignoring phased through platforms
        let groundMask = entryPhasing ? Cat.ground : Cat.ground | Cat.platform
        var grounded = false
        if body.velocity.dy <= 20 {
            let foot = hitW / 2 - 1
            for ox in [-foot, foot] {
                let start = CGPoint(x: player.position.x + ox, y: player.position.y)
                let end = CGPoint(x: start.x, y: start.y - modelSize / 2 - 6)
                physicsWorld.enumerateBodies(alongRayStart: start, end: end) { hit, _, _, stop in
                    if hit.categoryBitMask & groundMask != 0 {
                        grounded = true
                        stop.pointee = true
                    }
                }
                if grounded { break }
            }
        }
        if grounded {
            lastGroundedTime = sceneTime
            airJumpsUsed = 0
            // touched the floor for the first time, everything turns solid
            if entryPhasing { beginEntryPhasing(false) }
        }
        // open mouth in the air, reroll neutral or happy the moment it lands
        if grounded != wasGrounded {
            setMouth(airborne: !grounded)
            wasGrounded = grounded
        }
        // bob while walking on the ground, but not mid dash or jump
        setWalking(grounded && moveDirection != 0 && !dashing && !entryPhasing)
        if body.velocity.dy < -60 {
            descentSpeed = min(descentSpeed, body.velocity.dy)
        }
        if grounded, descentSpeed < -320, body.velocity.dy > -60 {
            landSquish()
            landPuff()
            descentSpeed = 0
        }

        if jumpRequestedTime >= 0, sceneTime - jumpRequestedTime <= jumpBufferTime {
            let groundJump = sceneTime - lastGroundedTime <= coyoteTime
            if groundJump || airJumpsUsed < extraJumps {
                if !groundJump { airJumpsUsed += 1 }
                body.velocity.dy = 0
                body.applyImpulse(CGVector(dx: 0, dy: jumpSpeed * body.mass))
                // thin and tall on launch, back to a full cube by the apex
                squish(x: 0.68, y: 1.42, hold: 0.05, back: 0.12)
                jumpPuff()
                jumpRequestedTime = -1
                lastGroundedTime = -1
            }
        }

        let jumpState = (first: sceneTime - lastGroundedTime <= coyoteTime,
                         second: extraJumps > 0 && airJumpsUsed < extraJumps)
        if jumpState != lastJumpState {
            lastJumpState = jumpState
            onJumpStateChanged?(jumpState.first, jumpState.second)
        }

        let dashReady = sceneTime >= dashReadyTime
        if dashReady != lastDashReady {
            lastDashReady = dashReady
            onDashStateChanged?(dashReady)
        }

        if hasKey, !hatchUnlocked {
            let target = isBossLevel ? bossSlotPosition : keyPosition
            let dx = player.position.x - target.x
            let dy = player.position.y - target.y
            if dx * dx + dy * dy < 70 * 70 {
                if isBossLevel {
                    if !bossDelivered {
                        bossDelivered = true
                        onBossDelivered?()
                        // gate waits for the popup to fill its slash heart
                        run(.sequence([.wait(forDuration: 0.55),
                                       .run { [weak self] in self?.openHatch() }]))
                    }
                } else {
                    fillHeartSlot()
                    openHatch()
                }
            }
        }

        if !hasFallenThrough, player.position.y < boxBottomY - 30 {
            hasFallenThrough = true
            onFellThrough?(player.position.x / size.width)
        }
        if player.position.y < boxBottomY - 140 {
            if hasFallenThrough {
                // park hidden after completion
                player.isHidden = true
                body.isDynamic = false
                player.position = CGPoint(x: boxMidX, y: boxBottomY + 20)
                body.velocity = .zero
            } else {
                respawnCube()
            }
        }
    }

    // runs after the physics step
    override func didSimulatePhysics() {
        guard let body = player?.physicsBody, !hasFallenThrough else { return }
        let wallHalf = modelSize / 2
        let wallMin = edgeInset + wallHalf
        let wallMax = size.width - edgeInset - wallHalf
        if player.position.x < wallMin {
            player.position.x = wallMin
            if body.velocity.dx < 0 { body.velocity.dx = 0 }
        } else if player.position.x > wallMax {
            player.position.x = wallMax
            if body.velocity.dx > 0 { body.velocity.dx = 0 }
        }
    }
}

extension LevelScene: SKPhysicsContactDelegate {
    func didBegin(_ contact: SKPhysicsContact) {
        let other = contact.bodyA.categoryBitMask == Cat.player ? contact.bodyB : contact.bodyA

        // dropping in through the level, items cant be grabbed until it lands
        if entryPhasing { return }

        switch other.categoryBitMask {
        case Cat.heart:
            if let node = other.node, node == heart {
                heart = nil
                hasKey = true
                updateStance()
                onCollectHeart?()
                node.run(.sequence([
                    .group([.scale(to: 1.8, duration: 0.15), .fadeOut(withDuration: 0.15)]),
                    .removeFromParent()
                ]))
            }
        case Cat.wings:
            if let node = other.node, node == wings {
                wings = nil
                onCollectPowerup?(adPowerup)
                openHatch()
                node.run(.sequence([
                    .group([.scale(to: 1.8, duration: 0.15), .fadeOut(withDuration: 0.15)]),
                    .removeFromParent()
                ]))
            }
        default:
            break
        }
    }
}

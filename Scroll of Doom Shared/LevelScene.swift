import SpriteKit
import UIKit

final class LevelScene: SKScene {

    private let moveSpeed: CGFloat = 260
    private let jumpSpeed: CGFloat = 715
    private let gravityY: CGFloat = -26
    // coyote time and jump buffering
    private let coyoteTime: TimeInterval = 0.08
    private let jumpBufferTime: TimeInterval = 0.12
    private let edgeInset: CGFloat = 4
    // matches the create button column in the tab bar
    private var openingWidth: CGFloat { (size.width - 20) / 5 }
    private let openingFrac: CGFloat = 0.5

    private enum Cat {
        static let player: UInt32 = 0x1 << 0
        static let ground: UInt32 = 0x1 << 1
        static let heart:  UInt32 = 0x1 << 2
        static let wings:  UInt32 = 0x1 << 3
    }

    var levelIndex = 0
    var isAdLevel = false
    var isBossLevel = false
    var extraJumps = 0
    // box floor sits on top of the tab bar
    var bottomInset: CGFloat = 0
    var onFellThrough: ((CGFloat) -> Void)?
    var onCollectHeart: (() -> Void)?
    var onHeartFilled: (() -> Void)?
    var onCollectWings: (() -> Void)?
    var onHatchOpened: (() -> Void)?
    var onBossDelivered: (() -> Void)?

    private var player: SKShapeNode!
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

    private var bossDelivered = false
    private var moveDirection: CGFloat = 0
    private var lastGroundedTime: TimeInterval = -1
    private var jumpRequestedTime: TimeInterval = -1
    private var sceneTime: TimeInterval = 0
    private var airJumpsUsed = 0
    private var hasFallenThrough = false
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
        backgroundColor = .black
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
        CGPoint(x: 60, y: boxBottomY + 60)
    }

    // the ellipsis in the rail, boss levels deliver the broken heart there
    private var bossSlotPosition: CGPoint {
        CGPoint(x: size.width - 35, y: 304)
    }

    private func buildLevel() {
        removeAllChildren()
        hasKey = false
        hatchUnlocked = false
        bossDelivered = false

        let cube = CGSize(width: 30, height: 30)
        player = SKShapeNode(rectOf: cube, cornerRadius: 7)
        player.fillColor = .white
        player.strokeColor = .white
        player.lineWidth = 1.5
        player.zPosition = 10

        let body = SKPhysicsBody(rectangleOf: CGSize(width: cube.width - 2, height: cube.height - 2))
        body.allowsRotation = false
        body.restitution = 0
        body.friction = 0
        body.linearDamping = 0
        body.categoryBitMask = Cat.player
        body.contactTestBitMask = Cat.ground | Cat.heart | Cat.wings
        body.collisionBitMask = Cat.ground
        // sweep collision so the cube cant slip through
        body.usesPreciseCollisionDetection = true
        player.physicsBody = body
        addChild(player)

        for ex in [-6.0, 6.0] {
            let eye = SKShapeNode(circleOfRadius: 3)
            eye.fillColor = .black
            eye.strokeColor = .clear
            eye.position = CGPoint(x: ex, y: 4)
            player.addChild(eye)
        }

        layoutBox()
        addHeartSlot()
        if isAdLevel {
            addWings()
        } else {
            addHeartKey()
        }
        respawnCube()
        lastLayoutSize = size
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

        let openingCenterX = rect.minX + rect.width * openingFrac
        let openingStartX = openingCenterX - openingWidth / 2
        let openingEndX = openingCenterX + openingWidth / 2

        let cr = max(min(displayCornerRadius - edgeInset, rect.width / 2, rect.height / 2), 0)
        cornerR = cr
        let path = CGMutablePath()
        let quarter = CGFloat.pi / 2

        path.move(to: CGPoint(x: openingEndX, y: minY))
        path.addLine(to: CGPoint(x: maxX, y: minY))
        path.addLine(to: CGPoint(x: maxX, y: maxY - cr))
        path.addArc(center: CGPoint(x: maxX - cr, y: maxY - cr), radius: cr,
                    startAngle: 0, endAngle: quarter, clockwise: false)
        path.addLine(to: CGPoint(x: minX + cr, y: maxY))
        path.addArc(center: CGPoint(x: minX + cr, y: maxY - cr), radius: cr,
                    startAngle: quarter, endAngle: .pi, clockwise: false)
        path.addLine(to: CGPoint(x: minX, y: minY))
        path.addLine(to: CGPoint(x: openingStartX, y: minY))

        // physics stays, visually hidden
        let shape = SKShapeNode(path: path)
        shape.strokeColor = .black
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

        buildHatch(startX: openingStartX, endX: openingEndX, y: minY)
        buildPlatforms()
    }

    private func buildHatch(startX: CGFloat, endX: CGFloat, y: CGFloat) {
        hatchNode?.removeFromParent()
        hatchNode = nil
        hatchCenter = CGPoint(x: (startX + endX) / 2, y: y)
        guard !hatchUnlocked else { return }

        let gray = UIColor(white: 0.45, alpha: 1)
        let hatch = SKNode()
        hatch.zPosition = 6

        let path = CGMutablePath()
        path.move(to: CGPoint(x: startX, y: y))
        path.addLine(to: CGPoint(x: endX, y: y))
        let line = SKShapeNode(path: path)
        line.strokeColor = gray
        line.lineWidth = 3
        line.lineCap = .round
        hatch.addChild(line)

        // lock shows on the create button

        let body = SKPhysicsBody(edgeFrom: CGPoint(x: startX, y: y),
                                 to: CGPoint(x: endX, y: y))
        body.categoryBitMask = Cat.ground
        hatch.physicsBody = body

        addChild(hatch)
        hatchNode = hatch
    }

    // 52pt spacing stays under the ~65pt jump height
    private func buildPlatforms() {
        platformsNode?.removeFromParent()

        let node = SKNode()
        node.zPosition = 5

        let keyY = keyPosition.y
        let width: CGFloat = 70
        var y = boxBottomY + 52
        var i = 0
        while y < keyY - 35 {
            let cx = i % 2 == 0 ? size.width - 75 : size.width - 160
            let a = CGPoint(x: cx - width / 2, y: y)
            let b = CGPoint(x: cx + width / 2, y: y)
            let path = CGMutablePath()
            path.move(to: a)
            path.addLine(to: b)
            let line = SKShapeNode(path: path)
            line.strokeColor = .white
            line.lineWidth = 3
            line.lineCap = .round
            let body = SKPhysicsBody(edgeFrom: a, to: b)
            body.categoryBitMask = Cat.ground
            line.physicsBody = body
            node.addChild(line)
            y += 52
            i += 1
        }

        addChild(node)
        platformsNode = node
    }

    private func addHeartKey() {
        heart?.removeFromParent()

        let key = SKNode()
        key.zPosition = 8
        key.addChild(SKSpriteNode(texture: isBossLevel
            ? GameArt.brokenHeartTexture()
            : GameArt.heartTexture(filled: true)))
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
        node.addChild(SKSpriteNode(texture: GameArt.wingsTexture()))
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
    }

    func setMove(_ direction: CGFloat) { moveDirection = direction }

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

    override func update(_ currentTime: TimeInterval) {
        guard let body = player?.physicsBody else { return }
        sceneTime = currentTime

        // catches resizes the events missed
        if size != lastLayoutSize {
            relayout()
        }

        // look one frame ahead, cap velocity
        let dt: CGFloat = 1.0 / 60.0
        let halfW: CGFloat = 14
        let wallMin = edgeInset + halfW
        let wallMax = size.width - edgeInset - halfW
        var vx = moveDirection * moveSpeed
        let predictedX = player.position.x + vx * dt
        if predictedX > wallMax {
            vx = max(0, (wallMax - player.position.x) / dt)
        } else if predictedX < wallMin {
            vx = min(0, (wallMin - player.position.x) / dt)
        }
        body.velocity.dx = vx

        // terminal velocity so long falls cant tunnel through thin edges
        if body.velocity.dy < -1400 { body.velocity.dy = -1400 }

        // raycast under both bottom corners
        var grounded = false
        if body.velocity.dy <= 20 {
            for ox in [-halfW + 1, halfW - 1] {
                let start = CGPoint(x: player.position.x + ox, y: player.position.y)
                let end = CGPoint(x: start.x, y: start.y - halfW - 6)
                physicsWorld.enumerateBodies(alongRayStart: start, end: end) { hit, _, _, stop in
                    if hit.categoryBitMask == Cat.ground {
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
        }

        if jumpRequestedTime >= 0, sceneTime - jumpRequestedTime <= jumpBufferTime {
            let groundJump = sceneTime - lastGroundedTime <= coyoteTime
            if groundJump || airJumpsUsed < extraJumps {
                if !groundJump { airJumpsUsed += 1 }
                body.velocity.dy = 0
                body.applyImpulse(CGVector(dx: 0, dy: jumpSpeed * body.mass))
                jumpRequestedTime = -1
                lastGroundedTime = -1
            }
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
        let halfW: CGFloat = 14
        let wallMin = edgeInset + halfW
        let wallMax = size.width - edgeInset - halfW
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

        switch other.categoryBitMask {
        case Cat.heart:
            if let node = other.node, node == heart {
                heart = nil
                hasKey = true
                onCollectHeart?()
                node.run(.sequence([
                    .group([.scale(to: 1.8, duration: 0.15), .fadeOut(withDuration: 0.15)]),
                    .removeFromParent()
                ]))
            }
        case Cat.wings:
            if let node = other.node, node == wings {
                wings = nil
                onCollectWings?()
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

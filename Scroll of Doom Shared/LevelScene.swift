import SpriteKit
import UIKit

final class LevelScene: SKScene {

    private let moveSpeed: CGFloat = 260
    private let jumpSpeed: CGFloat = 950
    private let maxJumps = 1
    private let gravityY: CGFloat = -30
    private let edgeInset: CGFloat = 4
    private let openingWidth: CGFloat = 46
    // never 0.5 so a dropped cube lands on solid floor and cant chain-fall
    private let openingFracs: [CGFloat] = [0.24, 0.76, 0.34, 0.66, 0.28]

    private enum Cat {
        static let player: UInt32 = 0x1 << 0
        static let ground: UInt32 = 0x1 << 1
        static let heart:  UInt32 = 0x1 << 2
    }

    var levelIndex = 0
    var onFellThrough: ((CGFloat) -> Void)?
    var onCollectHeart: (() -> Void)?
    var onHeartFilled: (() -> Void)?

    private var player: SKShapeNode!
    private var border: SKShapeNode?
    private var heart: SKNode?
    private var heartSlot: SKNode?
    private var hatchNode: SKNode?
    private var platformsNode: SKNode?
    private var hatchCenter: CGPoint = .zero
    private var hasKey = false
    private var hatchUnlocked = false

    private var boxBottomY: CGFloat = 0
    private var boxTopY: CGFloat = 0
    private var boxMidX: CGFloat = 0
    // needed by the corner constraint in didSimulatePhysics
    private var cornerR: CGFloat = 0

    private var moveDirection: CGFloat = 0
    private var jumpsRemaining = 1
    private var hasFallenThrough = false
    private var pendingEntryFrac: CGFloat?
    private var lastLayoutSize: CGSize = .zero

    private var openingFrac: CGFloat { openingFracs[levelIndex % openingFracs.count] }

    // reads the real iphone display corner radius, falls back to a safe default
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
        buildLevel()
    }

    // scenes are created at a placeholder size and get the real one later,
    // the resize event can fire before didMove or while the page is offscreen
    // and paused, so update also watches the size every frame as a backstop
    override func didChangeSize(_ oldSize: CGSize) {
        guard player != nil else { return }
        relayout()
        respawnCube()
    }

    private func relayout() {
        layoutBox()
        heartSlot?.position = keyPosition
        heart?.position = keySpawnPosition
        lastLayoutSize = size
    }

    // tune these two to line the key up with the rail slot
    private let keyTopOffset: CGFloat = 515
    private let keyRightInset: CGFloat = 35

    private var keyPosition: CGPoint {
        CGPoint(x: size.width - keyRightInset, y: size.height - keyTopOffset)
    }

    // key spawns down left so it has to be carried up to the heart lock
    private var keySpawnPosition: CGPoint {
        CGPoint(x: 60, y: boxBottomY + 60)
    }

    private func buildLevel() {
        removeAllChildren()
        hasKey = false
        hatchUnlocked = false

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
        body.contactTestBitMask = Cat.ground | Cat.heart
        body.collisionBitMask = Cat.ground
        // sweeps movement path each frame so cube cant slip past the boundary
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
        addHeartKey()
        respawnCube()
        lastLayoutSize = size
    }

    // upright unfilled heart on the right, this is the lock the key gets carried to
    private func addHeartSlot() {
        let slot = SKNode()
        slot.zPosition = 7

        let sprite = SKSpriteNode(texture: heartTexture(systemName: "heart"))
        slot.addChild(sprite)
        slot.position = keyPosition
        addChild(slot)
        heartSlot = slot
    }

    private func heartTexture(systemName: String) -> SKTexture {
        let canvasSize = CGSize(width: 40, height: 40)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        let img = renderer.image { _ in
            let cfg = UIImage.SymbolConfiguration(pointSize: 28, weight: .regular)
            if let sym = UIImage(systemName: systemName, withConfiguration: cfg)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                sym.draw(in: CGRect(x: 20 - sym.size.width/2, y: 20 - sym.size.height/2,
                                    width: sym.size.width, height: sym.size.height))
            }
        }
        return SKTexture(image: img)
    }

    // filled heart pops in with the tiktok like bounce, shrink then overshoot and settle
    private func fillHeartSlot() {
        guard let slot = heartSlot else { return }
        let filled = SKSpriteNode(texture: heartTexture(systemName: "heart.fill"))
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

        let rect = CGRect(x: edgeInset, y: edgeInset,
                          width: size.width - edgeInset * 2,
                          height: size.height - edgeInset * 2)
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
        path.addLine(to: CGPoint(x: maxX - cr, y: minY))
        path.addArc(center: CGPoint(x: maxX - cr, y: minY + cr), radius: cr,
                    startAngle: -quarter, endAngle: 0, clockwise: false)
        path.addLine(to: CGPoint(x: maxX, y: maxY - cr))
        path.addArc(center: CGPoint(x: maxX - cr, y: maxY - cr), radius: cr,
                    startAngle: 0, endAngle: quarter, clockwise: false)
        path.addLine(to: CGPoint(x: minX + cr, y: maxY))
        path.addArc(center: CGPoint(x: minX + cr, y: maxY - cr), radius: cr,
                    startAngle: quarter, endAngle: .pi, clockwise: false)
        path.addLine(to: CGPoint(x: minX, y: minY + cr))
        path.addArc(center: CGPoint(x: minX + cr, y: minY + cr), radius: cr,
                    startAngle: .pi, endAngle: .pi + quarter, clockwise: false)
        path.addLine(to: CGPoint(x: openingStartX, y: minY))

        let shape = SKShapeNode(path: path)
        shape.strokeColor = .white
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

    // gray barrier sealing the hole, opens only when the key is brought close
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

        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        if let sym = UIImage(systemName: "lock.fill", withConfiguration: cfg)?
            .withTintColor(gray, renderingMode: .alwaysOriginal) {
            let renderer = UIGraphicsImageRenderer(size: sym.size)
            let flat = renderer.image { _ in sym.draw(at: .zero) }
            let lock = SKSpriteNode(texture: SKTexture(image: flat))
            lock.position = CGPoint(x: hatchCenter.x, y: y + 14)
            hatch.addChild(lock)
        }

        let body = SKPhysicsBody(edgeFrom: CGPoint(x: startX, y: y),
                                 to: CGPoint(x: endX, y: y))
        body.categoryBitMask = Cat.ground
        hatch.physicsBody = body

        addChild(hatch)
        hatchNode = hatch
    }

    // zigzag of platforms up the right side spaced under the jump height, for debugging
    private func buildPlatforms() {
        platformsNode?.removeFromParent()

        let node = SKNode()
        node.zPosition = 5

        let keyY = keyPosition.y
        let width: CGFloat = 70
        var y = boxBottomY + 85
        var i = 0
        while y < keyY - 35 {
            let cx = i % 2 == 0 ? size.width - 75 : size.width - 185
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
            y += 85
            i += 1
        }

        addChild(node)
        platformsNode = node
    }

    private func addHeartKey() {
        heart?.removeFromParent()

        let key = SKNode()
        key.zPosition = 8

        let canvasSize = CGSize(width: 40, height: 70)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        let img = renderer.image { _ in
            UIColor.white.setFill()
            let cfg = UIImage.SymbolConfiguration(pointSize: 28, weight: .regular)
            if let sym = UIImage(systemName: "heart.fill", withConfiguration: cfg)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                sym.draw(in: CGRect(x: 20 - sym.size.width/2, y: 29 - sym.size.height/2,
                                    width: sym.size.width, height: sym.size.height))
            }
            UIBezierPath(roundedRect: CGRect(x: 17.5, y: 29, width: 5, height: 30), cornerRadius: 2.5).fill()
            UIBezierPath(roundedRect: CGRect(x: 22, y: 53, width: 7, height: 4), cornerRadius: 1).fill()
            UIBezierPath(roundedRect: CGRect(x: 22, y: 45, width: 5, height: 4), cornerRadius: 1).fill()
        }

        let sprite = SKSpriteNode(texture: SKTexture(image: img))
        key.addChild(sprite)
        key.zRotation = -.pi * 55 / 180
        key.position = keySpawnPosition

        let body = SKPhysicsBody(circleOfRadius: 20)
        body.isDynamic = false
        body.categoryBitMask = Cat.heart
        body.collisionBitMask = 0
        key.physicsBody = body

        addChild(key)
        heart = key
    }

    private func respawnCube() {
        let x = pendingEntryFrac.map { $0 * size.width } ?? boxMidX
        pendingEntryFrac = nil
        player.position = CGPoint(x: x, y: boxTopY - 40)
        player.physicsBody?.velocity = .zero
        hasFallenThrough = false
    }

    func setMove(_ direction: CGFloat) { moveDirection = direction }

    func jump() {
        guard jumpsRemaining > 0, let body = player?.physicsBody else { return }
        body.velocity.dy = 0
        body.applyImpulse(CGVector(dx: 0, dy: jumpSpeed * body.mass))
        jumpsRemaining -= 1
    }

    func enterFromTop(atXFraction frac: CGFloat) {
        pendingEntryFrac = frac
        if boxTopY > 0 { respawnCube() }
    }

    override func update(_ currentTime: TimeInterval) {
        guard let body = player?.physicsBody else { return }

        // catches any resize the events missed before a wrong frame can show
        if size != lastLayoutSize {
            relayout()
            respawnCube()
        }

        // look one frame ahead, cap velocity so the cube arrives flush at the wall
        // instead of penetrating and getting pushed back, which was the jitter
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

        // raycast under both bottom corners, grounding via contact events wont
        // work because the border is one body so wall contact keeps it alive
        if body.velocity.dy <= 1 {
            var grounded = false
            for ox in [-halfW + 1, halfW - 1] {
                let start = CGPoint(x: player.position.x + ox, y: player.position.y)
                let end = CGPoint(x: start.x, y: start.y - halfW - 5)
                physicsWorld.enumerateBodies(alongRayStart: start, end: end) { hit, _, _, stop in
                    if hit.categoryBitMask == Cat.ground {
                        grounded = true
                        stop.pointee = true
                    }
                }
                if grounded { break }
            }
            if grounded { jumpsRemaining = maxJumps }
        }

        // carrying the key close to the empty heart fills it, then the hatch releases
        if hasKey, !hatchUnlocked, let hatch = hatchNode {
            let dx = player.position.x - keyPosition.x
            let dy = player.position.y - keyPosition.y
            if dx * dx + dy * dy < 70 * 70 {
                hatchUnlocked = true
                fillHeartSlot()
                hatch.physicsBody = nil
                hatch.run(.sequence([.wait(forDuration: 0.35),
                                     .fadeOut(withDuration: 0.25),
                                     .removeFromParent()]))
                hatchNode = nil
            }
        }

        if !hasFallenThrough, player.position.y < boxBottomY - 30 {
            hasFallenThrough = true
            onFellThrough?(player.position.x / size.width)
        }
        if player.position.y < boxBottomY - 140 {
            respawnCube()
        }
    }

    // runs after the physics step so whatever we set here is what renders,
    // enforcing wall and arc constraints before any frame is drawn
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

        let arcTopY = boxBottomY + cornerR
        if player.position.y - halfW < arcTopY {
            constrainToCorner(center: CGPoint(x: size.width - edgeInset - cornerR, y: arcTopY),
                              cubeCorner: CGPoint(x: player.position.x + halfW,
                                                  y: player.position.y - halfW),
                              rightSide: true, body: body)
            constrainToCorner(center: CGPoint(x: edgeInset + cornerR, y: arcTopY),
                              cubeCorner: CGPoint(x: player.position.x - halfW,
                                                  y: player.position.y - halfW),
                              rightSide: false, body: body)
        }
    }

    // projects the cube back onto the arc and cancels only the outward velocity
    private func constrainToCorner(center: CGPoint, cubeCorner q: CGPoint,
                                   rightSide: Bool, body: SKPhysicsBody) {
        guard q.y < center.y, rightSide ? q.x > center.x : q.x < center.x else { return }
        let dx = q.x - center.x, dy = q.y - center.y
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > cornerR, dist > 0 else { return }

        let scale = cornerR / dist
        player.position.x += (center.x + dx * scale) - q.x
        player.position.y += (center.y + dy * scale) - q.y

        let nx = dx / dist, ny = dy / dist
        let vOut = body.velocity.dx * nx + body.velocity.dy * ny
        if vOut > 0 {
            body.velocity.dx -= vOut * nx
            body.velocity.dy -= vOut * ny
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
        default:
            break
        }
    }
}

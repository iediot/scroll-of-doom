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

    private enum Cat {
        static let player: UInt32 = 0x1 << 0
        static let ground: UInt32 = 0x1 << 1
        static let heart:  UInt32 = 0x1 << 2
        static let wings:  UInt32 = 0x1 << 3
    }

    var levelIndex = 0
    var isAdLevel = false
    var isBossLevel = false
    var adPowerup: Powerup = .doubleJump
    var extraJumps = 0
    var hasDash = false
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

    private var player: SKNode!
    private var squishBottom: SKNode!   // squishes scale from the cubes feet, purely visual
    private var eyes: [SKShapeNode] = []
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
        let restore = pendingRestore
        pendingRestore = nil
        hasKey = restore?.hasKey ?? false
        hatchUnlocked = restore?.hatchOpen ?? false
        bossDelivered = restore?.hatchOpen ?? false

        let cube = CGSize(width: modelSize, height: modelSize)
        player = SKNode()
        player.zPosition = 10
        player.physicsBody = makeBody()
        addChild(player)

        // one node that scales from the cubes feet, dropped a few px so the
        // model rests flush on the ground instead of floating above the hitbox
        squishBottom = SKNode()
        squishBottom.position = CGPoint(x: 0, y: -cube.height / 2 - 2)
        player.addChild(squishBottom)

        let visual = SKShapeNode(rect: CGRect(x: -cube.width / 2, y: 0,
                                              width: cube.width, height: cube.height),
                                 cornerRadius: 7)
        visual.fillColor = .white
        visual.strokeColor = .white
        visual.lineWidth = 1.5
        squishBottom.addChild(visual)

        eyes = []
        for ex in [-6.0, 6.0] {
            let eye = SKShapeNode(circleOfRadius: 3)
            eye.fillColor = .black
            eye.strokeColor = .clear
            eye.position = CGPoint(x: ex, y: cube.height / 2 + 4)
            squishBottom.addChild(eye)
            eyes.append(eye)
        }

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
        let line = SKShapeNode(path: path)
        line.strokeColor = .white
        line.lineWidth = 3
        line.lineCap = .round
        hatch.addChild(line)

        let body = SKPhysicsBody(edgeFrom: CGPoint(x: edgeInset, y: y),
                                 to: CGPoint(x: size.width - edgeInset, y: y))
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
        node.addChild(SKSpriteNode(texture: GameArt.powerupTexture(adPowerup)))
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

    private func placeCube(fracX: Double, fracY: Double) {
        player.position = CGPoint(x: CGFloat(fracX) * size.width,
                                  y: CGFloat(fracY) * size.height)
        player.physicsBody?.velocity = .zero
        player.physicsBody?.isDynamic = true
        player.isHidden = false
        hasFallenThrough = false
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
            UIColor.black.setFill()
            cg.fill(CGRect(origin: .zero, size: imgSize))

            cg.setLineCap(.round)

            // platforms
            cg.setStrokeColor(UIColor.white.cgColor)
            cg.setLineWidth(3 * scale)
            for node in platformsNode?.children ?? [] {
                guard let bb = (node as? SKShapeNode)?.path?.boundingBoxOfPath else { continue }
                cg.move(to: pt(CGPoint(x: bb.minX, y: bb.midY)))
                cg.addLine(to: pt(CGPoint(x: bb.maxX, y: bb.midY)))
            }
            cg.strokePath()

            // locked gate spans the floor
            if !hatchUnlocked {
                cg.setStrokeColor(UIColor.white.cgColor)
                cg.setLineWidth(3 * scale)
                cg.move(to: pt(CGPoint(x: 0, y: boxBottomY)))
                cg.addLine(to: pt(CGPoint(x: size.width, y: boxBottomY)))
                cg.strokePath()
            }

            // collectible item
            for node in [heart, wings].compactMap({ $0 }) {
                guard let sprite = node.children.first as? SKSpriteNode,
                      let cgImg = sprite.texture?.cgImage() else { continue }
                let sz = sprite.texture!.size()
                let c = pt(node.position)
                UIImage(cgImage: cgImg).draw(in: CGRect(x: c.x - sz.width * scale / 2,
                                                        y: c.y - sz.height * scale / 2,
                                                        width: sz.width * scale,
                                                        height: sz.height * scale))
            }

            // cube with its eyes
            let side = 30 * scale
            let c = pt(player.position)
            let cubeRect = CGRect(x: c.x - side / 2, y: c.y - side / 2, width: side, height: side)
            UIColor.white.setFill()
            UIBezierPath(roundedRect: cubeRect, cornerRadius: 7 * scale).fill()
            UIColor.black.setFill()
            for ex in [-6.0, 6.0] {
                let e = pt(CGPoint(x: player.position.x + ex, y: player.position.y + 4))
                cg.fillEllipse(in: CGRect(x: e.x - 3 * scale, y: e.y - 3 * scale,
                                          width: 6 * scale, height: 6 * scale))
            }
        }
    }


    func setMove(_ direction: CGFloat) {
        moveDirection = direction
        if direction != 0 { lastFacing = direction }
        lookEyes(direction)
    }

    // short horizontal burst toward the held or last faced direction
    func dash() {
        guard hasDash, sceneTime >= dashReadyTime else { return }
        dashDirection = moveDirection != 0 ? moveDirection : lastFacing
        dashEndTime = sceneTime + dashDuration
        dashReadyTime = sceneTime + dashCooldown
        dashSquish()
        lookEyes(dashDirection, amount: 3.5)
    }

    // eyes glance toward the direction of travel
    private func lookEyes(_ dir: CGFloat, amount: CGFloat = 2.2) {
        for (i, eye) in eyes.enumerated() {
            let baseX: CGFloat = i == 0 ? -6 : 6
            eye.run(.moveTo(x: baseX + dir * amount, duration: 0.1), withKey: "look")
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

        // raycast under the hitboxs bottom corners
        var grounded = false
        if body.velocity.dy <= 20 {
            let foot = hitW / 2 - 1
            for ox in [-foot, foot] {
                let start = CGPoint(x: player.position.x + ox, y: player.position.y)
                let end = CGPoint(x: start.x, y: start.y - modelSize / 2 - 6)
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

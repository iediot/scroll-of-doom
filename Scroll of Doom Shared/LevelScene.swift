import SpriteKit

/// A minimal, single-screen playable level: a white cube trapped inside a
/// white-bordered play box. Monochrome (white on black) aesthetic. Controls
/// live in SwiftUI (see LevelPageView) and drive the cube through
/// `setMove(_:)` and `jump()`.
final class LevelScene: SKScene {

    // MARK: - Tuning
    private let moveSpeed: CGFloat = 260
    private let jumpSpeed: CGFloat = 750
    private let maxJumps = 2

    /// Play-box insets, in scene points.
    private let boxSideInset: CGFloat = 16
    private let boxBottomInset: CGFloat = 170   // a bit above the bottom UI
    private let boxTopInset: CGFloat = 110       // clear of the notch / status area

    private enum Cat {
        static let player: UInt32 = 0x1 << 0
        static let ground: UInt32 = 0x1 << 1
    }

    // MARK: - Nodes / state
    private var player: SKShapeNode!
    private var boxBorder: SKShapeNode?
    private var boxBottomY: CGFloat = 0

    private var moveDirection: CGFloat = 0
    private var jumpsRemaining = 2

    // MARK: - Setup

    override func didMove(to view: SKView) {
        scaleMode = .resizeFill
        backgroundColor = .black
        physicsWorld.gravity = CGVector(dx: 0, dy: -18)
        physicsWorld.contactDelegate = self
        buildLevel()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard player != nil else { return }
        layoutBox()
    }

    private func buildLevel() {
        removeAllChildren()

        let cube = CGSize(width: 30, height: 30)
        player = SKShapeNode(rectOf: cube, cornerRadius: 7)
        player.fillColor = .white
        player.strokeColor = .white
        player.lineWidth = 1.5
        player.glowWidth = 0
        player.zPosition = 10

        let body = SKPhysicsBody(rectangleOf: CGSize(width: cube.width - 2, height: cube.height - 2))
        body.allowsRotation = false
        body.restitution = 0
        body.friction = 0
        body.linearDamping = 0
        body.categoryBitMask = Cat.player
        body.contactTestBitMask = Cat.ground
        body.collisionBitMask = Cat.ground
        player.physicsBody = body
        addChild(player)

        // Eyes (kept black on the white cube).
        for ex in [-6.0, 6.0] {
            let eye = SKShapeNode(circleOfRadius: 3)
            eye.fillColor = .black
            eye.strokeColor = .clear
            eye.position = CGPoint(x: ex, y: 4)
            player.addChild(eye)
        }

        layoutBox()
        // Drop the cube in from near the top of the box.
        player.position = CGPoint(x: size.width / 2, y: boxBottomY + 160)
        player.physicsBody?.velocity = .zero
    }

    /// (Re)builds the white play-box border + its containing physics edge loop
    /// to fit the current scene size.
    private func layoutBox() {
        boxBorder?.removeFromParent()

        let rect = CGRect(
            x: boxSideInset,
            y: boxBottomInset,
            width: size.width - boxSideInset * 2,
            height: size.height - boxTopInset - boxBottomInset
        )
        boxBottomY = rect.minY

        let border = SKShapeNode(rect: rect, cornerRadius: 12)
        border.strokeColor = .white
        border.lineWidth = 3
        border.fillColor = .clear
        border.zPosition = 5

        let body = SKPhysicsBody(edgeLoopFrom: rect)   // traps the cube on all sides
        body.categoryBitMask = Cat.ground
        border.physicsBody = body

        addChild(border)
        boxBorder = border
    }

    // MARK: - Public control API (called from the SwiftUI overlay)

    func setMove(_ direction: CGFloat) { moveDirection = direction }

    func jump() {
        guard jumpsRemaining > 0, let body = player?.physicsBody else { return }
        body.velocity.dy = 0
        body.applyImpulse(CGVector(dx: 0, dy: jumpSpeed * body.mass))
        jumpsRemaining -= 1
    }

    // MARK: - Loop

    override func update(_ currentTime: TimeInterval) {
        guard let body = player?.physicsBody else { return }
        body.velocity.dx = moveDirection * moveSpeed

        if player.position.y < boxBottomY - 80 {     // safety respawn
            player.position = CGPoint(x: size.width / 2, y: boxBottomY + 160)
            body.velocity = .zero
        }
    }
}

extension LevelScene: SKPhysicsContactDelegate {
    func didBegin(_ contact: SKPhysicsContact) {
        let onGround = contact.bodyA.categoryBitMask == Cat.ground
            || contact.bodyB.categoryBitMask == Cat.ground
        // Reset jumps only when landing near the box floor (not walls/ceiling).
        if onGround,
           abs(contact.contactNormal.dy) > 0.5,
           player.position.y < boxBottomY + 70 {
            jumpsRemaining = maxJumps
        }
    }
}

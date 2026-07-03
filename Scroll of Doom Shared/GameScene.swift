//
//  GameScene.swift
//  Shared SpriteKit scene for iOS + macOS
//
//  Infinite vertical tower climber:
//  - Endless procedural platforms, difficulty scales with height
//  - Spikes and falling = death -> game over screen -> tap/space to restart
//  - Run timer, height meter, coin counter
//  - Parallax starfield, glowing coins, rounded shapes
//  - iOS: joystick + jump button | macOS: arrows/WASD + space
//

import SpriteKit

// MARK: - Physics categories

struct PhysicsCategory {
    static let none:   UInt32 = 0
    static let player: UInt32 = 0x1 << 0
    static let ground: UInt32 = 0x1 << 1
    static let coin:   UInt32 = 0x1 << 2
    static let hazard: UInt32 = 0x1 << 3
}

class GameScene: SKScene {

    // MARK: - Tuning knobs

    private let moveSpeed: CGFloat = 260
    private let jumpSpeed: CGFloat = 750          // pts/s upward (tested & approved)
    private let gravityMS2: CGFloat = -18         // m/s^2
    private let maxJumps = 2
    private let cameraSmoothing: CGFloat = 4.5
    private let playerSize = CGSize(width: 24, height: 24)   // smaller cube

    // Difficulty scaling with height h (in points above spawn):
    private func platformWidth(atHeight h: CGFloat) -> ClosedRange<CGFloat> {
        let shrink = min(h / 60, 55)                    // narrows as you climb
        return (75 - shrink * 0.4)...(125 - shrink)     // ~75-125 early, ~53-70 high up
    }
    private func verticalGap(atHeight h: CGFloat) -> ClosedRange<CGFloat> {
        let grow = min(h / 80, 30)
        return (88 + grow * 0.5)...(100 + grow)         // 88-100 early, ~103-130 high up
    }
    private func spikeChance(atHeight h: CGFloat) -> Double {
        min(0.05 + Double(h) / 6000.0, 0.35)            // up to 35% of platforms
    }

    // MARK: - Nodes & state

    private var player: SKShapeNode!
    private var gameCamera: SKCameraNode!
    private var heightLabel: SKLabelNode!
    private var coinLabel: SKLabelNode!
    private var timeLabel: SKLabelNode!
    private var leftWall: SKSpriteNode!
    private var rightWall: SKSpriteNode!

    private var starLayerFar: SKNode!
    private var starLayerNear: SKNode!

    private var moveDirection: CGFloat = 0
    private var jumpsRemaining = 2
    private var lastUpdateTime: TimeInterval = 0

    private var runStartTime: TimeInterval = 0
    private var elapsedTime: TimeInterval = 0
    private var isGameOver = false

    private var highestGeneratedY: CGFloat = 0
    private var nextPlatformLeft = true
    private var worldNode: SKNode!                 // holds platforms/coins/spikes for easy cleanup

    #if os(iOS) || os(tvOS)
    private var joystickTouch: UITouch?
    private var jumpTouch: UITouch?
    #endif

    private var score = 0 {
        didSet { coinLabel?.text = "● \(score)" }
    }

    private var spawnPoint = CGPoint.zero
    private var bestHeight = 0

    // MARK: - Scene setup

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.05, green: 0.06, blue: 0.12, alpha: 1)
        physicsWorld.gravity = CGVector(dx: 0, dy: gravityMS2)
        physicsWorld.contactDelegate = self

        #if os(iOS) || os(tvOS)
        view.isMultipleTouchEnabled = true
        #endif

        spawnPoint = CGPoint(x: size.width / 2, y: 120)

        setupCamera()
        setupStars()
        setupWalls()
        setupHUD()

        #if os(iOS) || os(tvOS)
        setupTouchControls()
        #elseif os(macOS)
        view.window?.makeFirstResponder(self)
        #endif

        startRun()
    }

    // MARK: - Run lifecycle

    private func startRun() {
        isGameOver = false
        score = 0
        jumpsRemaining = maxJumps
        moveDirection = 0
        runStartTime = 0            // set on first update tick of the run
        elapsedTime = 0

        // Clear old world + game over UI
        worldNode?.removeFromParent()
        gameCamera.childNode(withName: "gameOverPanel")?.removeFromParent()

        worldNode = SKNode()
        addChild(worldNode)

        // Starting floor
        let floor = roundedBlock(size: CGSize(width: size.width - 60, height: 24),
                                 color: SKColor(red: 0.30, green: 0.33, blue: 0.42, alpha: 1))
        floor.position = CGPoint(x: size.width / 2, y: 80)
        floor.physicsBody = staticBody(size: CGSize(width: size.width - 60, height: 24),
                                       category: PhysicsCategory.ground)
        worldNode.addChild(floor)

        highestGeneratedY = 80
        nextPlatformLeft = true

        // Player
        player?.removeFromParent()
        setupPlayer()

        // Camera snap to start
        gameCamera.position = CGPoint(x: size.width / 2, y: spawnPoint.y + size.height * 0.2)

        // Pre-generate the first screenful
        generatePlatforms(upTo: size.height * 1.5)
    }

    private func gameOver(reason: String) {
        guard !isGameOver else { return }
        isGameOver = true
        moveDirection = 0
        player.physicsBody?.velocity = .zero

        let meters = Int(max(0, player.position.y - spawnPoint.y) / 10)
        bestHeight = max(bestHeight, meters)

        // Red flash
        let flash = SKSpriteNode(color: .systemRed, size: size)
        flash.zPosition = 150
        flash.alpha = 0.0
        gameCamera.addChild(flash)
        flash.run(.sequence([
            .fadeAlpha(to: 0.4, duration: 0.08),
            .fadeOut(withDuration: 0.3),
            .removeFromParent()
        ]))

        // Panel
        let panel = SKNode()
        panel.name = "gameOverPanel"
        panel.zPosition = 200
        gameCamera.addChild(panel)

        let dim = SKSpriteNode(color: SKColor(white: 0, alpha: 0.6), size: size)
        panel.addChild(dim)

        let title = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        title.text = reason
        title.fontSize = 42
        title.fontColor = .systemRed
        title.position = CGPoint(x: 0, y: 90)
        panel.addChild(title)

        let stats = SKLabelNode(fontNamed: "AvenirNext-Bold")
        stats.text = "\(meters) m   ●\(score)   \(formatTime(elapsedTime))"
        stats.fontSize = 24
        stats.fontColor = .white
        stats.position = CGPoint(x: 0, y: 40)
        panel.addChild(stats)

        let best = SKLabelNode(fontNamed: "AvenirNext-Medium")
        best.text = "BEST \(bestHeight) m"
        best.fontSize = 18
        best.fontColor = SKColor(white: 0.7, alpha: 1)
        best.position = CGPoint(x: 0, y: 8)
        panel.addChild(best)

        let retry = SKLabelNode(fontNamed: "AvenirNext-Bold")
        retry.text = "TAP TO RETRY"
        retry.fontSize = 22
        retry.fontColor = .systemGreen
        retry.position = CGPoint(x: 0, y: -50)
        panel.addChild(retry)
        retry.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.3, duration: 0.6),
            .fadeAlpha(to: 1.0, duration: 0.6)
        ])))
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let total = Int(t)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Player

    private func setupPlayer() {
        player = SKShapeNode(rectOf: playerSize, cornerRadius: 6)
        player.fillColor = .systemTeal
        player.strokeColor = SKColor(red: 0.6, green: 0.95, blue: 1.0, alpha: 1)
        player.lineWidth = 1.5
        player.glowWidth = 2
        player.position = spawnPoint

        // Little eyes for character
        for ex in [-5.0, 5.0] {
            let eye = SKShapeNode(circleOfRadius: 2.5)
            eye.fillColor = SKColor(white: 0.1, alpha: 1)
            eye.strokeColor = .clear
            eye.position = CGPoint(x: ex, y: 3)
            player.addChild(eye)
        }

        let body = SKPhysicsBody(rectangleOf: CGSize(width: playerSize.width - 2,
                                                     height: playerSize.height - 2))
        body.allowsRotation = false
        body.restitution = 0
        body.friction = 0
        body.linearDamping = 0
        body.categoryBitMask = PhysicsCategory.player
        body.contactTestBitMask = PhysicsCategory.ground | PhysicsCategory.coin | PhysicsCategory.hazard
        body.collisionBitMask = PhysicsCategory.ground
        player.physicsBody = body
        player.zPosition = 10
        addChild(player)
    }

    // MARK: - Infinite generation

    private func generatePlatforms(upTo targetY: CGFloat) {
        var rng = SystemRandomNumberGenerator()
        let w = size.width

        while highestGeneratedY < targetY {
            let h = max(0, highestGeneratedY - spawnPoint.y)
            let gap = CGFloat.random(in: verticalGap(atHeight: h), using: &rng)
            let width = CGFloat.random(in: platformWidth(atHeight: h), using: &rng)
            let y = highestGeneratedY + gap

            let xRange: ClosedRange<CGFloat> = nextPlatformLeft
                ? (45 + width / 2)...(w * 0.46)
                : (w * 0.54)...(w - 45 - width / 2)
            let x = CGFloat.random(in: xRange, using: &rng)

            let hasSpikes = Double.random(in: 0...1, using: &rng) < spikeChance(atHeight: h)
            addPlatform(x: x, y: y, width: width, withSpikes: hasSpikes, rng: &rng)

            if !hasSpikes, Bool.random(using: &rng) {
                addCoin(x: x, y: y + 42)
            }

            highestGeneratedY = y
            nextPlatformLeft.toggle()
        }

        // Cull anything far below the camera
        let cullY = gameCamera.position.y - size.height
        for node in worldNode.children where node.position.y < cullY {
            node.removeFromParent()
        }
    }

    private func addPlatform(x: CGFloat, y: CGFloat, width: CGFloat,
                             withSpikes: Bool, rng: inout SystemRandomNumberGenerator) {
        let platform = roundedBlock(size: CGSize(width: width, height: 14),
                                    color: SKColor(red: 0.42, green: 0.36, blue: 0.55, alpha: 1))
        platform.position = CGPoint(x: x, y: y)
        platform.physicsBody = staticBody(size: CGSize(width: width, height: 14),
                                          category: PhysicsCategory.ground)
        worldNode.addChild(platform)

        if withSpikes {
            // Spikes cover one random half of the platform; the other half stays safe
            let spikeWidth = width * 0.5
            let offset = (Bool.random(using: &rng) ? 1 : -1) * width * 0.25
            addSpikes(x: x + offset, y: y + 7, width: spikeWidth)
        }
    }

    private func roundedBlock(size: CGSize, color: SKColor) -> SKShapeNode {
        let block = SKShapeNode(rectOf: size, cornerRadius: 5)
        block.fillColor = color
        block.strokeColor = color.mixed(with: .white, fraction: 0.35)
        block.lineWidth = 1
        block.zPosition = 5
        return block
    }

    private func addCoin(x: CGFloat, y: CGFloat) {
        let coin = SKShapeNode(circleOfRadius: 8)
        coin.fillColor = .systemYellow
        coin.strokeColor = SKColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 1)
        coin.lineWidth = 1.5
        coin.glowWidth = 4
        coin.position = CGPoint(x: x, y: y)
        let body = SKPhysicsBody(circleOfRadius: 8)
        body.isDynamic = false
        body.categoryBitMask = PhysicsCategory.coin
        body.collisionBitMask = PhysicsCategory.none
        coin.physicsBody = body
        coin.zPosition = 8
        coin.run(.repeatForever(.sequence([
            .scaleX(to: 0.25, duration: 0.45),
            .scaleX(to: 1.0, duration: 0.45)
        ])))
        worldNode.addChild(coin)
    }

    private func addSpikes(x: CGFloat, y: CGFloat, width: CGFloat) {
        let spikeW: CGFloat = 12
        let spikeH: CGFloat = 15
        let count = max(2, Int(width / spikeW))

        let path = CGMutablePath()
        for i in 0..<count {
            let ox = CGFloat(i) * spikeW - CGFloat(count) * spikeW / 2
            path.move(to: CGPoint(x: ox, y: 0))
            path.addLine(to: CGPoint(x: ox + spikeW / 2, y: spikeH))
            path.addLine(to: CGPoint(x: ox + spikeW, y: 0))
        }
        path.closeSubpath()

        let spikes = SKShapeNode(path: path)
        spikes.fillColor = SKColor(red: 0.95, green: 0.25, blue: 0.3, alpha: 1)
        spikes.strokeColor = SKColor(red: 1.0, green: 0.5, blue: 0.55, alpha: 1)
        spikes.lineWidth = 1
        spikes.glowWidth = 1.5
        spikes.position = CGPoint(x: x, y: y)
        let body = SKPhysicsBody(rectangleOf: CGSize(width: CGFloat(count) * spikeW, height: spikeH - 4),
                                 center: CGPoint(x: 0, y: spikeH / 2))
        body.isDynamic = false
        body.categoryBitMask = PhysicsCategory.hazard
        body.collisionBitMask = PhysicsCategory.none
        spikes.physicsBody = body
        spikes.zPosition = 6
        worldNode.addChild(spikes)
    }

    private func staticBody(size: CGSize, category: UInt32) -> SKPhysicsBody {
        let body = SKPhysicsBody(rectangleOf: size)
        body.isDynamic = false
        body.restitution = 0
        body.friction = 0
        body.categoryBitMask = category
        return body
    }

    // MARK: - Walls, stars, camera, HUD

    private func setupWalls() {
        let wallColor = SKColor(red: 0.16, green: 0.18, blue: 0.26, alpha: 1)
        let wallSize = CGSize(width: 20, height: size.height * 2.5)

        leftWall = SKSpriteNode(color: wallColor, size: wallSize)
        rightWall = SKSpriteNode(color: wallColor, size: wallSize)
        leftWall.position = CGPoint(x: 10, y: 0)
        rightWall.position = CGPoint(x: size.width - 10, y: 0)

        for wall in [leftWall!, rightWall!] {
            wall.physicsBody = staticBody(size: wallSize, category: PhysicsCategory.ground)
            wall.zPosition = 7
            addChild(wall)
        }
    }

    private func setupStars() {
        starLayerFar = SKNode()
        starLayerNear = SKNode()
        starLayerFar.zPosition = 1
        starLayerNear.zPosition = 2
        addChild(starLayerFar)
        addChild(starLayerNear)

        var rng = SystemRandomNumberGenerator()
        for layer in [starLayerFar!, starLayerNear!] {
            let isNear = layer === starLayerNear
            for _ in 0..<40 {
                let star = SKShapeNode(circleOfRadius: isNear ? 1.6 : 0.9)
                star.fillColor = SKColor(white: 1, alpha: isNear ? 0.5 : 0.28)
                star.strokeColor = .clear
                star.position = CGPoint(
                    x: CGFloat.random(in: 0...size.width, using: &rng),
                    y: CGFloat.random(in: 0...(size.height * 2), using: &rng)
                )
                layer.addChild(star)
            }
        }
    }

    private func updateStars() {
        // Parallax: layers track the camera at a fraction of its speed,
        // and stars wrap vertically so the field is endless.
        let camY = gameCamera.position.y
        starLayerFar.position.y = camY * 0.85 - size.height * 0.4
        starLayerNear.position.y = camY * 0.7 - size.height * 0.3

        for layer in [starLayerFar!, starLayerNear!] {
            let layerCamY = camY - layer.position.y
            for star in layer.children {
                if star.position.y < layerCamY - size.height * 0.6 {
                    star.position.y += size.height * 2
                } else if star.position.y > layerCamY + size.height * 1.4 {
                    star.position.y -= size.height * 2
                }
            }
        }
    }

    private func setupCamera() {
        gameCamera = SKCameraNode()
        gameCamera.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(gameCamera)
        camera = gameCamera
    }

    private func setupHUD() {
        coinLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
        coinLabel.text = "● 0"
        coinLabel.fontSize = 18
        coinLabel.fontColor = .systemYellow
        coinLabel.horizontalAlignmentMode = .left
        coinLabel.position = CGPoint(x: -size.width / 2 + 22, y: size.height / 2 - 44)
        coinLabel.zPosition = 100
        gameCamera.addChild(coinLabel)

        heightLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
        heightLabel.text = "0 m"
        heightLabel.fontSize = 18
        heightLabel.fontColor = .white
        heightLabel.horizontalAlignmentMode = .center
        heightLabel.position = CGPoint(x: 0, y: size.height / 2 - 44)
        heightLabel.zPosition = 100
        gameCamera.addChild(heightLabel)

        timeLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
        timeLabel.text = "0:00"
        timeLabel.fontSize = 18
        timeLabel.fontColor = SKColor(white: 0.8, alpha: 1)
        timeLabel.horizontalAlignmentMode = .right
        timeLabel.position = CGPoint(x: size.width / 2 - 22, y: size.height / 2 - 44)
        timeLabel.zPosition = 100
        gameCamera.addChild(timeLabel)
    }

    // MARK: - Jumping

    private func pressJump() {
        guard !isGameOver, jumpsRemaining > 0 else { return }
        if let body = player.physicsBody {
            body.velocity.dy = 0
            body.applyImpulse(CGVector(dx: 0, dy: jumpSpeed * body.mass))
        }
        jumpsRemaining -= 1
    }

    // MARK: - Frame update

    override func update(_ time: TimeInterval) {
        let dt: CGFloat
        if lastUpdateTime > 0 {
            dt = CGFloat(min(time - lastUpdateTime, 1.0 / 30.0))
        } else {
            dt = 1.0 / 60.0
        }
        lastUpdateTime = time

        guard !isGameOver, let body = player.physicsBody else { return }

        // Run timer
        if runStartTime == 0 { runStartTime = time }
        elapsedTime = time - runStartTime
        timeLabel.text = formatTime(elapsedTime)

        // Horizontal movement
        body.velocity.dx = moveDirection * moveSpeed

        // Fell below the visible area -> death
        if player.position.y < gameCamera.position.y - size.height / 2 - 60 {
            gameOver(reason: "YOU FELL!")
            return
        }

        // Height meter
        let meters = Int(max(0, player.position.y - spawnPoint.y) / 10)
        heightLabel.text = "\(meters) m"

        // Camera follows upward (never scrolls back down past a bit below the player)
        let targetY = player.position.y + size.height * 0.12
        let t = 1 - exp(-cameraSmoothing * dt)
        var newY = gameCamera.position.y + (targetY - gameCamera.position.y) * t
        newY = max(size.height / 2, newY)
        gameCamera.position.y = newY
        gameCamera.position.x = size.width / 2

        // Walls follow the camera so the tower is endless
        leftWall.position.y = newY
        rightWall.position.y = newY

        updateStars()

        // Keep generating ahead of the camera
        generatePlatforms(upTo: newY + size.height * 1.2)
    }
}

// MARK: - Contacts

extension GameScene: SKPhysicsContactDelegate {

    func didBegin(_ contact: SKPhysicsContact) {
        guard !isGameOver else { return }
        let other = otherBody(in: contact)

        switch other.categoryBitMask {
        case PhysicsCategory.ground:
            if abs(contact.contactNormal.dy) > 0.7 {
                jumpsRemaining = maxJumps
            }

        case PhysicsCategory.coin:
            score += 1
            other.node?.run(.sequence([
                .group([.scale(to: 1.8, duration: 0.12), .fadeOut(withDuration: 0.12)]),
                .removeFromParent()
            ]))

        case PhysicsCategory.hazard:
            gameOver(reason: "SPIKED!")

        default:
            break
        }
    }

    private func otherBody(in contact: SKPhysicsContact) -> SKPhysicsBody {
        contact.bodyA.categoryBitMask == PhysicsCategory.player ? contact.bodyB : contact.bodyA
    }
}

// MARK: - Shared restart handling

extension GameScene {
    fileprivate func handleRestartInput() -> Bool {
        if isGameOver {
            startRun()
            return true
        }
        return false
    }
}

// MARK: - iOS: Virtual joystick + jump button

#if os(iOS) || os(tvOS)
import UIKit

extension GameScene {

    private struct ControlTag {
        static let joystickBase = "joystickBase"
        static let joystickKnob = "joystickKnob"
        static let jumpButton = "jumpButton"
    }

    func setupTouchControls() {
        let margin: CGFloat = 85
        let halfW = size.width / 2
        let halfH = size.height / 2

        let base = SKShapeNode(circleOfRadius: 46)
        base.name = ControlTag.joystickBase
        base.strokeColor = SKColor(white: 1, alpha: 0.5)
        base.lineWidth = 2
        base.position = CGPoint(x: -halfW + margin, y: -halfH + margin)
        base.zPosition = 100
        gameCamera.addChild(base)

        let knob = SKShapeNode(circleOfRadius: 20)
        knob.name = ControlTag.joystickKnob
        knob.fillColor = SKColor(white: 1, alpha: 0.6)
        knob.strokeColor = .clear
        knob.position = base.position
        knob.zPosition = 101
        gameCamera.addChild(knob)

        let jumpButton = SKShapeNode(circleOfRadius: 46)
        jumpButton.name = ControlTag.jumpButton
        jumpButton.strokeColor = SKColor(white: 1, alpha: 0.5)
        jumpButton.lineWidth = 2
        jumpButton.position = CGPoint(x: halfW - margin, y: -halfH + margin)
        jumpButton.zPosition = 100
        gameCamera.addChild(jumpButton)

        let jumpLabel = SKLabelNode(text: "JUMP")
        jumpLabel.fontName = "AvenirNext-Bold"
        jumpLabel.fontSize = 14
        jumpLabel.fontColor = SKColor(white: 1, alpha: 0.7)
        jumpLabel.verticalAlignmentMode = .center
        jumpLabel.position = jumpButton.position
        jumpLabel.zPosition = 101
        gameCamera.addChild(jumpLabel)
    }

    private var joystickBase: SKShapeNode? { gameCamera.childNode(withName: ControlTag.joystickBase) as? SKShapeNode }
    private var joystickKnob: SKShapeNode? { gameCamera.childNode(withName: ControlTag.joystickKnob) as? SKShapeNode }
    private var jumpButtonNode: SKShapeNode? { gameCamera.childNode(withName: ControlTag.jumpButton) as? SKShapeNode }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if handleRestartInput() { return }

        for touch in touches {
            guard let base = joystickBase, let jumpBtn = jumpButtonNode else { continue }
            let loc = touch.location(in: gameCamera)

            let joyDist = hypot(loc.x - base.position.x, loc.y - base.position.y)
            let jumpDist = hypot(loc.x - jumpBtn.position.x, loc.y - jumpBtn.position.y)

            if joyDist < 80, joystickTouch == nil {
                joystickTouch = touch
                updateJoystick(for: touch)
            } else if jumpDist < 65, jumpTouch == nil {
                jumpTouch = touch
                pressJump()
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches where touch == joystickTouch {
            updateJoystick(for: touch)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { endTouch(touch) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { endTouch(touch) }
    }

    private func updateJoystick(for touch: UITouch) {
        guard let base = joystickBase, let knob = joystickKnob else { return }
        let loc = touch.location(in: gameCamera)
        let dx = loc.x - base.position.x
        let dy = loc.y - base.position.y
        let distance = min(hypot(dx, dy), 46)
        let angle = atan2(dy, dx)
        knob.position = CGPoint(x: base.position.x + cos(angle) * distance,
                                y: base.position.y + sin(angle) * distance)
        moveDirection = max(-1, min(1, dx / 46))
    }

    private func endTouch(_ touch: UITouch) {
        if touch == joystickTouch {
            joystickTouch = nil
            moveDirection = 0
            joystickKnob?.position = joystickBase?.position ?? .zero
        }
        if touch == jumpTouch {
            jumpTouch = nil
        }
    }
}

// MARK: - macOS: Keyboard

#elseif os(macOS)
import AppKit

extension GameScene {

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard !event.isARepeat else { return }

        if isGameOver {
            _ = handleRestartInput()
            return
        }

        switch event.keyCode {
        case 123, 0:  moveDirection = -1   // Left arrow, A
        case 124, 2:  moveDirection = 1    // Right arrow, D
        case 49, 126, 13: pressJump()      // Space, Up arrow, W
        default: break
        }
    }

    override func keyUp(with event: NSEvent) {
        switch event.keyCode {
        case 123, 0:
            if moveDirection < 0 { moveDirection = 0 }
        case 124, 2:
            if moveDirection > 0 { moveDirection = 0 }
        default: break
        }
    }
}
#endif

// MARK: - Small helpers

private extension SKColor {
    /// Linear mix between two colors (cross-platform, no NSColor name clash).
    func mixed(with color: SKColor, fraction: CGFloat) -> SKColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        #if os(macOS)
        let c1 = usingColorSpace(.deviceRGB) ?? self
        let c2 = color.usingColorSpace(.deviceRGB) ?? color
        c1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        c2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        #else
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        color.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        #endif
        return SKColor(red: r1 + (r2 - r1) * fraction,
                       green: g1 + (g2 - g1) * fraction,
                       blue: b1 + (b2 - b1) * fraction,
                       alpha: a1 + (a2 - a1) * fraction)
    }
}

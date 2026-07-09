import SpriteKit
import UIKit

// every powerup lives here, new ones get a case and an icon
enum Powerup: String, Codable, CaseIterable {
    case doubleJump
    case dash
}

// all placeholder art in one spot, swap for real textures later
enum GameArt {

    static func heartTexture(filled: Bool) -> SKTexture {
        symbolTexture(filled ? "heart.fill" : "heart",
                      pointSize: 28,
                      canvas: CGSize(width: 40, height: 40),
                      color: .white)
    }

    static func lockTexture() -> SKTexture? {
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        guard let sym = UIImage(systemName: "lock.fill", withConfiguration: cfg)?
            .withTintColor(UIColor(white: 0.45, alpha: 1), renderingMode: .alwaysOriginal)
        else { return nil }
        let renderer = UIGraphicsImageRenderer(size: sym.size)
        let flat = renderer.image { _ in sym.draw(at: .zero) }
        return SKTexture(image: flat)
    }

    static func powerupTexture(_ p: Powerup) -> SKTexture {
        SKTexture(image: icon(for: p))
    }

    // the boss counterpart of the heart
    static func brokenHeartTexture() -> SKTexture {
        symbolTexture("heart.slash.fill",
                      pointSize: 28,
                      canvas: CGSize(width: 40, height: 40),
                      color: .white)
    }

    static func icon(for powerup: Powerup) -> UIImage {
        switch powerup {
        case .doubleJump: return wingsImage()
        case .dash: return dashImage()
        }
    }

    // three staggered right triangles matching the tab bar dash icon
    static func dashImage() -> UIImage {
        let canvas = CGSize(width: 52, height: 34)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        return renderer.image { ctx in
            // back arrow
            UIColor.white.setFill()
            roundedRightTriangle(center: CGPoint(x: 26 + 7, y: 17),
                                 base: 25, cornerRadius: 5).fill()
            // carve the gap out of the back arrow only, so it shows whatever is behind
            ctx.cgContext.setBlendMode(.clear)
            roundedRightTriangle(center: CGPoint(x: 26, y: 17),
                                 base: 25, cornerRadius: 5).fill()
            ctx.cgContext.setBlendMode(.normal)
            // front arrow on top, untouched by the cut
            UIColor.white.setFill()
            roundedRightTriangle(center: CGPoint(x: 26 - 7, y: 17),
                                 base: 25, cornerRadius: 5).fill()
        }
    }

    private static func roundedRightTriangle(center: CGPoint, base: CGFloat,
                                             cornerRadius r: CGFloat) -> UIBezierPath {
        let h = base * sqrt(3) / 2
        let pts = [CGPoint(x: center.x + h / 2, y: center.y),
                   CGPoint(x: center.x - h / 2, y: center.y + base / 2),
                   CGPoint(x: center.x - h / 2, y: center.y - base / 2)]
        func unit(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            let dx = b.x - a.x, dy = b.y - a.y
            let len = max(hypot(dx, dy), 0.0001)
            return CGPoint(x: dx / len, y: dy / len)
        }
        let path = UIBezierPath()
        for i in 0..<3 {
            let curr = pts[i], prev = pts[(i + 2) % 3], next = pts[(i + 1) % 3]
            let tp = unit(curr, prev), tn = unit(curr, next)
            let s = CGPoint(x: curr.x + tp.x * r, y: curr.y + tp.y * r)
            let e = CGPoint(x: curr.x + tn.x * r, y: curr.y + tn.y * r)
            if i == 0 { path.move(to: s) } else { path.addLine(to: s) }
            path.addQuadCurve(to: e, controlPoint: curr)
        }
        path.close()
        return path
    }

    static func wingsImage() -> UIImage {
        let canvasSize = CGSize(width: 60, height: 36)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        return renderer.image { ctx in
            UIColor.white.setFill()
            let wing = UIBezierPath()
            wing.move(to: CGPoint(x: 31, y: 28))
            wing.addQuadCurve(to: CGPoint(x: 56, y: 6), controlPoint: CGPoint(x: 38, y: 4))
            wing.addQuadCurve(to: CGPoint(x: 46, y: 21), controlPoint: CGPoint(x: 53, y: 15))
            wing.addQuadCurve(to: CGPoint(x: 38, y: 26), controlPoint: CGPoint(x: 43, y: 25))
            wing.addQuadCurve(to: CGPoint(x: 31, y: 28), controlPoint: CGPoint(x: 34, y: 28))
            wing.close()
            wing.fill()

            ctx.cgContext.saveGState()
            ctx.cgContext.translateBy(x: canvasSize.width, y: 0)
            ctx.cgContext.scaleBy(x: -1, y: 1)
            wing.fill()
            ctx.cgContext.restoreGState()
        }
    }

    private static func symbolTexture(_ name: String, pointSize: CGFloat,
                                      canvas: CGSize, color: UIColor) -> SKTexture {
        SKTexture(image: symbolImage(name, pointSize: pointSize, canvas: canvas, color: color))
    }

    private static func symbolImage(_ name: String, pointSize: CGFloat,
                                    canvas: CGSize, color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        return renderer.image { _ in
            let cfg = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            if let sym = UIImage(systemName: name, withConfiguration: cfg)?
                .withTintColor(color, renderingMode: .alwaysOriginal) {
                sym.draw(in: CGRect(x: canvas.width / 2 - sym.size.width / 2,
                                    y: canvas.height / 2 - sym.size.height / 2,
                                    width: sym.size.width, height: sym.size.height))
            }
        }
    }
}

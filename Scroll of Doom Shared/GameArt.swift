import SpriteKit
import UIKit

// every powerup lives here, new ones get a case and an icon
enum Powerup: String, Codable, CaseIterable {
    case doubleJump
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

    static func wingsTexture() -> SKTexture {
        SKTexture(image: wingsImage())
    }

    static func icon(for powerup: Powerup) -> UIImage {
        switch powerup {
        case .doubleJump: return wingsImage()
        }
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
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        let img = renderer.image { _ in
            let cfg = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            if let sym = UIImage(systemName: name, withConfiguration: cfg)?
                .withTintColor(color, renderingMode: .alwaysOriginal) {
                sym.draw(in: CGRect(x: canvas.width / 2 - sym.size.width / 2,
                                    y: canvas.height / 2 - sym.size.height / 2,
                                    width: sym.size.width, height: sym.size.height))
            }
        }
        return SKTexture(image: img)
    }
}

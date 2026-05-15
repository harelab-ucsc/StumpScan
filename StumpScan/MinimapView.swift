import UIKit
import simd

final class MinimapView: UIView {

    private var cameraTransform: simd_float4x4 = matrix_identity_float4x4
    private var anchors: [Int: TagAnchor] = [:]
    private var activeIDs: Set<Int> = []

    // Minimum half-span in metres (so the map doesn't zoom in absurdly)
    private let minHalfSpan: Float = 2.0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(cameraTransform: simd_float4x4, anchors: [Int: TagAnchor], activeIDs: Set<Int>) {
        self.cameraTransform = cameraTransform
        self.anchors = anchors
        self.activeIDs = activeIDs
        setNeedsDisplay()
    }

    // MARK: Drawing

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        let camXZ = SIMD2<Float>(cameraTransform.columns.3.x, cameraTransform.columns.3.z)
        let center = CGPoint(x: rect.midX, y: rect.midY)

        // Scale to fit all tag anchors, with a minimum span
        var halfSpan = minHalfSpan
        for anchor in anchors.values {
            let dx = abs(anchor.worldPosition.x - camXZ.x)
            let dz = abs(anchor.worldPosition.z - camXZ.y)
            halfSpan = max(halfSpan, dx * 1.3, dz * 1.3)
        }
        let scale = Float(min(rect.width, rect.height) * 0.5 - 14) / halfSpan

        // Background
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.72).cgColor)
        UIBezierPath(roundedRect: rect, cornerRadius: 12).fill()

        // Range rings
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.1).cgColor)
        ctx.setLineWidth(0.5)
        for m: Float in [1, 2, 3, 5, 8, 10, 15] {
            let r = CGFloat(m * scale)
            guard r < rect.width else { break }
            ctx.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        }

        // North line (world -Z = up on the map)
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.08).cgColor)
        ctx.move(to: CGPoint(x: center.x, y: rect.minY))
        ctx.addLine(to: CGPoint(x: center.x, y: rect.maxY))
        ctx.move(to: CGPoint(x: rect.minX, y: center.y))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: center.y))
        ctx.strokePath()

        // Clip to rounded rect for dots/arrows
        ctx.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: 12).addClip()

        // Tag dots
        for (id, anchor) in anchors {
            let worldXZ = SIMD2<Float>(anchor.worldPosition.x, anchor.worldPosition.z)
            let pt = toScreen(worldXZ, camXZ: camXZ, scale: scale, center: center)
            let isActive = activeIDs.contains(id)
            let color: UIColor = isActive ? .systemGreen : .systemBlue
            let r: CGFloat = isActive ? 5 : 4

            ctx.setFillColor(color.withAlphaComponent(isActive ? 1 : 0.75).cgColor)
            ctx.fillEllipse(in: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2))

            ("\(id)" as NSString).draw(
                at: CGPoint(x: pt.x + r + 2, y: pt.y - 6),
                withAttributes: [.foregroundColor: color,
                                 .font: UIFont.boldSystemFont(ofSize: 9)]
            )
        }

        // Camera arrow
        drawCamera(ctx: ctx, at: center)

        ctx.restoreGState()

        // Scale bar  (1 m)
        let barLen = CGFloat(1 * scale)
        let barY = rect.maxY - 9
        let barX = rect.minX + 10
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.45).cgColor)
        ctx.setLineWidth(1.5)
        ctx.move(to: CGPoint(x: barX, y: barY))
        ctx.addLine(to: CGPoint(x: barX + barLen, y: barY))
        ctx.strokePath()
        ("1m" as NSString).draw(
            at: CGPoint(x: barX + barLen + 3, y: barY - 7),
            withAttributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.45),
                             .font: UIFont.systemFont(ofSize: 8)]
        )

        // Border
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.2).cgColor)
        ctx.setLineWidth(1)
        UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 12).stroke()
    }

    // MARK: Helpers

    // World XZ → minimap screen point (camera always at center)
    private func toScreen(_ worldXZ: SIMD2<Float>, camXZ: SIMD2<Float>,
                          scale: Float, center: CGPoint) -> CGPoint {
        CGPoint(
            x: center.x + CGFloat((worldXZ.x - camXZ.x) * scale),
            y: center.y + CGFloat((worldXZ.y - camXZ.y) * scale)  // world +Z = screen down
        )
    }

    private func drawCamera(ctx: CGContext, at center: CGPoint) {
        // Forward vector projected to XZ. ARKit camera looks in -Z of its local space.
        let fwdX = -cameraTransform.columns.2.x
        let fwdZ = -cameraTransform.columns.2.z
        // Angle from screen-up (world -Z direction is "north"/up on the map).
        let heading = CGFloat(atan2f(fwdX, -fwdZ))

        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: heading)

        // Arrow shape pointing upward before rotation
        let s: CGFloat = 9
        let arrow = UIBezierPath()
        arrow.move(to:     CGPoint(x:  0,       y: -s * 1.4))   // tip
        arrow.addLine(to:  CGPoint(x: -s * 0.7, y:  s * 0.6))
        arrow.addLine(to:  CGPoint(x:  0,       y:  s * 0.2))   // tail notch
        arrow.addLine(to:  CGPoint(x:  s * 0.7, y:  s * 0.6))
        arrow.close()

        UIColor.systemYellow.setFill()
        UIColor.black.withAlphaComponent(0.4).setStroke()
        arrow.lineWidth = 0.75
        arrow.fill()
        arrow.stroke()

        ctx.restoreGState()
    }
}

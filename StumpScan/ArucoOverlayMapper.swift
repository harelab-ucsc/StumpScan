import CoreGraphics

struct ArucoOverlayMapper {
    static func viewPoint(
        for imagePoint: CGPoint,
        imageSize: CGSize,
        viewportSize: CGSize,
        transform: CGAffineTransform
    ) -> CGPoint {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }

        let normalizedPoint = CGPoint(
            x: imagePoint.x / imageSize.width,
            y: imagePoint.y / imageSize.height
        ).applying(transform)

        return CGPoint(
            x: normalizedPoint.x * viewportSize.width,
            y: normalizedPoint.y * viewportSize.height
        )
    }

    static func labelFrame(
        anchoredAt point: CGPoint,
        viewportSize: CGSize,
        labelSize: CGSize = CGSize(width: 56, height: 22),
        verticalOffset: CGFloat = 24
    ) -> CGRect {
        CGRect(
            x: min(max(0, point.x), max(0, viewportSize.width - labelSize.width)),
            y: min(max(0, point.y - verticalOffset), max(0, viewportSize.height - labelSize.height)),
            width: labelSize.width,
            height: labelSize.height
        )
    }
}

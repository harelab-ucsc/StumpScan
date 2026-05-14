import CoreGraphics
import CoreVideo
import Testing
@testable import StumpScan

@Suite("ArUco detection")
struct ArucoDetectorTests {
    @Test("Image points map into viewport coordinates")
    func imagePointMappingUsesNormalizedDisplayTransform() {
        let mappedPoint = ArucoOverlayMapper.viewPoint(
            for: CGPoint(x: 320, y: 120),
            imageSize: CGSize(width: 640, height: 480),
            viewportSize: CGSize(width: 200, height: 100),
            transform: .identity
        )

        #expect(mappedPoint == CGPoint(x: 100, y: 25))
    }

    @Test("Marker labels stay inside the viewport")
    func labelFrameIsClampedInsideViewport() {
        let topLeftFrame = ArucoOverlayMapper.labelFrame(
            anchoredAt: CGPoint(x: -20, y: 3),
            viewportSize: CGSize(width: 120, height: 80)
        )

        let bottomRightFrame = ArucoOverlayMapper.labelFrame(
            anchoredAt: CGPoint(x: 140, y: 120),
            viewportSize: CGSize(width: 120, height: 80)
        )

        #expect(topLeftFrame.origin == .zero)
        #expect(bottomRightFrame.maxX <= 120)
        #expect(bottomRightFrame.maxY <= 80)
    }

    @Test("Detector handles a blank camera buffer")
    func detectorHandlesBlankPixelBuffer() throws {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            64,
            64,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            nil,
            &pixelBuffer
        )

        #expect(status == kCVReturnSuccess)

        let buffer = try #require(pixelBuffer)
        let detections = OpenCVArucoTagDetector().detect(in: buffer)

        #expect(detections.isEmpty)
    }
}

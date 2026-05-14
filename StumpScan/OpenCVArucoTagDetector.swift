import CoreGraphics
import CoreVideo
import Foundation
import ObjectiveC.runtime
import UIKit

struct OpenCVArucoTagDetector: ArucoTagDetector {
    static let unavailableMessage = "OpenCV ArUco backend is not linked. Add an iOS OpenCV build that includes the aruco module, make opencv2/aruco.hpp visible to the target, and link the OpenCV framework/library."

    var isAvailable: Bool {
        guard let detectorClass = detectorClass else { return false }

        let selector = NSSelectorFromString("hasOpenCVArucoSupport")
        guard let method = class_getClassMethod(detectorClass, selector) else { return false }

        typealias AvailabilityFunction = @convention(c) (AnyClass, Selector) -> Bool
        let implementation = method_getImplementation(method)
        let hasSupport = unsafeBitCast(implementation, to: AvailabilityFunction.self)
        return hasSupport(detectorClass, selector)
    }

    func validateConfiguration() {
        precondition(isAvailable, Self.unavailableMessage)
    }

    func detect(in pixelBuffer: CVPixelBuffer, dictionary: TagDictionary) -> [ArucoTag] {
        guard let detectorClass else {
            preconditionFailure(Self.unavailableMessage)
        }

        let selector = NSSelectorFromString("detectMarkersInPixelBuffer:dictionary:")
        guard let method = class_getClassMethod(detectorClass, selector) else {
            preconditionFailure(Self.unavailableMessage)
        }

        typealias DetectMarkersFunction = @convention(c) (AnyClass, Selector, CVPixelBuffer, Int) -> NSArray
        let implementation = method_getImplementation(method)
        let detectMarkers = unsafeBitCast(implementation, to: DetectMarkersFunction.self)
        let markerObjects = detectMarkers(detectorClass, selector, pixelBuffer, dictionary.objcValue)

        let imageSize = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )

        return markerObjects.compactMap { markerObject in
            guard let marker = markerObject as? NSObject else { return nil }
            guard let identifier = marker.value(forKey: "identifier") as? Int else { return nil }
            guard let cornerValues = marker.value(forKey: "corners") as? [NSValue] else { return nil }

            return ArucoTag(
                id: identifier,
                corners: cornerValues.map { $0.cgPointValue },
                imageSize: imageSize
            )
        }
    }

    private var detectorClass: AnyClass? {
        NSClassFromString("ArucoMarkerDetector")
    }
}

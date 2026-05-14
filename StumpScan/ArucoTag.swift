import CoreGraphics
import CoreVideo

struct ArucoTag: Identifiable {
    let id: Int
    let corners: [CGPoint]
    let imageSize: CGSize
}

enum TagDictionary: CaseIterable {
    case aruco4x4
    case aruco5x5
    case aruco6x6
    case aruco7x7
    case aprilTag16h5
    case aprilTag25h9
    case aprilTag36h10
    case aprilTag36h11

    var mode: DetectionMode {
        switch self {
        case .aruco4x4, .aruco5x5, .aruco6x6, .aruco7x7: .aruco
        case .aprilTag16h5, .aprilTag25h9, .aprilTag36h10, .aprilTag36h11: .aprilTag
        }
    }

    var tickLabel: String {
        switch self {
        case .aruco4x4:       "4×4"
        case .aruco5x5:       "5×5"
        case .aruco6x6:       "6×6"
        case .aruco7x7:       "7×7"
        case .aprilTag16h5:   "16h5"
        case .aprilTag25h9:   "25h9"
        case .aprilTag36h10:  "36h10"
        case .aprilTag36h11:  "36h11"
        }
    }

    // Int value passed to the ObjC layer (matches ArucoMarkerDictionary enum)
    var objcValue: Int {
        switch self {
        case .aruco4x4:       0
        case .aruco5x5:       1
        case .aruco6x6:       2
        case .aruco7x7:       3
        case .aprilTag16h5:   4
        case .aprilTag25h9:   5
        case .aprilTag36h10:  6
        case .aprilTag36h11:  7
        }
    }
}

enum DetectionMode: CaseIterable {
    case aruco
    case aprilTag

    var displayName: String {
        switch self {
        case .aruco:    "ArUco"
        case .aprilTag: "AprilTag"
        }
    }

    var toggled: DetectionMode {
        switch self {
        case .aruco:    .aprilTag
        case .aprilTag: .aruco
        }
    }

    // Four options per mode; slider index maps 1:1 so position is preserved on toggle
    var dictionaries: [TagDictionary] {
        switch self {
        case .aruco:    [.aruco4x4, .aruco5x5, .aruco6x6, .aruco7x7]
        case .aprilTag: [.aprilTag16h5, .aprilTag25h9, .aprilTag36h10, .aprilTag36h11]
        }
    }

    var promptText: String {
        switch self {
        case .aruco:    "Point camera at an ArUco tag"
        case .aprilTag: "Point camera at an AprilTag"
        }
    }

    func detectionText(count: Int) -> String {
        switch self {
        case .aruco:    count == 1 ? "1 ArUco tag detected"   : "\(count) ArUco tags detected"
        case .aprilTag: count == 1 ? "1 AprilTag detected"    : "\(count) AprilTags detected"
        }
    }
}

protocol ArucoTagDetector: Sendable {
    var isAvailable: Bool { get }

    func validateConfiguration()
    func detect(in pixelBuffer: CVPixelBuffer, dictionary: TagDictionary) -> [ArucoTag]
}

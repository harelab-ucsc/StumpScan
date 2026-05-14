#import "ArucoMarkerDetector.h"
#import <UIKit/UIKit.h>

#if __has_include(<opencv2/objdetect/aruco_detector.hpp>) && __has_include(<opencv2/core.hpp>)
#import <opencv2/objdetect/aruco_detector.hpp>
#import <opencv2/core.hpp>
#import <opencv2/imgproc.hpp>
#define STUMPSCAN_HAS_OPENCV_ARUCO 1
#elif __has_include(<opencv2/aruco.hpp>) && __has_include(<opencv2/core.hpp>)
#import <opencv2/aruco.hpp>
#import <opencv2/core.hpp>
#import <opencv2/imgproc.hpp>
#define STUMPSCAN_HAS_OPENCV_ARUCO 1
#define STUMPSCAN_OPENCV_LEGACY_ARUCO 1
#else
#define STUMPSCAN_HAS_OPENCV_ARUCO 0
#endif

@implementation ArucoMarkerDetection

- (instancetype)initWithIdentifier:(NSInteger)identifier corners:(NSArray<NSValue *> *)corners {
    self = [super init];
    if (self) {
        _identifier = identifier;
        _corners = [corners copy];
    }
    return self;
}

@end

@implementation ArucoMarkerDetector

+ (BOOL)hasOpenCVArucoSupport {
#if STUMPSCAN_HAS_OPENCV_ARUCO
    return YES;
#else
    return NO;
#endif
}

+ (NSArray<ArucoMarkerDetection *> *)detectMarkersInPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                                     dictionary:(ArucoMarkerDictionary)dictionary {
#if STUMPSCAN_HAS_OPENCV_ARUCO
    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);

    const size_t width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0);
    const size_t height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0);
    const size_t bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
    void *baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);

    cv::aruco::PredefinedDictionaryType dictionaryType;
    switch (dictionary) {
        case ArucoMarkerDictionaryArUco5x5_50:   dictionaryType = cv::aruco::DICT_5X5_50;         break;
        case ArucoMarkerDictionaryArUco6x6_50:   dictionaryType = cv::aruco::DICT_6X6_50;         break;
        case ArucoMarkerDictionaryArUco7x7_50:   dictionaryType = cv::aruco::DICT_7X7_50;         break;
        case ArucoMarkerDictionaryAprilTag16h5:  dictionaryType = cv::aruco::DICT_APRILTAG_16h5;  break;
        case ArucoMarkerDictionaryAprilTag25h9:  dictionaryType = cv::aruco::DICT_APRILTAG_25h9;  break;
        case ArucoMarkerDictionaryAprilTag36h10: dictionaryType = cv::aruco::DICT_APRILTAG_36h10; break;
        case ArucoMarkerDictionaryAprilTag36h11: dictionaryType = cv::aruco::DICT_APRILTAG_36h11; break;
        default:                                 dictionaryType = cv::aruco::DICT_4X4_50;         break;
    }

    cv::Mat grayImage((int)height, (int)width, CV_8UC1, baseAddress, bytesPerRow);
    std::vector<int> ids;
    std::vector<std::vector<cv::Point2f>> markerCorners;

#ifdef STUMPSCAN_OPENCV_LEGACY_ARUCO
    cv::Ptr<cv::aruco::Dictionary> dict = cv::aruco::getPredefinedDictionary(dictionaryType);
    cv::aruco::detectMarkers(grayImage, dict, markerCorners, ids);
#else
    cv::aruco::ArucoDetector detector(cv::aruco::getPredefinedDictionary(dictionaryType));
    detector.detectMarkers(grayImage, markerCorners, ids);
#endif

    NSMutableArray<ArucoMarkerDetection *> *detections = [NSMutableArray arrayWithCapacity:ids.size()];
    for (size_t markerIndex = 0; markerIndex < ids.size(); markerIndex += 1) {
        NSMutableArray<NSValue *> *corners = [NSMutableArray arrayWithCapacity:4];
        for (const cv::Point2f &corner : markerCorners[markerIndex]) {
            [corners addObject:[NSValue valueWithCGPoint:CGPointMake(corner.x, corner.y)]];
        }

        ArucoMarkerDetection *detection = [[ArucoMarkerDetection alloc] initWithIdentifier:ids[markerIndex] corners:corners];
        [detections addObject:detection];
    }

    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    return detections;
#else
    return @[];
#endif
}

@end

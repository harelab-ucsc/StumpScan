#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ArucoMarkerDictionary) {
    ArucoMarkerDictionaryArUco4x4_50    = 0,
    ArucoMarkerDictionaryArUco5x5_50    = 1,
    ArucoMarkerDictionaryArUco6x6_50    = 2,
    ArucoMarkerDictionaryArUco7x7_50    = 3,
    ArucoMarkerDictionaryAprilTag16h5   = 4,
    ArucoMarkerDictionaryAprilTag25h9   = 5,
    ArucoMarkerDictionaryAprilTag36h10  = 6,
    ArucoMarkerDictionaryAprilTag36h11  = 7,
};

@interface ArucoMarkerDetection: NSObject

@property (nonatomic, assign, readonly) NSInteger identifier;
@property (nonatomic, copy, readonly) NSArray<NSValue *> *corners;

- (instancetype)initWithIdentifier:(NSInteger)identifier corners:(NSArray<NSValue *> *)corners;

@end

@interface ArucoMarkerDetector: NSObject

+ (BOOL)hasOpenCVArucoSupport;
+ (NSArray<ArucoMarkerDetection *> *)detectMarkersInPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                                     dictionary:(ArucoMarkerDictionary)dictionary
    NS_SWIFT_NAME(detectMarkers(in:dictionary:));

@end

NS_ASSUME_NONNULL_END

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ARFRecordingConfig : NSObject

@property(nonatomic) BOOL recordImu;
@property(nonatomic) BOOL recordDepth;
@property(nonatomic) BOOL recordPointCloud;
@property(nonatomic) BOOL recordMesh;
@property(nonatomic) BOOL recordRgb;
@property(nonatomic) NSInteger rgbHz;
@property(nonatomic) NSInteger depthHz;
@property(nonatomic) NSInteger pointCloudHz;
@property(nonatomic) NSInteger imuHz;
/// Target landscape short side for RGB: 720 or 1080 (720p / 1080p).
@property(nonatomic) NSInteger rgbVideoHeight;
@property(nonatomic) BOOL autoFocus;
/// When NO, exposure is locked once it settles so brightness stays constant.
@property(nonatomic) BOOL autoExposure;
@property(nonatomic) NSInteger arkitFps;
@property(nonatomic) BOOL enableInertialDerived;

- (instancetype)init;

@end

@interface ARFRecorderResult : NSObject

@property(nonatomic) BOOL success;
@property(nonatomic) BOOL supported;
@property(nonatomic, copy) NSString *state;
@property(nonatomic, copy) NSString *trackingState;
@property(nonatomic, copy) NSString *errorMessage;
@property(nonatomic, copy) NSString *outputDirectory;
@property(nonatomic, copy) NSString *cameraResolution;
@property(nonatomic, copy) NSString *recordingResolution;
@property(nonatomic, copy) NSString *lowQualityReason;
@property(nonatomic) BOOL depthSupported;
@property(nonatomic) BOOL meshSupported;
@property(nonatomic) BOOL isRecording;
@property(nonatomic) BOOL isPaused;
@property(nonatomic) BOOL isFinalizationInProgress;
@property(nonatomic) BOOL isLowQualityMode;
@property(nonatomic) long long textureId;
@property(nonatomic) long long frameCount;
@property(nonatomic) long long previewWidth;
@property(nonatomic) long long previewHeight;
@property(nonatomic) long long recordingDurationMs;
@property(nonatomic) double durationSeconds;
@property(nonatomic) long long framesRecorded;
@property(nonatomic) long long imuSamples;
@property(nonatomic) long long recordingHz;

- (instancetype)init;

@end

@interface ARRecorderInterop : NSObject

+ (instancetype)sharedInterop;
- (ARFRecorderResult *)startRecordingWithConfig:(ARFRecordingConfig *)config;
- (ARFRecorderResult *)pauseRecording;
- (ARFRecorderResult *)resumeRecording;
- (ARFRecorderResult *)cancelRecording;
- (ARFRecorderResult *)stopRecording;
- (ARFRecorderResult *)getRecordingState;
- (ARFRecorderResult *)checkArAvailability;

@end

NS_ASSUME_NONNULL_END

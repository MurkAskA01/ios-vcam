#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreVideo/CoreVideo.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^AVAssetFrameCallback)(UIImage *frame);
typedef void (^AVAssetPixelBufferCallback)(CVPixelBufferRef buffer);
typedef void (^AVAssetErrorCallback)(NSError *error);

@interface AVAssetStreamAdapter : NSObject <NSURLSessionDataDelegate>

@property (nonatomic, strong, readonly) NSURL *streamURL;
@property (nonatomic, assign, readonly) BOOL isConnecting;
@property (nonatomic, assign, readonly) NSUInteger frameCount;
@property (nonatomic, assign, readonly) CFAbsoluteTime lastFrameTime;

@property (nonatomic, copy, nullable) AVAssetFrameCallback frameCallback;
@property (nonatomic, copy, nullable) AVAssetPixelBufferCallback pixelBufferCallback;
@property (nonatomic, copy, nullable) AVAssetErrorCallback errorCallback;

- (instancetype)initWithURL:(NSURL *)url;
- (void)startStreaming;
- (void)stopStreaming;

@end

NS_ASSUME_NONNULL_END


#import "AVAssetStreamAdapter.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <ImageIO/ImageIO.h>
#import <MobileCoreServices/MobileCoreServices.h>

#ifdef DEBUG_MODE
    #define StreamLog(fmt, ...) NSLog((@"[Stream] " fmt), ##__VA_ARGS__)
#else
    #define StreamLog(...)
#endif

@interface AVAssetStreamAdapter ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionDataTask *task;
@property (nonatomic, strong) NSMutableData *imageData;
@property (nonatomic, assign) BOOL isRunning;

@property (nonatomic, strong) AVPlayer *hlsPlayer;
@property (nonatomic, strong) AVPlayerItem *hlsPlayerItem;
@property (nonatomic, strong) AVPlayerItemVideoOutput *videoOutput;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) BOOL isHLS;

@property (nonatomic, assign, readwrite) BOOL isConnecting;
@end

@implementation AVAssetStreamAdapter

- (instancetype)initWithURL:(NSURL *)url {
    self = [super init];
    if (self) {
        _streamURL = url;
        _isConnecting = NO;
        _frameCount = 0;
        _lastFrameTime = 0;

        NSString *urlString = url.absoluteString.lowercaseString;
        _isHLS = [urlString hasSuffix:@".m3u8"] || [urlString containsString:@".m3u8"];

        StreamLog(@"Initialized with URL: %@", url);
    }
    return self;
}

- (void)startStreaming {
    if (_isRunning) {
        StreamLog(@"Already streaming");
        return;
    }

    _isRunning = YES;
    _isConnecting = YES;
    StreamLog(@"Starting stream...");

    if (_isHLS) {
        [self startHLSStream];
    } else {
        [self startMJPEGStream];
    }
}

- (void)stopStreaming {
    StreamLog(@"Stopping stream...");
    _isRunning = NO;
    _isConnecting = NO;

    if (_isHLS) {
        [self stopHLSStream];
    } else {
        [self stopMJPEGStream];
    }
}

- (void)startHLSStream {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.hlsPlayerItem = [AVPlayerItem playerItemWithURL:self.streamURL];
        self.hlsPlayer = [AVPlayer playerWithPlayerItem:self.hlsPlayerItem];
        self.hlsPlayer.automaticallyWaitsToMinimizeStalling = NO;
        self.hlsPlayer.muted = YES;

        NSDictionary *pixelBufferAttributes = @{
            (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
            (id)kCVPixelBufferIOSurfacePropertiesKey: @{}
        };

        self.videoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:pixelBufferAttributes];
        [self.hlsPlayerItem addOutput:self.videoOutput];
        [self.hlsPlayer play];

        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLinkCallback:)];
        self.displayLink.preferredFramesPerSecond = 30;
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

        self.isConnecting = NO;
        StreamLog(@"HLS stream started");

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(playerItemDidReachEnd:)
                                                     name:AVPlayerItemDidPlayToEndTimeNotification
                                                   object:self.hlsPlayerItem];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(playerItemFailed:)
                                                     name:AVPlayerItemFailedToPlayToEndTimeNotification
                                                   object:self.hlsPlayerItem];
    });
}

- (void)displayLinkCallback:(CADisplayLink *)sender {
    if (!self.isRunning) return;

    CMTime currentTime = [self.hlsPlayer currentTime];
    if (![self.videoOutput hasNewPixelBufferForItemTime:currentTime]) return;

    CVPixelBufferRef pixelBuffer = [self.videoOutput copyPixelBufferForItemTime:currentTime itemTimeForDisplay:nil];
    if (!pixelBuffer) return;

    self->_frameCount++;
    self->_lastFrameTime = CFAbsoluteTimeGetCurrent();

    if (self.pixelBufferCallback) {
        self.pixelBufferCallback(pixelBuffer);
        CVPixelBufferRelease(pixelBuffer);
        return;
    }

    if (self.frameCallback) {
        CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
        CIContext *context = [CIContext contextWithOptions:nil];
        CGImageRef cgImage = [context createCGImage:ciImage fromRect:ciImage.extent];
        UIImage *image = cgImage ? [UIImage imageWithCGImage:cgImage] : nil;
        if (cgImage) CGImageRelease(cgImage);
        CVPixelBufferRelease(pixelBuffer);

        if (image) {
            self.frameCallback(image);
        }
    } else {
        CVPixelBufferRelease(pixelBuffer);
    }
}

- (void)playerItemDidReachEnd:(NSNotification *)notification {
    StreamLog(@"Stream ended, restarting...");
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.hlsPlayer seekToTime:kCMTimeZero];
        [self.hlsPlayer play];
    });
}

- (void)playerItemFailed:(NSNotification *)notification {
    StreamLog(@"Stream failed, restarting in 2s");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (!self.isRunning) return;
        [self stopHLSStream];
        [self startHLSStream];
    });
}

- (void)stopHLSStream {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        [self.displayLink invalidate];
        self.displayLink = nil;
        [self.hlsPlayer pause];
        self.hlsPlayer = nil;
        self.hlsPlayerItem = nil;
        self.videoOutput = nil;
    });
}

- (void)startMJPEGStream {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 30.0;
    config.timeoutIntervalForResource = 300.0;
    config.HTTPMaximumConnectionsPerHost = 1;

    self.session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
    self.imageData = [NSMutableData data];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.streamURL];
    [request setValue:@"multipart/x-mixed-replace" forHTTPHeaderField:@"Accept"];

    self.task = [self.session dataTaskWithRequest:request];
    [self.task resume];

    StreamLog(@"MJPEG stream started");
}

- (void)stopMJPEGStream {
    [self.task cancel];
    self.task = nil;
    [self.session invalidateAndCancel];
    self.session = nil;
    self.imageData = nil;
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    self.isConnecting = NO;
    StreamLog(@"Connection established");
    completionHandler(NSURLSessionResponseAllow);
}

- (CVPixelBufferRef)pixelBufferFromJPEGData:(NSData *)jpegData CF_RETURNS_RETAINED {
    CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)jpegData, NULL);
    if (!imageSource) return NULL;

    CGImageRef cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, NULL);
    CFRelease(imageSource);
    if (!cgImage) return NULL;

    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);

    NSDictionary *options = @{
        (id)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (id)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES,
        (id)kCVPixelBufferIOSurfacePropertiesKey: @{}
    };

    CVPixelBufferRef pixelBuffer = NULL;
    if (CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                            (__bridge CFDictionaryRef)options, &pixelBuffer) != kCVReturnSuccess || !pixelBuffer) {
        CGImageRelease(cgImage);
        return NULL;
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8, bytesPerRow, colorSpace,
                                                 kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(colorSpace);

    if (context) {
        CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);
        CGContextRelease(context);
    }

    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    CGImageRelease(cgImage);

    return pixelBuffer;
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
    if (!self.isRunning) return;

    [self.imageData appendData:data];

    NSData *startMarker = [NSData dataWithBytes:(unsigned char[]){0xFF, 0xD8} length:2];
    NSData *endMarker = [NSData dataWithBytes:(unsigned char[]){0xFF, 0xD9} length:2];

    NSRange startRange = [self.imageData rangeOfData:startMarker options:0
                                               range:NSMakeRange(0, self.imageData.length)];
    NSRange endRange = [self.imageData rangeOfData:endMarker options:0
                                             range:NSMakeRange(0, self.imageData.length)];

    if (startRange.location != NSNotFound && endRange.location != NSNotFound &&
        endRange.location > startRange.location) {

        NSRange imageRange = NSMakeRange(startRange.location,
                                         endRange.location + endMarker.length - startRange.location);
        NSData *jpegData = [self.imageData subdataWithRange:imageRange];

        if (self.pixelBufferCallback) {
            CVPixelBufferRef pixelBuffer = [self pixelBufferFromJPEGData:jpegData];
            if (pixelBuffer) {
                self->_frameCount++;
                self->_lastFrameTime = CFAbsoluteTimeGetCurrent();
                self.pixelBufferCallback(pixelBuffer);
                CVPixelBufferRelease(pixelBuffer);
            }
        }
        else if (self.frameCallback) {
            UIImage *image = [UIImage imageWithData:jpegData];
            if (image) {
                self->_frameCount++;
                self->_lastFrameTime = CFAbsoluteTimeGetCurrent();
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.frameCallback(image);
                });
            }
        }

        [self.imageData replaceBytesInRange:NSMakeRange(0, endRange.location + endMarker.length)
                                  withBytes:NULL length:0];
    }

    if (self.imageData.length > 10 * 1024 * 1024) {
        [self.imageData setLength:0];
        StreamLog(@"Buffer overflow, cleared");
    }
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    if (error) {
        StreamLog(@"Connection error: %@", error.localizedDescription);

        if (self.errorCallback) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.errorCallback(error);
            });
        }

        if (self.isRunning) {
            StreamLog(@"Reconnecting in 3s...");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                if (self.isRunning) {
                    [self startMJPEGStream];
                }
            });
        }
    } else {
        StreamLog(@"Stream ended normally");
    }
}

- (void)dealloc {
    [self stopStreaming];
}


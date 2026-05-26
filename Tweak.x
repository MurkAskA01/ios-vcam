#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "AVAssetStreamAdapter.h"

// Debug logging - disabled in production
#ifdef DEBUG_MODE
    #define AVFLog(fmt, ...) NSLog((@"[AVF] " fmt), ##__VA_ARGS__)
#else
    #define AVFLog(...)
#endif

static BOOL _cms_active = YES;
static NSString *_cms_source = @"http://192.168.1.44:8888/live/stream/index.m3u8";
static AVAssetStreamAdapter *_cms_adapter = nil;
static CVPixelBufferRef _cms_currentFrame = NULL;
static id _cms_syncObj = nil;
static NSMutableDictionary<NSString *, NSValue *> *_cms_methodCache = nil;

@interface AVFDisplayLinkTarget : NSObject
@property (nonatomic, weak) AVCaptureVideoPreviewLayer *previewLayer;
- (void)updateFrame:(CADisplayLink *)link;
@end

@implementation AVFDisplayLinkTarget
- (void)updateFrame:(CADisplayLink *)link {
    AVCaptureVideoPreviewLayer *layer = self.previewLayer;
    if (!layer) { [link invalidate]; return; }
    
    CALayer *overlayLayer = objc_getAssociatedObject(layer, "_cms_ol");
    if (!overlayLayer) return;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    overlayLayer.frame = layer.bounds;

    CVPixelBufferRef frame = NULL;
    @synchronized(_cms_syncObj) {
        if (_cms_currentFrame) frame = CVPixelBufferRetain(_cms_currentFrame);
    }

    if (frame) {
        IOSurfaceRef surface = CVPixelBufferGetIOSurface(frame);
        if (surface) {
            overlayLayer.contents = (__bridge id)surface;
            overlayLayer.hidden = NO;
            for (CALayer *sub in layer.sublayers) {
                if (sub != overlayLayer) sub.hidden = YES;
            }
        }
        CVPixelBufferRelease(frame);
    } else {
        overlayLayer.hidden = YES;
        for (CALayer *sub in layer.sublayers) {
            if (sub != overlayLayer) sub.hidden = NO;
        }
    }
    [CATransaction commit];
}
@end

static void _cms_initialize(void) {
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        if (!_cms_syncObj) _cms_syncObj = [NSObject new];
        if (!_cms_methodCache) _cms_methodCache = [NSMutableDictionary new];

        NSURL *streamURL = [NSURL URLWithString:_cms_source];
        if (!streamURL) {
            AVFLog(@"Invalid stream URL");
            return;
        }

        _cms_adapter = [[AVAssetStreamAdapter alloc] initWithURL:streamURL];
        _cms_adapter.pixelBufferCallback = ^(CVPixelBufferRef buffer) {
            if (!buffer) return;
            @synchronized(_cms_syncObj) {
                if (_cms_currentFrame) CVPixelBufferRelease(_cms_currentFrame);
                _cms_currentFrame = CVPixelBufferRetain(buffer);
            }
        };
        [_cms_adapter startStreaming];
        AVFLog(@"Stream adapter initialized");
    });
}

static CMSampleBufferRef _cms_createSampleBuffer(CMSampleBufferRef original) {
    CVPixelBufferRef pixelBuffer = NULL;
    @synchronized(_cms_syncObj) {
        if (_cms_currentFrame) pixelBuffer = CVPixelBufferRetain(_cms_currentFrame);
    }
    if (!pixelBuffer) return NULL;

    CMVideoFormatDescriptionRef formatDesc = NULL;
    if (CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, &formatDesc) != noErr || !formatDesc) {
        CVPixelBufferRelease(pixelBuffer);
        return NULL;
    }

    CMSampleTimingInfo timing;
    if (original) {
        if (CMSampleBufferGetSampleTimingInfo(original, 0, &timing) != noErr) {
            timing.duration = CMTimeMake(1, 30);
            timing.presentationTimeStamp = CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000);
            timing.decodeTimeStamp = kCMTimeInvalid;
        }
    } else {
        timing.duration = CMTimeMake(1, 30);
        timing.presentationTimeStamp = CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000);
        timing.decodeTimeStamp = kCMTimeInvalid;
    }

    CMSampleBufferRef sampleBuffer = NULL;
    OSStatus status = CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault, pixelBuffer, formatDesc, &timing, &sampleBuffer);
    CFRelease(formatDesc);
    CVPixelBufferRelease(pixelBuffer);
    return (status == noErr) ? sampleBuffer : NULL;
}

%hook AVCaptureVideoDataOutput

- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate
                          queue:(dispatch_queue_t)queue {
    if (!_cms_active || !delegate) {
        %orig;
        return;
    }
    _cms_initialize();

    Class delegateClass = object_getClass(delegate);
    NSString *className = NSStringFromClass(delegateClass);
    SEL selector = @selector(captureOutput:didOutputSampleBuffer:fromConnection:);

    @synchronized(_cms_methodCache) {
        if (!_cms_methodCache[className]) {
            Method method = class_getInstanceMethod(delegateClass, selector);
            if (method) {
                const char *typeEncoding = method_getTypeEncoding(method);
                IMP originalIMP = method_getImplementation(method);
                _cms_methodCache[className] = [NSValue valueWithPointer:originalIMP];

                __block NSString *cachedClassName = className;
                IMP replacementIMP = imp_implementationWithBlock(^(id target,
                                                                   AVCaptureOutput *output,
                                                                   CMSampleBufferRef sampleBuffer,
                                                                   AVCaptureConnection *connection) {
                    CMSampleBufferRef modifiedBuffer = NULL;
                    if (_cms_active) modifiedBuffer = _cms_createSampleBuffer(sampleBuffer);
                    CMSampleBufferRef finalBuffer = modifiedBuffer ? modifiedBuffer : sampleBuffer;

                    IMP cachedIMP = NULL;
                    @synchronized(_cms_methodCache) {
                        NSValue *impValue = _cms_methodCache[cachedClassName];
                        if (impValue) cachedIMP = (IMP)[impValue pointerValue];
                    }
                    if (cachedIMP) {
                        ((void(*)(id, SEL, AVCaptureOutput *, CMSampleBufferRef, AVCaptureConnection *))cachedIMP)
                            (target, selector, output, finalBuffer, connection);
                    }
                    if (modifiedBuffer) CFRelease(modifiedBuffer);
                });

                BOOL methodAdded = class_addMethod(delegateClass, selector, replacementIMP, typeEncoding);
                if (!methodAdded) {
                    method_setImplementation(method, replacementIMP);
                }
                AVFLog(@"Delegate intercepted: %@", className);
            }
        }
    }
    %orig;
}

%end

%hook AVSampleBufferDisplayLayer

- (void)enqueueSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    if (!_cms_active) { %orig; return; }
    _cms_initialize();

    CMSampleBufferRef modifiedBuffer = _cms_createSampleBuffer(sampleBuffer);
    if (modifiedBuffer) {
        %orig(modifiedBuffer);
        CFRelease(modifiedBuffer);
        return;
    }
    %orig(sampleBuffer);
}

%end

%hook NSObject

- (void)captureOutput:(AVCapturePhotoOutput *)output
        didFinishProcessingPhotoSampleBuffer:(CMSampleBufferRef)photoSampleBuffer
        previewPhotoSampleBuffer:(CMSampleBufferRef)previewSampleBuffer
        resolvedSettings:(AVCaptureResolvedPhotoSettings *)resolvedSettings
        bracketSettings:(AVCaptureBracketedStillImageSettings *)bracketSettings
        error:(NSError *)error {
    if (!_cms_active || error) { %orig; return; }

    CMSampleBufferRef modifiedPhoto = _cms_createSampleBuffer(photoSampleBuffer);
    CMSampleBufferRef modifiedPreview = _cms_createSampleBuffer(previewSampleBuffer);

    if (modifiedPhoto || modifiedPreview) {
        AVFLog(@"Photo capture intercepted");
        %orig(output,
              modifiedPhoto ? modifiedPhoto : photoSampleBuffer,
              modifiedPreview ? modifiedPreview : previewSampleBuffer,
              resolvedSettings,
              bracketSettings,
              error);
        if (modifiedPhoto) CFRelease(modifiedPhoto);
        if (modifiedPreview) CFRelease(modifiedPreview);
        return;
    }
    %orig;
}

%end

%hook AVCapturePhoto

- (CVPixelBufferRef)pixelBuffer {
    @synchronized(_cms_syncObj) {
        if (_cms_active && _cms_currentFrame) {
            AVFLog(@"Photo pixelBuffer replaced");
            return (CVPixelBufferRef)CFRetain(_cms_currentFrame);
        }
    }
    return %orig;
}

- (CVPixelBufferRef)previewPixelBuffer {
    @synchronized(_cms_syncObj) {
        if (_cms_active && _cms_currentFrame) {
            return (CVPixelBufferRef)CFRetain(_cms_currentFrame);
        }
    }
    return %orig;
}

- (CGImageRef)CGImageRepresentation {
    @synchronized(_cms_syncObj) {
        if (_cms_active && _cms_currentFrame) {
            CIImage *ciImage = [CIImage imageWithCVPixelBuffer:_cms_currentFrame];
            CIContext *context = [CIContext contextWithOptions:nil];
            CGImageRef cgImage = [context createCGImage:ciImage fromRect:ciImage.extent];
            if (cgImage) {
                AVFLog(@"CGImageRepresentation replaced");
                return cgImage;
            }
        }
    }
    return %orig;
}

- (NSData *)fileDataRepresentation {
    @synchronized(_cms_syncObj) {
        if (_cms_active && _cms_currentFrame) {
            CIImage *ciImage = [CIImage imageWithCVPixelBuffer:_cms_currentFrame];
            CIContext *context = [CIContext contextWithOptions:nil];
            CGImageRef cgImage = [context createCGImage:ciImage fromRect:ciImage.extent];
            if (!cgImage) return %orig;
            NSData *jpegData = UIImageJPEGRepresentation([UIImage imageWithCGImage:cgImage], 0.9);
            CGImageRelease(cgImage);
            AVFLog(@"File data replaced (%lu bytes)", (unsigned long)jpegData.length);
            return jpegData;
        }
    }
    return %orig;
}

%end

%hook AVCaptureVideoPreviewLayer

- (void)layoutSublayers {
    %orig;
    if (!_cms_active) return;
    _cms_initialize();

    CALayer *overlayLayer = objc_getAssociatedObject(self, "_cms_ol");
    if (!overlayLayer) {
        overlayLayer = [CALayer layer];
        overlayLayer.contentsGravity = kCAGravityResizeAspectFill;
        overlayLayer.zPosition = 999999;
        overlayLayer.backgroundColor = [UIColor clearColor].CGColor;
        overlayLayer.opaque = NO;
        overlayLayer.hidden = YES;
        [self addSublayer:overlayLayer];
        objc_setAssociatedObject(self, "_cms_ol", overlayLayer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        AVFDisplayLinkTarget *target = [AVFDisplayLinkTarget new];
        target.previewLayer = self;
        CADisplayLink *displayLink = [CADisplayLink displayLinkWithTarget:target selector:@selector(updateFrame:)];
        displayLink.preferredFramesPerSecond = 30;
        [displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        
        objc_setAssociatedObject(self, "_cms_dlt", target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, "_cms_dl", displayLink, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        AVFLog(@"Preview layer initialized");
    }
}

%end

%hook AVCaptureDevice

+ (AVCaptureDevice *)defaultDeviceWithMediaType:(AVMediaType)mediaType {
    if (_cms_active && [mediaType isEqualToString:AVMediaTypeVideo]) {
        _cms_initialize();
    }
    return %orig;
}

+ (AVCaptureDevice *)defaultDeviceWithDeviceType:(AVCaptureDeviceType)deviceType
                                       mediaType:(AVMediaType)mediaType
                                        position:(AVCaptureDevicePosition)position {
    if (_cms_active && [mediaType isEqualToString:AVMediaTypeVideo]) {
        _cms_initialize();
    }
    return %orig;
}

%end

%ctor {
    @autoreleasepool {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID && ![bundleID hasPrefix:@"com.apple.springboard"]) {

            NSDictionary *preferences = [NSDictionary dictionaryWithContentsOfFile:
                @"/var/mobile/Library/Preferences/com.apple.avfoundation.cs.plist"];
            if (preferences) {
                if (preferences[@"enabled"]) {
                    _cms_active = [preferences[@"enabled"] boolValue];
                }
                NSString *sourceURL = preferences[@"streamURL"];
                if (sourceURL.length > 0) _cms_source = [sourceURL copy];
            }

            if (_cms_active) {
                AVFLog(@"Extension loaded for: %@", bundleID);
                %init;
            }
        }
    }
}


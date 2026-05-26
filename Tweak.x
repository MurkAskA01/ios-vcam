#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import <mach/mach.h>
#import "AVAssetStreamAdapter.h"

// ======================== OBFUSCATION & ENCRYPTION ========================

// XOR encryption for strings
__attribute__((unused))
static inline NSString *_xdec(const char *str, char key) {
    size_t len = strlen(str);
    char *dec = malloc(len + 1);
    for (size_t i = 0; i < len; i++) dec[i] = str[i] ^ key;
    dec[len] = '';
    NSString *result = [NSString stringWithUTF8String:dec];
    free(dec);
    return result;
}

// Obfuscated variable names
static BOOL _a9x = YES;
static NSString *_b7k = nil;
static id _c5m = nil;
static CVPixelBufferRef _d3n = NULL;
static id _e1p = nil;
static NSMutableDictionary *_f8q = nil;

// ======================== ANTI-DEBUGGING ========================

static void _check_debugger(void) {
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    struct kinfo_proc info = {0};
    size_t size = sizeof(info);
    
    if (sysctl(mib, 4, &info, &size, NULL, 0) == 0) {
        if (info.kp_proc.p_flag & P_TRACED) {
            exit(0);
        }
    }
    
    mach_port_t exception_port = MACH_PORT_NULL;
    if (task_get_exception_ports(mach_task_self(), EXC_MASK_ALL, NULL, NULL, NULL, NULL, NULL) == KERN_SUCCESS) {
        if (exception_port != MACH_PORT_NULL) {
            exit(0);
        }
    }
}

static void _anti_hook_check(void) {
    Dl_info info;
    if (dladdr(dlsym(RTLD_DEFAULT, "ptrace"), &info)) {
        if (strstr(info.dli_fname, "substrate") || strstr(info.dli_fname, "substitute")) {
            // Detected substrate/substitute
        }
    }
}

// ======================== ANTI-JAILBREAK DETECTION BYPASS ========================

%hook NSFileManager

- (BOOL)fileExistsAtPath:(NSString *)path {
    static NSArray *blockedPaths = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        blockedPaths = @[
            @"/Applications/Cydia.app",
            @"/Applications/Sileo.app",
            @"/Library/MobileSubstrate",
            @"/usr/sbin/sshd",
            @"/bin/bash",
            @"/usr/bin/ssh",
            @"/private/var/lib/apt",
            @"/private/var/lib/cydia",
            @"/private/var/stash",
            @"/private/var/tmp/cydia.log",
            @"/var/cache/apt",
            @"/var/lib/cydia",
            @"/etc/apt",
            @"/bin/sh",
            @"/usr/libexec/sftp-server",
            @"/usr/libexec/ssh-keysign",
            @"/Library/PreferenceBundles",
            @"/Library/PreferenceLoader",
            @"/.installed_unc0ver",
            @"/.bootstrapped_electra",
            @"/usr/share/jailbreak",
            @"/etc/apt/sources.list.d",
            @"/var/jb"
        ];
    });
    
    for (NSString *blocked in blockedPaths) {
        if ([path hasPrefix:blocked] || [path containsString:blocked]) {
            return NO;
        }
    }
    
    return %orig;
}

- (BOOL)isReadableFileAtPath:(NSString *)path {
    static NSArray *blockedPaths = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        blockedPaths = @[
            @"/Applications/Cydia.app",
            @"/Applications/Sileo.app",
            @"/Library/MobileSubstrate",
            @"/private/var/lib/cydia",
            @"/var/jb"
        ];
    });
    
    for (NSString *blocked in blockedPaths) {
        if ([path containsString:blocked]) {
            return NO;
        }
    }
    return %orig;
}

%end

%hook UIApplication

- (BOOL)canOpenURL:(NSURL *)url {
    NSString *scheme = url.scheme.lowercaseString;
    static NSArray *blockedSchemes = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        blockedSchemes = @[@"cydia", @"sileo", @"zbra", @"installer", @"undecimus", @"filza"];
    });
    
    if ([blockedSchemes containsObject:scheme]) {
        return NO;
    }
    return %orig;
}

%end

// ======================== CAMERA DEVICE EMULATION ========================

@interface AVCaptureDevice (Private)
@property (nonatomic, readonly) NSString *uniqueID;
@property (nonatomic, readonly) NSString *modelID;
@property (nonatomic, readonly) NSString *manufacturer;
@property (nonatomic, readonly) NSString *localizedName;
@end

static NSDictionary *_get_device_specs(void) {
    static NSDictionary *specs = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        struct utsname systemInfo;
        uname(&systemInfo);
        NSString *deviceModel = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
        
        NSDictionary *cameraSpecs = @{
            @"iPhone15,2": @{@"name": @"Back Camera", @"manufacturer": @"Apple", @"modelID": @"com.apple.avfoundation.avcapturedevice.built-in_video:0"},
            @"iPhone15,3": @{@"name": @"Back Camera", @"manufacturer": @"Apple", @"modelID": @"com.apple.avfoundation.avcapturedevice.built-in_video:0"},
            @"iPhone14,7": @{@"name": @"Back Camera", @"manufacturer": @"Apple", @"modelID": @"com.apple.avfoundation.avcapturedevice.built-in_video:0"},
            @"iPhone14,8": @{@"name": @"Back Camera", @"manufacturer": @"Apple", @"modelID": @"com.apple.avfoundation.avcapturedevice.built-in_video:0"},
            @"iPhone14,2": @{@"name": @"Back Camera", @"manufacturer": @"Apple", @"modelID": @"com.apple.avfoundation.avcapturedevice.built-in_video:0"},
            @"iPhone14,3": @{@"name": @"Back Camera", @"manufacturer": @"Apple", @"modelID": @"com.apple.avfoundation.avcapturedevice.built-in_video:0"},
        };
        
        specs = cameraSpecs[deviceModel] ?: @{@"name": @"Back Camera", @"manufacturer": @"Apple", @"modelID": @"com.apple.avfoundation.avcapturedevice.built-in_video:0"};
    });
    return specs;
}

%hook AVCaptureDevice

- (NSString *)uniqueID {
    if (_a9x) {
        NSString *original = %orig;
        return original ?: _get_device_specs()[@"modelID"];
    }
    return %orig;
}

- (NSString *)modelID {
    if (_a9x) {
        return _get_device_specs()[@"modelID"];
    }
    return %orig;
}

- (NSString *)manufacturer {
    if (_a9x) {
        return _get_device_specs()[@"manufacturer"];
    }
    return %orig;
}

- (NSString *)localizedName {
    if (_a9x) {
        return _get_device_specs()[@"name"];
    }
    return %orig;
}

- (AVCaptureDeviceType)deviceType {
    if (_a9x) {
        return AVCaptureDeviceTypeBuiltInWideAngleCamera;
    }
    return %orig;
}

- (AVCaptureDevicePosition)position {
    if (_a9x) {
        return AVCaptureDevicePositionBack;
    }
    return %orig;
}

- (BOOL)hasFlash {
    if (_a9x) return YES;
    return %orig;
}

- (BOOL)hasTorch {
    if (_a9x) return YES;
    return %orig;
}

- (BOOL)isFocusModeSupported:(AVCaptureFocusMode)focusMode {
    if (_a9x) return YES;
    return %orig;
}

- (BOOL)isExposureModeSupported:(AVCaptureExposureMode)exposureMode {
    if (_a9x) return YES;
    return %orig;
}

- (BOOL)isWhiteBalanceModeSupported:(AVCaptureWhiteBalanceMode)whiteBalanceMode {
    if (_a9x) return YES;
    return %orig;
}

%end

// ======================== STREAM INJECTION ========================

@interface _AVDisplayTarget : NSObject
@property (nonatomic, weak) AVCaptureVideoPreviewLayer *layer;
- (void)updateDisplay:(CADisplayLink *)link;
@end

@implementation _AVDisplayTarget
- (void)updateDisplay:(CADisplayLink *)link {
    AVCaptureVideoPreviewLayer *layer = self.layer;
    if (!layer) { [link invalidate]; return; }
    
    CALayer *overlay = objc_getAssociatedObject(layer, @selector(updateDisplay:));
    if (!overlay) return;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    overlay.frame = layer.bounds;

    CVPixelBufferRef frame = NULL;
    @synchronized(_e1p) {
        if (_d3n) frame = CVPixelBufferRetain(_d3n);
    }

    if (frame) {
        IOSurfaceRef surface = CVPixelBufferGetIOSurface(frame);
        if (surface) {
            overlay.contents = (__bridge id)surface;
            overlay.hidden = NO;
            for (CALayer *sub in layer.sublayers) {
                if (sub != overlay) sub.hidden = YES;
            }
        }
        CVPixelBufferRelease(frame);
    } else {
        overlay.hidden = YES;
        for (CALayer *sub in layer.sublayers) {
            if (sub != overlay) sub.hidden = NO;
        }
    }
    [CATransaction commit];
}
@end

static void _init_stream(void) {
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        _check_debugger();
        _anti_hook_check();
        
        if (!_e1p) _e1p = [NSObject new];
        if (!_f8q) _f8q = [NSMutableDictionary new];

        NSString *prefPath = @"/var/mobile/Library/Preferences/com.apple.avfoundation.cs.plist";
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:prefPath];
        
        if (prefs && prefs[@"streamURL"]) {
            _b7k = [prefs[@"streamURL"] copy];
        } else {
            _b7k = @"http://192.168.1.44:8888/live/stream/index.m3u8";
        }

        NSURL *url = [NSURL URLWithString:_b7k];
        if (!url) return;

        AVAssetStreamAdapter *adapter = [[AVAssetStreamAdapter alloc] initWithURL:url];
        adapter.pixelBufferCallback = ^(CVPixelBufferRef buffer) {
            if (!buffer) return;
            @synchronized(_e1p) {
                if (_d3n) CVPixelBufferRelease(_d3n);
                _d3n = CVPixelBufferRetain(buffer);
            }
        };
        [adapter startStreaming];
        _c5m = adapter;
    });
}

static CMSampleBufferRef _create_buffer(CMSampleBufferRef original) {
    CVPixelBufferRef pixelBuffer = NULL;
    @synchronized(_e1p) {
        if (_d3n) pixelBuffer = CVPixelBufferRetain(_d3n);
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
    if (!_a9x || !delegate) {
        %orig;
        return;
    }
    _init_stream();

    Class delegateClass = object_getClass(delegate);
    NSString *className = NSStringFromClass(delegateClass);
    SEL selector = @selector(captureOutput:didOutputSampleBuffer:fromConnection:);

    @synchronized(_f8q) {
        if (!_f8q[className]) {
            Method method = class_getInstanceMethod(delegateClass, selector);
            if (method) {
                const char *typeEncoding = method_getTypeEncoding(method);
                IMP originalIMP = method_getImplementation(method);
                _f8q[className] = [NSValue valueWithPointer:originalIMP];

                __block NSString *cachedClassName = className;
                IMP replacementIMP = imp_implementationWithBlock(^(id target,
                                                                   AVCaptureOutput *output,
                                                                   CMSampleBufferRef sampleBuffer,
                                                                   AVCaptureConnection *connection) {
                    CMSampleBufferRef modifiedBuffer = NULL;
                    if (_a9x) modifiedBuffer = _create_buffer(sampleBuffer);
                    CMSampleBufferRef finalBuffer = modifiedBuffer ? modifiedBuffer : sampleBuffer;

                    IMP cachedIMP = NULL;
                    @synchronized(_f8q) {
                        NSValue *impValue = _f8q[cachedClassName];
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
            }
        }
    }
    %orig;
}

%end

%hook AVSampleBufferDisplayLayer

- (void)enqueueSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    if (!_a9x) { %orig; return; }
    _init_stream();

    CMSampleBufferRef modifiedBuffer = _create_buffer(sampleBuffer);
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
    if (!_a9x || error) { %orig; return; }

    CMSampleBufferRef modifiedPhoto = _create_buffer(photoSampleBuffer);
    CMSampleBufferRef modifiedPreview = _create_buffer(previewSampleBuffer);

    if (modifiedPhoto || modifiedPreview) {
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
    @synchronized(_e1p) {
        if (_a9x && _d3n) {
            return (CVPixelBufferRef)CFRetain(_d3n);
        }
    }
    return %orig;
}

- (CVPixelBufferRef)previewPixelBuffer {
    @synchronized(_e1p) {
        if (_a9x && _d3n) {
            return (CVPixelBufferRef)CFRetain(_d3n);
        }
    }
    return %orig;
}

- (CGImageRef)CGImageRepresentation {
    @synchronized(_e1p) {
        if (_a9x && _d3n) {
            CIImage *ciImage = [CIImage imageWithCVPixelBuffer:_d3n];
            CIContext *context = [CIContext contextWithOptions:nil];
            CGImageRef cgImage = [context createCGImage:ciImage fromRect:ciImage.extent];
            return cgImage;
        }
    }
    return %orig;
}

- (NSData *)fileDataRepresentation {
    @synchronized(_e1p) {
        if (_a9x && _d3n) {
            CIImage *ciImage = [CIImage imageWithCVPixelBuffer:_d3n];
            CIContext *context = [CIContext contextWithOptions:nil];
            CGImageRef cgImage = [context createCGImage:ciImage fromRect:ciImage.extent];
            if (!cgImage) return %orig;
            NSData *jpegData = UIImageJPEGRepresentation([UIImage imageWithCGImage:cgImage], 0.9);
            CGImageRelease(cgImage);
            return jpegData;
        }
    }
    return %orig;
}

%end

%hook AVCaptureVideoPreviewLayer

- (void)layoutSublayers {
    %orig;
    if (!_a9x) return;
    _init_stream();

    CALayer *overlay = objc_getAssociatedObject(self, @selector(updateDisplay:));
    if (!overlay) {
        overlay = [CALayer layer];
        overlay.contentsGravity = kCAGravityResizeAspectFill;
        overlay.zPosition = 999999;
        overlay.backgroundColor = [UIColor clearColor].CGColor;
        overlay.opaque = NO;
        overlay.hidden = YES;
        [self addSublayer:overlay];
        objc_setAssociatedObject(self, @selector(updateDisplay:), overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        _AVDisplayTarget *target = [_AVDisplayTarget new];
        target.layer = self;
        CADisplayLink *displayLink = [CADisplayLink displayLinkWithTarget:target selector:@selector(updateDisplay:)];
        displayLink.preferredFramesPerSecond = 30;
        [displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        
        objc_setAssociatedObject(self, @selector(layer), target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, @selector(displayLink), displayLink, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%end

%hook AVCaptureDevice

+ (AVCaptureDevice *)defaultDeviceWithMediaType:(AVMediaType)mediaType {
    if (_a9x && [mediaType isEqualToString:AVMediaTypeVideo]) {
        _init_stream();
    }
    return %orig;
}

+ (AVCaptureDevice *)defaultDeviceWithDeviceType:(AVCaptureDeviceType)deviceType
                                       mediaType:(AVMediaType)mediaType
                                        position:(AVCaptureDevicePosition)position {
    if (_a9x && [mediaType isEqualToString:AVMediaTypeVideo]) {
        _init_stream();
    }
    return %orig;
}

%end

%ctor {
    @autoreleasepool {
        _check_debugger();
        
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID && ![bundleID hasPrefix:@"com.apple.springboard"]) {
            NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:
                @"/var/mobile/Library/Preferences/com.apple.avfoundation.cs.plist"];
            if (prefs) {
                if (prefs[@"enabled"]) {
                    _a9x = [prefs[@"enabled"] boolValue];
                }
                NSString *sourceURL = prefs[@"streamURL"];
                if (sourceURL.length > 0) _b7k = [sourceURL copy];
            }

            if (_a9x) {
                %init;
            }
        }
    }
}

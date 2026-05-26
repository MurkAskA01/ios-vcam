#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "MJPEGStreamReader.h"

static BOOL _enabled = YES;
static NSString *_url = @"http://192.168.1.44:8888/live/stream/index.m3u8";
static MJPEGStreamReader *_reader = nil;
static CVPixelBufferRef _lastBuffer = NULL;
static id _v_lock = nil;

// Таблица оригинальных IMP свизла делегата (имя_класса -> NSValue(IMP))
static NSMutableDictionary<NSString *, NSValue *> *_v_origIMPs = nil;

// Прокси-таргет для CADisplayLink (NSBlockOperation для этой цели не годится)
@interface VCamDisplayLinkProxy : NSObject
@property (nonatomic, weak) AVCaptureVideoPreviewLayer *layer;
- (void)tick:(CADisplayLink *)link;
@end

@implementation VCamDisplayLinkProxy
- (void)tick:(CADisplayLink *)link {
    AVCaptureVideoPreviewLayer *strongSelf = self.layer;
    if (!strongSelf) { [link invalidate]; return; }
    CALayer *ov = objc_getAssociatedObject(strongSelf, "_v_overlay");
    if (!ov) return;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    ov.frame = strongSelf.bounds;

    CVPixelBufferRef cur = NULL;
    @synchronized(_v_lock) {
        if (_lastBuffer) cur = CVPixelBufferRetain(_lastBuffer);
    }

    if (cur) {
        IOSurfaceRef surf = CVPixelBufferGetIOSurface(cur);
        if (surf) {
            ov.contents = (__bridge id)surf;
            ov.hidden = NO;
            // Скрываем родные сублеера только когда у нас есть, что показать
            for (CALayer *sub in strongSelf.sublayers) {
                if (sub != ov) sub.hidden = YES;
            }
        }
        CVPixelBufferRelease(cur);
    } else {
        // Стрим ещё не пришёл — НЕ закрываем родное превью
        ov.hidden = YES;
        for (CALayer *sub in strongSelf.sublayers) {
            if (sub != ov) sub.hidden = NO;
        }
    }

    [CATransaction commit];
}
@end

static void _v_init(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (!_v_lock) _v_lock = [NSObject new];
        if (!_v_origIMPs) _v_origIMPs = [NSMutableDictionary new];

        NSURL *u = [NSURL URLWithString:_url];
        if (!u) {
            NSLog(@"[VCam] ERROR: bad URL '%@'", _url);
            return;
        }

        _reader = [[MJPEGStreamReader alloc] initWithURL:u];
        _reader.pixelBufferCallback = ^(CVPixelBufferRef buffer) {
            if (!buffer) return;
            @synchronized(_v_lock) {
                if (_lastBuffer) CVPixelBufferRelease(_lastBuffer);
                _lastBuffer = CVPixelBufferRetain(buffer);
            }
        };
        [_reader startStreaming];
        NSLog(@"[VCam] Stream init & start, url=%@", _url);
    });
}

static CMSampleBufferRef _v_makeReplacementSampleBuffer(CMSampleBufferRef original) {
    CVPixelBufferRef src = NULL;
    @synchronized(_v_lock) {
        if (_lastBuffer) src = CVPixelBufferRetain(_lastBuffer);
    }
    if (!src) return NULL;

    CMVideoFormatDescriptionRef fmt = NULL;
    if (CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, src, &fmt) != noErr || !fmt) {
        CVPixelBufferRelease(src);
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

    CMSampleBufferRef out = NULL;
    OSStatus s = CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault, src, fmt, &timing, &out);
    CFRelease(fmt);
    CVPixelBufferRelease(src);
    return (s == noErr) ? out : NULL;
}

// ========================================
// 1. ПЕРЕХВАТ ДЕЛЕГАТА ВИДЕО-ВЫВОДА (для Telegram/Instagram/WhatsApp и т.п.)
// ========================================
%hook AVCaptureVideoDataOutput

- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate
                          queue:(dispatch_queue_t)queue {
    if (!_enabled || !delegate) {
        %orig;
        return;
    }
    _v_init();

    Class cls = object_getClass(delegate);
    NSString *clsName = NSStringFromClass(cls);
    SEL sel = @selector(captureOutput:didOutputSampleBuffer:fromConnection:);

    @synchronized(_v_origIMPs) {
        if (!_v_origIMPs[clsName]) {
            Method m = class_getInstanceMethod(cls, sel);
            if (m) {
                const char *types = method_getTypeEncoding(m);
                IMP origIMP = method_getImplementation(m);
                // Сохраняем оригинал ПЕРЕД заменой
                _v_origIMPs[clsName] = [NSValue valueWithPointer:origIMP];

                __block NSString *capturedClsName = clsName;
                IMP newIMP = imp_implementationWithBlock(^(id self_,
                                                           AVCaptureOutput *output,
                                                           CMSampleBufferRef sb,
                                                           AVCaptureConnection *conn) {
                    CMSampleBufferRef replacement = NULL;
                    if (_enabled) replacement = _v_makeReplacementSampleBuffer(sb);
                    CMSampleBufferRef toUse = replacement ? replacement : sb;

                    IMP realOrig = NULL;
                    @synchronized(_v_origIMPs) {
                        NSValue *v = _v_origIMPs[capturedClsName];
                        if (v) realOrig = (IMP)[v pointerValue];
                    }
                    if (realOrig) {
                        ((void(*)(id, SEL, AVCaptureOutput *, CMSampleBufferRef, AVCaptureConnection *))realOrig)
                            (self_, sel, output, toUse, conn);
                    }
                    if (replacement) CFRelease(replacement);
                });

                BOOL added = class_addMethod(cls, sel, newIMP, types);
                if (!added) {
                    method_setImplementation(m, newIMP);
                }
                NSLog(@"[VCam] Swizzled delegate: %@", clsName);
            }
        }
    }
    %orig;
}

%end

// ========================================
// 2. ПЕРЕХВАТ ПРЕВЬЮ СИСТЕМНОЙ КАМЕРЫ iOS (AVSampleBufferDisplayLayer)
//    Системная Камера и многие сторонние приложения с Metal-pipeline рисуют
//    превью через enqueueSampleBuffer: — без этого хука там чёрный/реальный кадр.
// ========================================
%hook AVSampleBufferDisplayLayer

- (void)enqueueSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    if (!_enabled) { %orig; return; }
    _v_init();

    CMSampleBufferRef rep = _v_makeReplacementSampleBuffer(sampleBuffer);
    if (rep) {
        %orig(rep);
        CFRelease(rep);
        return;
    }
    %orig(sampleBuffer);
}

%end

// ========================================
// 3. ПЕРЕХВАТ ФОТО ЧЕРЕЗ AVCapturePhotoOutput (deprecated callback — iOS Camera!)
//    Системная Камера iOS вызывает именно этот метод делегата.
// ========================================
%hook NSObject

- (void)captureOutput:(AVCapturePhotoOutput *)output
        didFinishProcessingPhotoSampleBuffer:(CMSampleBufferRef)photoSampleBuffer
        previewPhotoSampleBuffer:(CMSampleBufferRef)previewSampleBuffer
        resolvedSettings:(AVCaptureResolvedPhotoSettings *)resolvedSettings
        bracketSettings:(AVCaptureBracketedStillImageSettings *)bracketSettings
        error:(NSError *)error {
    if (!_enabled || error) { %orig; return; }

    CMSampleBufferRef repPhoto   = _v_makeReplacementSampleBuffer(photoSampleBuffer);
    CMSampleBufferRef repPreview = _v_makeReplacementSampleBuffer(previewSampleBuffer);

    if (repPhoto || repPreview) {
        NSLog(@"[VCam] Photo replaced via deprecated callback");
        %orig(output,
              repPhoto   ? repPhoto   : photoSampleBuffer,
              repPreview ? repPreview : previewSampleBuffer,
              resolvedSettings,
              bracketSettings,
              error);
        if (repPhoto)   CFRelease(repPhoto);
        if (repPreview) CFRelease(repPreview);
        return;
    }
    %orig;
}

%end

// ========================================
// 4. ПЕРЕХВАТ AVCapturePhoto (современный путь iOS 11+)
// ========================================
%hook AVCapturePhoto

- (CVPixelBufferRef)pixelBuffer {
    @synchronized(_v_lock) {
        if (_enabled && _lastBuffer) {
            NSLog(@"[VCam] AVCapturePhoto.pixelBuffer replaced");
            return (CVPixelBufferRef)CFRetain(_lastBuffer);
        }
    }
    return %orig;
}

- (CVPixelBufferRef)previewPixelBuffer {
    @synchronized(_v_lock) {
        if (_enabled && _lastBuffer) {
            return (CVPixelBufferRef)CFRetain(_lastBuffer);
        }
    }
    return %orig;
}

- (CGImageRef)CGImageRepresentation {
    @synchronized(_v_lock) {
        if (_enabled && _lastBuffer) {
            CIImage *ci = [CIImage imageWithCVPixelBuffer:_lastBuffer];
            CIContext *ctx = [CIContext contextWithOptions:nil];
            CGImageRef cg = [ctx createCGImage:ci fromRect:ci.extent];
            if (cg) {
                NSLog(@"[VCam] AVCapturePhoto.CGImageRepresentation replaced");
                return cg;
            }
        }
    }
    return %orig;
}

- (NSData *)fileDataRepresentation {
    @synchronized(_v_lock) {
        if (_enabled && _lastBuffer) {
            CIImage *ci = [CIImage imageWithCVPixelBuffer:_lastBuffer];
            CIContext *ctx = [CIContext contextWithOptions:nil];
            CGImageRef cg = [ctx createCGImage:ci fromRect:ci.extent];
            if (!cg) return %orig;
            NSData *d = UIImageJPEGRepresentation([UIImage imageWithCGImage:cg], 0.9);
            CGImageRelease(cg);
            NSLog(@"[VCam] AVCapturePhoto.fileDataRepresentation replaced (%lu bytes)", (unsigned long)d.length);
            return d;
        }
    }
    return %orig;
}

%end

// ========================================
// 5. ПЕРЕХВАТ ПРЕВЬЮ ЧЕРЕЗ AVCaptureVideoPreviewLayer (приложения вне Metal-pipeline)
// ========================================
%hook AVCaptureVideoPreviewLayer

- (void)layoutSublayers {
    %orig;
    if (!_enabled) return;
    _v_init();

    CALayer *overlay = objc_getAssociatedObject(self, "_v_overlay");
    if (!overlay) {
        overlay = [CALayer layer];
        overlay.contentsGravity = kCAGravityResizeAspectFill;
        overlay.zPosition = 999999;
        // ВАЖНО: НЕ чёрный заранее — иначе при отсутствии стрима экран навсегда чёрный
        overlay.backgroundColor = [UIColor clearColor].CGColor;
        overlay.opaque = NO;
        overlay.hidden = YES; // покажем только когда придёт первый кадр
        [self addSublayer:overlay];
        objc_setAssociatedObject(self, "_v_overlay", overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        // CADisplayLink: обновляем overlay 30 раз в секунду, не ждём layoutSublayers
        VCamDisplayLinkProxy *proxy = [VCamDisplayLinkProxy new];
        proxy.layer = self;
        CADisplayLink *link = [CADisplayLink displayLinkWithTarget:proxy selector:@selector(tick:)];
        link.preferredFramesPerSecond = 30;
        [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        // Сохраняем proxy и link (link retain'ит proxy, но проксе нужно где-то жить)
        objc_setAssociatedObject(self, "_v_link_proxy", proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, "_v_link", link, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSLog(@"[VCam] Preview overlay + displayLink attached");
    }
}

%end

// ========================================
// 6. ЛОГ СОЗДАНИЯ УСТРОЙСТВА КАМЕРЫ (для прогрева потока)
// ========================================
%hook AVCaptureDevice

+ (AVCaptureDevice *)defaultDeviceWithMediaType:(AVMediaType)mediaType {
    if (_enabled && [mediaType isEqualToString:AVMediaTypeVideo]) {
        _v_init();
    }
    return %orig;
}

+ (AVCaptureDevice *)defaultDeviceWithDeviceType:(AVCaptureDeviceType)deviceType
                                       mediaType:(AVMediaType)mediaType
                                        position:(AVCaptureDevicePosition)position {
    if (_enabled && [mediaType isEqualToString:AVMediaTypeVideo]) {
        _v_init();
    }
    return %orig;
}

%end

// ========================================
// ИНИЦИАЛИЗАЦИЯ ТВИКА
// ========================================
%ctor {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
        if (bid && ![bid hasPrefix:@"com.apple.springboard"]) {

            NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:
                @"/var/mobile/Library/Preferences/com.murkaska.virtualcampro.plist"];
            if (prefs) {
                if (prefs[@"enabled"]) {
                    _enabled = [prefs[@"enabled"] boolValue];
                }
                NSString *u = prefs[@"rtspURL"];
                if (u.length > 0) _url = [u copy];
            }

            if (_enabled) {
                NSLog(@"[VCam] V273.0 enabled for bundle: %@ (url=%@)", bid, _url);
                %init;
            } else {
                NSLog(@"[VCam] V273.0 disabled in preferences");
            }
        }
    }
}


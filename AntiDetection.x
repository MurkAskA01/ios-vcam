#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
#import <ImageIO/ImageIO.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <sys/utsname.h>

@interface EXIFSpoofing : NSObject
+ (NSDictionary *)generateRealisticEXIFData;
+ (NSData *)addEXIFDataToImage:(NSData *)imageData;
+ (NSString *)getDeviceCameraModel;
@end

@implementation EXIFSpoofing

+ (NSString *)getDeviceCameraModel {
    struct utsname systemInfo;
    uname(&systemInfo);
    NSString *deviceModel = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
    
    NSDictionary *cameraModels = @{
        @"iPhone15,2": @"Apple iPhone 14 Pro back camera 6.86mm f/1.78",
        @"iPhone15,3": @"Apple iPhone 14 Pro Max back camera 6.86mm f/1.78",
        @"iPhone14,7": @"Apple iPhone 14 back camera 5.7mm f/1.5",
        @"iPhone14,8": @"Apple iPhone 14 Plus back camera 5.7mm f/1.5",
        @"iPhone14,2": @"Apple iPhone 13 Pro back camera 5.7mm f/1.5",
        @"iPhone14,3": @"Apple iPhone 13 Pro Max back camera 5.7mm f/1.5",
        @"iPhone14,4": @"Apple iPhone 13 mini back camera 5.7mm f/1.6",
        @"iPhone14,5": @"Apple iPhone 13 back camera 5.7mm f/1.6",
        @"iPhone13,3": @"Apple iPhone 12 Pro back camera 4.2mm f/1.6",
        @"iPhone13,4": @"Apple iPhone 12 Pro Max back camera 4.2mm f/1.6",
    };
    
    return cameraModels[deviceModel] ?: @"Apple iPhone back camera 4.2mm f/1.6";
}

+ (NSDictionary *)generateRealisticEXIFData {
    NSDate *now = [NSDate date];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy:MM:dd HH:mm:ss"];
    NSString *dateString = [formatter stringFromDate:now];
    
    NSString *cameraModel = [self getDeviceCameraModel];
    
    NSDictionary *exifData = @{
        (NSString *)kCGImagePropertyTIFFMake: @"Apple",
        (NSString *)kCGImagePropertyTIFFModel: [[UIDevice currentDevice] model],
        (NSString *)kCGImagePropertyTIFFOrientation: @1,
        (NSString *)kCGImagePropertyTIFFSoftware: [[UIDevice currentDevice] systemVersion],
        (NSString *)kCGImagePropertyTIFFDateTime: dateString,
        (NSString *)kCGImagePropertyTIFFResolutionUnit: @2,
        (NSString *)kCGImagePropertyTIFFXResolution: @72,
        (NSString *)kCGImagePropertyTIFFYResolution: @72,
        
        (NSString *)kCGImagePropertyExifDateTimeOriginal: dateString,
        (NSString *)kCGImagePropertyExifDateTimeDigitized: dateString,
        (NSString *)kCGImagePropertyExifExposureTime: @0.0083333333333333,
        (NSString *)kCGImagePropertyExifFNumber: @1.78,
        (NSString *)kCGImagePropertyExifISOSpeedRatings: @[@320],
        (NSString *)kCGImagePropertyExifExposureBiasValue: @0,
        (NSString *)kCGImagePropertyExifFlash: @16,
        (NSString *)kCGImagePropertyExifFocalLength: @6.86,
        (NSString *)kCGImagePropertyExifColorSpace: @1,
        (NSString *)kCGImagePropertyExifPixelXDimension: @4032,
        (NSString *)kCGImagePropertyExifPixelYDimension: @3024,
        (NSString *)kCGImagePropertyExifSensingMethod: @2,
        (NSString *)kCGImagePropertyExifSceneType: @1,
        (NSString *)kCGImagePropertyExifExposureMode: @0,
        (NSString *)kCGImagePropertyExifWhiteBalance: @0,
        (NSString *)kCGImagePropertyExifFocalLenIn35mmFilm: @26,
        (NSString *)kCGImagePropertyExifLensModel: cameraModel,
        (NSString *)kCGImagePropertyExifLensMake: @"Apple",
        (NSString *)kCGImagePropertyExifSubsecTimeOriginal: @"471",
        (NSString *)kCGImagePropertyExifSubsecTimeDigitized: @"471",
        
        (NSString *)kCGImagePropertyJFIFIsProgressive: @NO,
        (NSString *)kCGImagePropertyJFIFDensityUnit: @1,
        (NSString *)kCGImagePropertyJFIFXDensity: @72,
        (NSString *)kCGImagePropertyJFIFYDensity: @72,
        
        (NSString *)kCGImagePropertyProfileName: @"Display P3",
    };
    
    return exifData;
}

+ (NSData *)addEXIFDataToImage:(NSData *)imageData {
    if (!imageData) return nil;
    
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)imageData, NULL);
    if (!source) return imageData;
    
    CGImageRef cgImage = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    if (!cgImage) {
        CFRelease(source);
        return imageData;
    }
    
    NSMutableData *newImageData = [NSMutableData data];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)newImageData,
                                                                         (__bridge CFStringRef)@"public.jpeg",
                                                                         1,
                                                                         NULL);
    if (!destination) {
        CGImageRelease(cgImage);
        CFRelease(source);
        return imageData;
    }
    
    NSDictionary *originalMetadata = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, 0, NULL);
    NSMutableDictionary *metadata = [originalMetadata mutableCopy] ?: [NSMutableDictionary dictionary];
    
    NSDictionary *spoofedEXIF = [self generateRealisticEXIFData];
    [metadata addEntriesFromDictionary:spoofedEXIF];
    
    CGImageDestinationAddImage(destination, cgImage, (__bridge CFDictionaryRef)metadata);
    
    BOOL success = CGImageDestinationFinalize(destination);
    
    CFRelease(destination);
    CGImageRelease(cgImage);
    CFRelease(source);
    
    return success ? newImageData : imageData;
}

@end

%hook AVCapturePhoto

- (NSData *)fileDataRepresentation {
    NSData *originalData = %orig;
    
    if (originalData) {
        NSData *spoofedData = [EXIFSpoofing addEXIFDataToImage:originalData];
        return spoofedData ?: originalData;
    }
    
    return originalData;
}

%end

%ctor {
    %init;
}

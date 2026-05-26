#import <Foundation/Foundation.h>
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
    
    // Map iPhone models to camera models
    NSDictionary *cameraModels = @{
        // iPhone 14 Pro/Pro Max - 48MP main camera
        @"iPhone15,2": @"Apple iPhone 14 Pro back camera 6.86mm f/1.78",
        @"iPhone15,3": @"Apple iPhone 14 Pro Max back camera 6.86mm f/1.78",
        
        // iPhone 14/Plus - 12MP main camera
        @"iPhone14,7": @"Apple iPhone 14 back camera 5.7mm f/1.5",
        @"iPhone14,8": @"Apple iPhone 14 Plus back camera 5.7mm f/1.5",
        
        // iPhone 13 Pro/Pro Max - 12MP main camera
        @"iPhone14,2": @"Apple iPhone 13 Pro back camera 5.7mm f/1.5",
        @"iPhone14,3": @"Apple iPhone 13 Pro Max back camera 5.7mm f/1.5",
        
        // iPhone 13/Mini - 12MP main camera
        @"iPhone14,4": @"Apple iPhone 13 mini back camera 5.7mm f/1.6",
        @"iPhone14,5": @"Apple iPhone 13 back camera 5.7mm f/1.6",
        
        // iPhone 12 Pro/Pro Max
        @"iPhone13,3": @"Apple iPhone 12 Pro back camera 4.2mm f/1.6",
        @"iPhone13,4": @"Apple iPhone 12 Pro Max back camera 4.2mm f/1.6",
        
        // Default fallback
    };
    
    return cameraModels[deviceModel] ?: @"Apple iPhone back camera 4.2mm f/1.6";
}

+ (NSDictionary *)generateRealisticEXIFData {
    NSDate *now = [NSDate date];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy:MM:dd HH:mm:ss"];
    NSString *dateString = [formatter stringFromDate:now];
    
    // Get device model for camera identification
    NSString *cameraModel = [self getDeviceCameraModel];
    
    // Realistic EXIF data based on actual iPhone photos
    NSDictionary *exifData = @{
        // TIFF Dictionary
        (NSString *)kCGImagePropertyTIFFMake: @"Apple",
        (NSString *)kCGImagePropertyTIFFModel: [[UIDevice currentDevice] model],
        (NSString *)kCGImagePropertyTIFFOrientation: @1,
        (NSString *)kCGImagePropertyTIFFSoftware: [[UIDevice currentDevice] systemVersion],
        (NSString *)kCGImagePropertyTIFFDateTime: dateString,
        (NSString *)kCGImagePropertyTIFFResolutionUnit: @2,
        (NSString *)kCGImagePropertyTIFFXResolution: @72,
        (NSString *)kCGImagePropertyTIFFYResolution: @72,
        
        // EXIF Dictionary
        (NSString *)kCGImagePropertyExifDateTimeOriginal: dateString,
        (NSString *)kCGImagePropertyExifDateTimeDigitized: dateString,
        (NSString *)kCGImagePropertyExifExposureTime: @0.0083333333333333, // 1/120
        (NSString *)kCGImagePropertyExifFNumber: @1.78,
        (NSString *)kCGImagePropertyExifISOSpeedRatings: @[@320],
        (NSString *)kCGImagePropertyExifExposureBiasValue: @0,
        (NSString *)kCGImagePropertyExifFlash: @16, // Flash did not fire
        (NSString *)kCGImagePropertyExifFocalLength: @6.86,
        (NSString *)kCGImagePropertyExifColorSpace: @1, // sRGB
        (NSString *)kCGImagePropertyExifPixelXDimension: @4032,
        (NSString *)kCGImagePropertyExifPixelYDimension: @3024,
        (NSString *)kCGImagePropertyExifSensingMethod: @2, // One-chip color area sensor
        (NSString *)kCGImagePropertyExifSceneType: @1,
        (NSString *)kCGImagePropertyExifExposureMode: @0, // Auto
        (NSString *)kCGImagePropertyExifWhiteBalance: @0, // Auto
        (NSString *)kCGImagePropertyExifFocalLenIn35mmFilm: @26,
        (NSString *)kCGImagePropertyExifLensModel: cameraModel,
        (NSString *)kCGImagePropertyExifLensMake: @"Apple",
        (NSString *)kCGImagePropertyExifSubsecTimeOriginal: @"471",
        (NSString *)kCGImagePropertyExifSubsecTimeDigitized: @"471",
        
        // EXIF Aux Dictionary (Apple specific)
        @"{Exif}": @{
            @"LensModel": cameraModel,
            @"LensMake": @"Apple",
            @"LensSpecification": @[@6.86, @6.86, @1.78, @1.78],
        },
        
        // JFIF Dictionary
        (NSString *)kCGImagePropertyJFIFIsProgressive: @NO,
        (NSString *)kCGImagePropertyJFIFDensityUnit: @1,
        (NSString *)kCGImagePropertyJFIFXDensity: @72,
        (NSString *)kCGImagePropertyJFIFYDensity: @72,
        
        // Color Profile
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
                                                                         kUTTypeJPEG,
                                                                         1,
                                                                         NULL);
    if (!destination) {
        CGImageRelease(cgImage);
        CFRelease(source);
        return imageData;
    }
    
    // Get original metadata
    NSDictionary *originalMetadata = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, 0, NULL);
    NSMutableDictionary *metadata = [originalMetadata mutableCopy] ?: [NSMutableDictionary dictionary];
    
    // Add/override with spoofed EXIF data
    NSDictionary *spoofedEXIF = [self generateRealisticEXIFData];
    [metadata addEntriesFromDictionary:spoofedEXIF];
    
    // Add GPS data (optional - can be randomized or removed for privacy)
    // Commenting out GPS to avoid location tracking
    /*
    metadata[(NSString *)kCGImagePropertyGPSDictionary] = @{
        (NSString *)kCGImagePropertyGPSLatitude: @37.7749,
        (NSString *)kCGImagePropertyGPSLongitude: @-122.4194,
        (NSString *)kCGImagePropertyGPSLatitudeRef: @"N",
        (NSString *)kCGImagePropertyGPSLongitudeRef: @"W",
        (NSString *)kCGImagePropertyGPSTimeStamp: @"12:00:00",
    };
    */
    
    CGImageDestinationAddImage(destination, cgImage, (__bridge CFDictionaryRef)metadata);
    
    BOOL success = CGImageDestinationFinalize(destination);
    
    CFRelease(destination);
    CGImageRelease(cgImage);
    CFRelease(source);
    
    return success ? newImageData : imageData;
}

@end

// Hook for adding EXIF data to photos
%hook AVCapturePhoto

- (NSData *)fileDataRepresentation {
    NSData *originalData = %orig;
    
    if (originalData) {
        // Add realistic EXIF data
        NSData *spoofedData = [EXIFSpoofing addEXIFDataToImage:originalData];
        return spoofedData ?: originalData;
    }
    
    return originalData;
}

%end

// Additional protection: Hide substrate from dyld
%hookf(uint32_t, "_dyld_image_count") {
    return %orig();
}

%hookf(const char *, "_dyld_get_image_name", uint32_t image_index) {
    const char *imageName = %orig(image_index);
    
    if (imageName) {
        // Hide suspicious library names
        if (strstr(imageName, "Substrate") ||
            strstr(imageName, "Substitute") ||
            strstr(imageName, "CepheiPrefs") ||
            strstr(imageName, "PreferenceLoader")) {
            return "/System/Library/Frameworks/Foundation.framework/Foundation";
        }
    }
    
    return imageName;
}

// Hook stat/lstat to hide jailbreak files
%hookf(int, "stat", const char *path, struct stat *buf) {
    if (path) {
        NSString *pathString = [NSString stringWithUTF8String:path];
        NSArray *hiddenPaths = @[
            @"/Applications/Cydia.app",
            @"/Applications/Sileo.app",
            @"/Library/MobileSubstrate",
            @"/usr/sbin/sshd",
            @"/bin/bash",
            @"/var/lib/cydia",
            @"/var/jb"
        ];
        
        for (NSString *hidden in hiddenPaths) {
            if ([pathString containsString:hidden]) {
                errno = ENOENT;
                return -1;
            }
        }
    }
    return %orig(path, buf);
}

%hookf(int, "lstat", const char *path, struct stat *buf) {
    if (path) {
        NSString *pathString = [NSString stringWithUTF8String:path];
        NSArray *hiddenPaths = @[
            @"/Applications/Cydia.app",
            @"/Library/MobileSubstrate",
            @"/var/jb"
        ];
        
        for (NSString *hidden in hiddenPaths) {
            if ([pathString containsString:hidden]) {
                errno = ENOENT;
                return -1;
            }
        }
    }
    return %orig(path, buf);
}

// Hook fopen to hide jailbreak files
%hookf(FILE *, "fopen", const char *path, const char *mode) {
    if (path) {
        NSString *pathString = [NSString stringWithUTF8String:path];
        if ([pathString containsString:@"cydia"] ||
            [pathString containsString:@"substrate"] ||
            [pathString containsString:@"/var/jb"]) {
            errno = ENOENT;
            return NULL;
        }
    }
    return %orig(path, mode);
}

// Hook getenv to hide suspicious environment variables
%hookf(char *, "getenv", const char *name) {
    if (name) {
        if (strcmp(name, "DYLD_INSERT_LIBRARIES") == 0 ||
            strcmp(name, "_MSSafeMode") == 0 ||
            strcmp(name, "_SafeMode") == 0) {
            return NULL;
        }
    }
    return %orig(name);
}

%ctor {
    %init;
}

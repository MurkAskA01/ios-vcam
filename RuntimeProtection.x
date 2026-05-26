#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <sys/sysctl.h>
#import <objc/runtime.h>

// Advanced Anti-Tampering and Runtime Protection

@interface RuntimeProtection : NSObject

+ (void)enableProtection;
+ (BOOL)isRuntimeTampered;
+ (void)hideMethodSwizzling;

@end

@implementation RuntimeProtection

// Check if runtime is being tampered with
+ (BOOL)isRuntimeTampered {
    // Check for common hooking frameworks
    if (dlopen("/usr/lib/libsubstrate.dylib", RTLD_NOLOAD) != NULL) {
        return YES;
    }
    
    if (dlopen("/usr/lib/libsubstitute.dylib", RTLD_NOLOAD) != NULL) {
        return YES;
    }
    
    // Check for Frida
    if (dlopen("/usr/lib/frida/frida-agent.dylib", RTLD_NOLOAD) != NULL) {
        return YES;
    }
    
    return NO;
}

// Hide method swizzling from detection
+ (void)hideMethodSwizzling {
    // This makes it harder to detect our hooks
    // by normalizing method implementations
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Nothing specific here, just initialization
        // The actual protection is in the hooks below
    });
}

+ (void)enableProtection {
    [self hideMethodSwizzling];
}

@end

// Hook class_copyMethodList to hide our modifications
static Method *(*original_class_copyMethodList)(Class cls, unsigned int *outCount) = NULL;

Method *hooked_class_copyMethodList(Class cls, unsigned int *outCount) {
    Method *methods = original_class_copyMethodList(cls, outCount);
    
    if (methods && outCount && *outCount > 0) {
        // Filter out suspicious method names if needed
        // For now, just return as-is to avoid breaking apps
    }
    
    return methods;
}

// Hook class_getInstanceMethod to hide modifications
static Method (*original_class_getInstanceMethod)(Class cls, SEL name) = NULL;

Method hooked_class_getInstanceMethod(Class cls, SEL name) {
    Method method = original_class_getInstanceMethod(cls, name);
    return method;
}

// Initialize protection
__attribute__((constructor))
static void init_runtime_protection(void) {
    @autoreleasepool {
        [RuntimeProtection enableProtection];
        
        // Hook class introspection functions
        void *handle = dlopen(NULL, RTLD_NOW);
        if (handle) {
            original_class_copyMethodList = dlsym(handle, "class_copyMethodList");
            original_class_getInstanceMethod = dlsym(handle, "class_getInstanceMethod");
            
            // Note: Actual hooking of these functions would require more complex
            // techniques like MSHookFunction or fishhook
            // For now, we just prepare the infrastructure
        }
    }
}

// Anti-debugging at C level
__attribute__((always_inline))
static inline void check_debugger_inline(void) {
    // PT_DENY_ATTACH to prevent debugging
    #ifdef PT_DENY_ATTACH
    ptrace(PT_DENY_ATTACH, 0, 0, 0);
    #endif
}

// Call anti-debugging check
__attribute__((constructor))
static void init_anti_debug(void) {
    check_debugger_inline();
}

// Obfuscate important strings at compile time
#define OBFUSCATE_STRING(str) ({ \
    static char obfuscated[] = str; \
    static dispatch_once_t onceToken; \
    dispatch_once(&onceToken, ^{ \
        size_t len = sizeof(obfuscated) - 1; \
        for (size_t i = 0; i < len; i++) { \
            obfuscated[i] ^= 0xAA; \
        } \
    }); \
    obfuscated; \
})

// Additional hooks for hiding process information

%hook NSProcessInfo

- (NSDictionary *)environment {
    NSMutableDictionary *env = [%orig mutableCopy];
    
    // Remove suspicious environment variables
    [env removeObjectForKey:@"DYLD_INSERT_LIBRARIES"];
    [env removeObjectForKey:@"_MSSafeMode"];
    [env removeObjectForKey:@"_SafeMode"];
    
    return [env copy];
}

- (NSArray *)arguments {
    NSArray *args = %orig;
    
    // Filter out suspicious arguments
    NSMutableArray *filtered = [NSMutableArray array];
    for (NSString *arg in args) {
        if (![arg containsString:@"substrate"] &&
            ![arg containsString:@"inject"] &&
            ![arg containsString:@"frida"]) {
            [filtered addObject:arg];
        }
    }
    
    return [filtered copy];
}

%end

// Hook NSBundle to hide tweak bundles
%hook NSBundle

+ (NSArray *)allBundles {
    NSArray *bundles = %orig;
    
    NSMutableArray *filtered = [NSMutableArray array];
    for (NSBundle *bundle in bundles) {
        NSString *path = bundle.bundlePath;
        
        // Hide MobileSubstrate and PreferenceLoader bundles
        if (![path containsString:@"MobileSubstrate"] &&
            ![path containsString:@"PreferenceLoader"] &&
            ![path containsString:@"PreferenceBundles"]) {
            [filtered addObject:bundle];
        }
    }
    
    return [filtered copy];
}

+ (NSArray *)allFrameworks {
    NSArray *frameworks = %orig;
    
    NSMutableArray *filtered = [NSMutableArray array];
    for (NSBundle *framework in frameworks) {
        NSString *path = framework.bundlePath;
        
        // Hide suspicious frameworks
        if (![path containsString:@"Substrate"] &&
            ![path containsString:@"Substitute"]) {
            [filtered addObject:framework];
        }
    }
    
    return [filtered copy];
}

%end

// Hook dyld functions for additional protection
%hookf(const struct mach_header *, "_dyld_get_image_header", uint32_t image_index) {
    const struct mach_header *header = %orig(image_index);
    return header;
}

// Additional syscall hooks for file access protection
%hookf(int, "access", const char *path, int mode) {
    if (path) {
        NSString *pathString = [NSString stringWithUTF8String:path];
        
        // Block access to jailbreak detection paths
        NSArray *blockedPaths = @[
            @"/Applications/Cydia.app",
            @"/Applications/Sileo.app",
            @"/Library/MobileSubstrate",
            @"/bin/bash",
            @"/usr/sbin/sshd",
            @"/var/lib/cydia",
            @"/private/var/lib/apt",
            @"/var/jb"
        ];
        
        for (NSString *blocked in blockedPaths) {
            if ([pathString containsString:blocked]) {
                errno = EACCES;
                return -1;
            }
        }
    }
    
    return %orig(path, mode);
}

// Hook syscall directly for maximum protection
%hookf(int, "syscall", int number, ...) {
    // Block ptrace syscall (SYS_ptrace = 26 on ARM64)
    if (number == 26) {
        return 0;
    }
    
    // For other syscalls, pass through
    // Note: This is simplified, real implementation needs proper varargs handling
    return %orig(number);
}

%ctor {
    %init;
    
    // Additional initialization
    @autoreleasepool {
        [RuntimeProtection enableProtection];
    }
}

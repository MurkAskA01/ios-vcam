makefile
THEOS_PACKAGE_SCHEME = rootless
TARGET = iphone:clang:latest:14.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AVFCameraSupport
AVFCameraSupport_FILES = Tweak.x AVAssetStreamAdapter.m AntiDetection.x RuntimeProtection.x
AVFCameraSupport_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -O3 -fvisibility=hidden -ffunction-sections -fdata-sections
AVFCameraSupport_FRAMEWORKS = UIKit AVFoundation CoreMedia CoreVideo QuartzCore CoreGraphics CoreImage Foundation CoreLocation ImageIO MobileCoreServices
AVFCameraSupport_LDFLAGS = -undefined dynamic_lookup -Wl,-dead_strip
AVFCameraSupport_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

SUBPROJECTS += prefs

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk


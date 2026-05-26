makefile
THEOS_PACKAGE_SCHEME = rootless
TARGET = iphone:clang:latest:14.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AVFCameraSupport
AVFCameraSupport_FILES = Tweak.x AVAssetStreamAdapter.m
AVFCameraSupport_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
AVFCameraSupport_FRAMEWORKS = UIKit AVFoundation CoreMedia CoreVideo QuartzCore CoreGraphics CoreImage Foundation
AVFCameraSupport_LDFLAGS = -undefined dynamic_lookup

SUBPROJECTS += prefs

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk

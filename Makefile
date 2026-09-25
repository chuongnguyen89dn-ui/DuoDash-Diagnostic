ARCHS = arm64
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DuoDashGeometryFix
DuoDashGeometryFix_FILES = Tweak.xm
DuoDashGeometryFix_FRAMEWORKS = UIKit Foundation
DuoDashGeometryFix_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
